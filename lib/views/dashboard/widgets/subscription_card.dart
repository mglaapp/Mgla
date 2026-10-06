import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Сколько дней до конца срока плитка подсвечивает как «пора продлевать».
const subscriptionWarnDays = 3;

/// Плитка подписки на панели: срок одной строкой и компактная «Продлить» (решение 06-10).
///
/// Обычная плитка сетки ([DashboardWidget.subscription]): добавляется и убирается в режиме
/// правки, как соседние. «Продлить» ведёт сразу к оплате тем же путём, что экран подписки
/// ([openPayment]); нажатие на плитку открывает подробности.
class SubscriptionCard extends ConsumerStatefulWidget {
  /// Откуда брать статус; по умолчанию — наш сервер. Подменяется в тестах.
  final Future<Result<AccountStatus>> Function(String key)? fetchStatus;

  const SubscriptionCard({super.key, this.fetchStatus});

  @override
  ConsumerState<SubscriptionCard> createState() => _SubscriptionCardState();
}

class _SubscriptionCardState extends ConsumerState<SubscriptionCard> {
  AccountStatus? _status;
  String? _loadedKey;
  bool _loaded = false;
  bool _failed = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final key = ourAccessKey(ref.read(profilesStateProvider));
    _loadedKey = key;
    if (key == null) {
      if (mounted) {
        setState(() {
          _status = null;
          _loaded = true;
          _failed = false;
        });
      }
      return;
    }
    if (mounted) setState(() => _busy = true);
    final fetch = widget.fetchStatus ?? request.accountStatus;
    final result = await fetch(key);
    // Ключ сменился, пока шёл запрос: этот ответ про чужой срок, его перезапишет новый.
    if (!mounted || _loadedKey != key) return;
    setState(() {
      _busy = false;
      _loaded = true;
      _failed = result.isError;
      // Сбой сети не стирает прошлый ответ: срок, виденный минуту назад, вернее пустоты.
      if (result.isSuccess) _status = result.data;
    });
  }

  Future<Plan?> _pickPlan(List<Plan> plans) async {
    if (plans.length == 1) return plans.first;
    final l = context.appLocalizations;
    return showDialog<Plan>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l.choosePlan),
        children: [
          for (final plan in plans)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(plan),
              child: Row(
                children: [
                  Expanded(child: Text(plan.title)),
                  Text(
                    '\$${plan.usd.toStringAsFixed(2)}',
                    style: dialogContext.textTheme.titleSmall?.toBold,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _renew(AccountStatus status) async {
    final key = _loadedKey;
    if (key == null) return;
    if (!canPayInApp(status)) {
      await dialogs.openUrl(accountUrl);
      return;
    }
    if (status.plans.isEmpty) return _openDetails();
    final plan = await _pickPlan(status.plans);
    if (plan == null || !mounted) return;
    setState(() => _busy = true);
    await openPayment(context, status, plan, key);
    if (!mounted) return;
    setState(() => _busy = false);
    // Перечитываем при любом возврате: карта подтверждается уведомлением платёжки, не здесь.
    await _load();
  }

  Future<void> _openDetails() async {
    if (_busy) return;
    await BaseNavigator.push(context, const SubscriptionView());
    if (mounted) await _load();
  }

  Future<void> _createAccount() async {
    setState(() => _busy = true);
    await createAccountFlow(context, ref);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Widget _action({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color? accent,
  }) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton.filledTonal(
        tooltip: tooltip,
        iconSize: 18,
        padding: EdgeInsets.zero,
        style: accent == null
            ? null
            : IconButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: accent == MglaPalette.warn
                    ? MglaPalette.warnOn
                    : context.colorScheme.onError,
              ),
        onPressed: _busy ? null : onPressed,
        icon: Icon(icon),
      ),
    );
  }

  Widget get _spinner => const SizedBox(
    width: 32,
    height: 32,
    child: Padding(
      padding: EdgeInsets.all(8),
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  bool _isSoon(AccountStatus status) {
    final days = status.daysLeft;
    return status.active && days != null && days <= subscriptionWarnDays;
  }

  (String, Color, Widget) _content() {
    final l = context.appLocalizations;
    final scheme = context.colorScheme;
    final status = _status;
    if (_loadedKey == null && _loaded) {
      return (
        l.noAccountShort,
        scheme.onSurfaceVariant,
        _action(
          icon: Icons.person_add_alt,
          tooltip: l.createAccount,
          onPressed: _createAccount,
        ),
      );
    }
    if (status == null) {
      if (_loaded && _failed) {
        return (
          l.offlineShort,
          scheme.error,
          _action(icon: Icons.refresh, tooltip: l.sync, onPressed: _load),
        );
      }
      return ('…', scheme.onSurfaceVariant, _spinner);
    }
    final action = _busy
        ? _spinner
        : _action(
            icon: status.active ? Icons.autorenew : Icons.payments_outlined,
            tooltip: status.active ? l.renewSubscription : l.getSubscription,
            onPressed: () => _renew(status),
            accent: !status.active
                ? context.colorScheme.error
                : _isSoon(status)
                ? MglaPalette.warn
                : null,
          );
    final expire = status.expiresAt;
    if (!status.active || expire == null) {
      return (l.accessNotPaid, scheme.error, action);
    }
    final days = status.daysLeft;
    final line = days == null
        ? l.subscriptionUntil(expire.show)
        : l.subscriptionUntilDays('$days', expire.show);
    return (
      line,
      _isSoon(status) ? MglaPalette.warn : scheme.onSurface,
      action,
    );
  }

  @override
  Widget build(BuildContext context) {
    // Перечитываем только при смене КЛЮЧА: состояние профилей меняется и от обновления
    // трафика подписки, и запрос к серверу на каждое такое событие был бы шумом.
    ref.listen(profilesStateProvider, (_, next) {
      if (ourAccessKey(next) != _loadedKey) unawaited(_load());
    });
    final (line, color, action) = _content();
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        radius: AppCorner.lg,
        info: Info(
          label: context.appLocalizations.subscription,
          iconData: Icons.card_membership,
        ),
        onPressed: _openDetails,
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 4, bottom: 8, right: 8),
          child: Row(
            children: [
              Expanded(
                child: TooltipText(
                  text: Text(
                    line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleSmall
                        ?.adjustSize(-2)
                        .copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              action,
            ],
          ),
        ),
      ),
    );
  }
}
