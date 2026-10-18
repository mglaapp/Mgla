import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:fl_clash/views/subscription_pay.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_ui/material_ui.dart';

/// Opens [TvLoginView] and turns the key it brings back into a profile.
Future<void> signInWithPhone(BuildContext context, WidgetRef ref) async {
  final url = await BaseNavigator.push<String>(context, const TvLoginView());
  if (url == null) return;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(ref.read(profilesActionProvider.notifier).addProfileFormURL(url));
  });
}

TvCodeCallBack onTvLink(WidgetRef ref) =>
    (code) => unawaited(confirmTvSignIn(ref, code));

/// Phone side of mgla://tv?c=CODE: hands this phone's key to the TV showing that code.
Future<void> confirmTvSignIn(
  WidgetRef ref,
  String code, {
  Future<Result<bool>> Function(String key, String code)? send,
}) async {
  final l = currentAppLocalizations;
  final key = ourAccessKey(ref.read(profilesStateProvider));
  if (key == null) {
    await dialogs.showMessage(
      title: l.connectTv,
      message: TextSpan(text: l.tvNeedsKey),
      cancelable: false,
    );
    return;
  }
  final clean = code.trim().toUpperCase();
  final shown = clean.length == 6
      ? '${clean.substring(0, 3)} ${clean.substring(3)}'
      : clean;
  final res = await dialogs.showMessage(
    title: l.connectTv,
    message: TextSpan(text: l.connectTvConfirm(shown)),
    confirmText: l.connectTv,
  );
  if (res != true) return;
  final result = await (send ?? request.tvConfirm)(key, clean);
  if (result.isError) {
    dialogs.showNotifier(
      serverErrorText(l, result.message),
      level: MessageLevel.error,
    );
    return;
  }
  dialogs.showNotifier(result.data! ? l.tvConnected : l.tvConnectedInactive);
}

/// TV side: a QR and a short code on screen, polled until a phone confirms it.
///
/// Pops with the subscription URL. An expired code is not renewed by itself: a TV left on this
/// screen overnight would otherwise ask the server for a new code every ten minutes.
class TvLoginView extends ConsumerStatefulWidget {
  final Future<Result<TvLoginStart>> Function()? start;
  final Future<Result<TvPoll>> Function(String code, String secret)? poll;

  const TvLoginView({super.key, this.start, this.poll});

  @override
  ConsumerState<TvLoginView> createState() => _TvLoginViewState();
}

class _TvLoginViewState extends ConsumerState<TvLoginView> {
  TvLoginStart? _login;
  String? _errorCode;
  bool _expired = false;
  bool _polling = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _timer?.cancel();
    setState(() {
      _login = null;
      _errorCode = null;
      _expired = false;
    });
    final result = await (widget.start ?? request.tvStart)();
    if (!mounted) return;
    if (result.isError) {
      setState(() => _errorCode = result.message);
      return;
    }
    final login = result.data!;
    setState(() => _login = login);
    _timer = Timer.periodic(
      Duration(seconds: login.pollEvery),
      (_) => _poll(login),
    );
  }

  Future<void> _poll(TvLoginStart login) async {
    if (_polling) return;
    _polling = true;
    final result = await (widget.poll ?? request.tvPoll)(
      login.code,
      login.secret,
    );
    _polling = false;
    if (!mounted || !identical(login, _login) || result.isError) return;
    final poll = result.data!;
    if (poll.done) {
      _timer?.cancel();
      Navigator.of(context).pop(subscriptionUrlOf(poll.key));
      return;
    }
    if (poll.state == 'expired' || poll.state == 'bad') {
      _timer?.cancel();
      setState(() => _expired = true);
    }
  }

  Widget _retry(String text, String action) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text, style: context.textTheme.titleMedium),
        const SizedBox(height: 16),
        FilledButton(autofocus: true, onPressed: _start, child: Text(action)),
      ],
    );
  }

  Widget _code(TvLoginStart login) {
    final l = context.appLocalizations;
    final site = Uri.tryParse(login.url);
    final siteText = site == null ? login.url : '${site.host}${site.path}';
    final muted = context.textTheme.bodyLarge?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.tvScanQr, style: context.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(l.tvOrEnterCode(siteText), style: muted),
        const SizedBox(height: 12),
        SelectableText(
          login.codeText,
          style: context.textTheme.displayMedium?.copyWith(
            fontFamily: 'monospace',
            letterSpacing: 6,
            color: context.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l.tvWaiting, style: muted),
          ],
        ),
      ],
    );
    if (login.qrSvg.isEmpty) return text;
    final qr = Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: SvgPicture.string(login.qrSvg, width: 220, height: 220),
    );
    return LayoutBuilder(
      builder: (context, constraints) => constraints.maxWidth >= 600
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                qr,
                const SizedBox(width: 40),
                Flexible(child: text),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [qr, const SizedBox(height: 24), text],
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final login = _login;
    final errorCode = _errorCode;
    final Widget body;
    if (errorCode != null) {
      body = _retry(serverErrorText(l, errorCode), l.redo);
    } else if (_expired) {
      body = _retry(l.tvCodeExpired, l.tvNewCode);
    } else if (login == null) {
      body = const CircularProgressIndicator();
    } else {
      body = _code(login);
    }
    return BaseScaffold(
      title: l.signInWithPhone,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }
}
