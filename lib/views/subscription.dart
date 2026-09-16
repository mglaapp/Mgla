import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Подписка целиком в приложении: срок, трафик, покупка и продление.
///
/// ЗАЧЕМ ЭКРАН СУЩЕСТВУЕТ. Приложение выложено публично, и его ставят, ещё не купив доступ.
/// До 16-09 такой человек упирался в поле «ключ доступа», а заплативший не имел в приложении
/// ни одного пути к продлению — обе дороги вели в браузер. Решение владельца: аккаунт, статус
/// и оплата должны быть здесь.
///
/// ГДЕ ЛЕЖИТ КЛЮЧ. Нигде отдельно: он вынимается из адреса профиля ([accessKeyOf]). Вторая
/// копия секрета разошлась бы с первой молча, и разошлась бы она ровно в тот момент, когда
/// человек платит.
///
/// ЧЕГО ЗДЕСЬ НЕТ. Карты и крипто-шлюза: их страница принадлежит платёжной системе и обязана
/// открываться у неё. Для них кнопка честно уводит на сайт, а не притворяется, что платит.
class SubscriptionView extends ConsumerStatefulWidget {
  const SubscriptionView({super.key});

  @override
  ConsumerState<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends ConsumerState<SubscriptionView> {
  AccountStatus? _status;
  String? _errorCode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  String? get _key {
    final state = ref.read(profilesStateProvider);
    // Сначала выбранный профиль, потом любой наш: человек мог добавить и чужую подписку,
    // и спрашивать наш сервер о чужом ключе незачем — [accessKeyOf] такие и отсеивает.
    final ordered = [
      ...state.profiles.where(
        (profile) => profile.id == state.currentProfileId,
      ),
      ...state.profiles,
    ];
    for (final profile in ordered) {
      final key = accessKeyOf(profile.url);
      if (key != null) return key;
    }
    return null;
  }

  Future<void> _load() async {
    final key = _key;
    if (key == null) {
      if (mounted) setState(() => _status = null);
      return;
    }
    setState(() => _busy = true);
    final result = await request.accountStatus(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result.isSuccess ? result.data : null;
      _errorCode = result.isError ? result.message : null;
    });
  }

  /// Завести аккаунт: профиль ставится сразу, ссылка входа показывается сразу.
  ///
  /// Показать её обязательно и именно здесь: аккаунт из приложения ни к чему не привязан, и
  /// человек, потерявший ссылку, теряет вход на сайт навсегда. Приложение её не хранит —
  /// хранить ссылку входа значит хранить пароль.
  Future<void> _createAccount() async {
    setState(() => _busy = true);
    final result = await request.createAccount();
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) {
      _complain(result.message);
      return;
    }
    final account = result.data!;
    await ref
        .read(profilesActionProvider.notifier)
        .addProfileFormURL(account.subUrl);
    if (!mounted) return;
    // Не окно со ссылкой, а экран возврата доступа: почта и телеграм вперёд, ссылка последней.
    // Показать ссылку первой значит предложить как основной способ то, что равно паролю.
    await BaseNavigator.push(
      context,
      RecoveryView(accessKey: account.key, loginUrl: account.loginUrl),
    );
    await _load();
  }

  /// Чем платить. Спрашиваем ТОЛЬКО когда есть из чего выбирать: лишний экран между
  /// человеком и оплатой — это люди, которые не доходят.
  Future<void> _choosePayment(AccountStatus status, Plan plan) async {
    if (status.usdtEnabled && !status.cardEnabled) return _pay(plan);
    if (status.cardEnabled && !status.usdtEnabled) return _payCard(plan);
    if (!status.usdtEnabled && !status.cardEnabled) {
      await dialogs.openUrl(accountUrl);
      return;
    }
    final l = context.appLocalizations;
    final choice = await dialogs.showCommonDialog<String>(
      child: CommonDialog(
        title: l.choosePayment,
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('card'),
            child: Text(l.payCard),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('usdt'),
            child: Text(l.payUsdt),
          ),
        ],
        child: Text(plan.title),
      ),
    );
    if (choice == 'usdt') return _pay(plan);
    if (choice == 'card') return _payCard(plan);
  }

  /// Оплата картой уходит в браузер целиком: у платёжной системы своя страница, свои правила
  /// и свой 3-D Secure. Подтверждение приходит к нам её уведомлением, поэтому возвращаться в
  /// приложение и что-то нажимать человеку не нужно — статус подтянется сам.
  Future<void> _payCard(Plan plan) async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    final result = await request.createCardPayment(key, plan.code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) {
      _complain(result.message);
      return;
    }
    await dialogs.openUrl(result.data!);
  }

  Future<void> _pay(Plan plan) async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    final result = await request.createUsdtInvoice(key, plan.code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) {
      _complain(result.message);
      return;
    }
    await BaseNavigator.push(
      context,
      _UsdtPayView(invoice: result.data!, accessKey: key),
    );
    await _load();
  }

  void _complain(String code) {
    final l = context.appLocalizations;
    dialogs.showNotifier(switch (code) {
      'unknown_key' => l.errUnknownKey,
      'usdt_off' => l.errUsdtOff,
      'card_off' => l.errCardOff,
      'too_many' => l.errTooMany,
      _ => l.errNetwork,
    }, level: MessageLevel.error);
  }

  Widget _buildNoAccount() {
    final l = context.appLocalizations;
    return CommonCard(
      type: CommonCardType.filled,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.subscription, style: context.textTheme.titleMedium?.toBold),
            const SizedBox(height: 8),
            Text(
              l.accessKeyDesc,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _createAccount,
                  icon: const Icon(Icons.person_add_alt),
                  label: Text(l.createAccount),
                ),
                const AccessKeyButton(),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(AccountStatus status) {
    final l = context.appLocalizations;
    final expire = status.expiresAt;
    final quota = status.quotaGb;
    final used = status.usedGb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        generateSectionV3(
          title: status.active ? l.accessPaidUntil : l.accessNotPaid,
          items: [
            DecorationListItem(
              title: Text(
                expire != null ? expire.show : l.accessNotPaid,
                style: context.textTheme.titleMedium?.toBold,
              ),
              subtitle: quota != null
                  ? TooltipLabel('${used ?? 0} / $quota GB')
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        generateSectionV3(
          title: l.recoverAccess,
          items: [
            DecorationListItem(
              title: Text(l.recoverAccess),
              subtitle: TooltipLabel(l.recoverAccessTip),
              // Ссылки входа тут нет и быть не может: сервер отдаёт её только при создании.
              // Позже остаются почта и телеграм — и это честнее, чем показать пустое место.
              onPressed: () => BaseNavigator.push(
                context,
                RecoveryView(accessKey: status.key),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 12),
        generateSectionV3(
          title: status.active ? l.renewSubscription : l.getSubscription,
          items: [
            for (final plan in status.plans)
              DecorationListItem(
                title: Text(plan.title),
                subtitle: TooltipLabel('\$${plan.usd.toStringAsFixed(2)}'),
                trailing: (status.usdtEnabled || status.cardEnabled)
                    ? FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _choosePayment(status, plan),
                        child: Text(
                          status.usdtEnabled && !status.cardEnabled
                              ? l.payUsdt
                              : (status.cardEnabled && !status.usdtEnabled
                                    ? l.payCard
                                    : l.pay),
                        ),
                      )
                    : TextButton(
                        onPressed: () => dialogs.openUrl(accountUrl),
                        child: Text(l.payOnSite),
                      ),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Профили меняются снаружи (человек добавил ключ на другом экране) — перечитываем статус,
    // иначе экран остаётся с ответом «ключа нет» при уже добавленном ключе.
    ref.listen(profilesStateProvider, (_, _) => unawaited(_load()));
    final status = _status;
    return BaseScaffold(
      title: context.appLocalizations.subscription,
      actions: [
        IconButton(
          tooltip: context.appLocalizations.sync,
          onPressed: _busy ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: ListView(
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (status == null) _buildNoAccount() else _buildStatus(status),
            if (_errorCode != null) ...[
              const SizedBox(height: 12),
              Text(
                context.appLocalizations.errNetwork,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Счёт на USDT: адрес, точная сумма и кнопка «я оплатил».
///
/// Сумма и адрес даются с копированием, а не только текстом: ручной ввод суммы — главный
/// источник «перевёл не столько, доступ не включился», и на сайте ровно для этого стоит QR.
class _UsdtPayView extends ConsumerStatefulWidget {
  final UsdtInvoice invoice;
  final String accessKey;

  const _UsdtPayView({required this.invoice, required this.accessKey});

  @override
  ConsumerState<_UsdtPayView> createState() => _UsdtPayViewState();
}

class _UsdtPayViewState extends ConsumerState<_UsdtPayView> {
  bool _busy = false;

  Future<void> _check() async {
    setState(() => _busy = true);
    final result = await request.checkUsdtPayment(widget.accessKey);
    if (!mounted) return;
    setState(() => _busy = false);
    final l = context.appLocalizations;
    if (result.isSuccess && result.data!.active) {
      dialogs.showNotifier(l.paymentReceived, level: MessageLevel.info);
      Navigator.of(context).pop();
      return;
    }
    // «Не видно» — это не отказ: перевод в сети идёт минутами, и пугать человека словом
    // «ошибка» здесь значит гнать его в поддержку за тем, что решится само.
    dialogs.showNotifier(l.paymentNotSeen);
  }

  Widget _row(String label, String value) {
    return DecorationListItem(
      title: Text(label),
      subtitle: TooltipLabel(value),
      trailing: IconButton(
        tooltip: context.appLocalizations.copy,
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (mounted) {
            dialogs.showNotifier(context.appLocalizations.copy);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final invoice = widget.invoice;
    return BaseScaffold(
      title: l.payUsdt,
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: ListView(
          children: [
            if (invoice.qrSvg.isNotEmpty) ...[
              // Картинка собрана сервером. Кошелёк подставит адрес и сумму сам — ручной ввод
              // суммы это главный источник «перевёл не столько, доступ не включился».
              Center(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: SvgPicture.string(
                    invoice.qrSvg,
                    width: 200,
                    height: 200,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            generateSectionV3(
              title: l.payUsdt,
              items: [
                _row(l.usdtAmount, invoice.amount),
                _row(l.usdtAddress, invoice.address),
                DecorationListItem(
                  title: Text(l.usdtNetwork),
                  subtitle: TooltipLabel(invoice.network),
                ),
                DecorationListItem(
                  title: Text(l.minutesLeftLabel),
                  subtitle: TooltipLabel('${invoice.minutesLeft}'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.done),
                label: Text(l.iPaid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Как вернуть доступ: почта, телеграм и — последней — ссылка входа.
///
/// ПОРЯДОК ЗДЕСЬ НЕ ОФОРМЛЕНИЕ, А РЕШЕНИЕ ВЛАДЕЛЬЦА (16-09, то же, что на сайте 13-09):
/// почта и телеграм вперёд, ссылка последней и свёрнутой. Пока ссылка стояла первой, она
/// читалась как основной способ — а она равна паролю и теряется вместе с устройством.
///
/// ТАЙМЕР НА КНОПКЕ ПОДТВЕРЖДЕНИЯ — тоже решение владельца, и он не про «подождать». Кнопка,
/// доступная сразу, нажимается до чтения: человек подтверждает, что понял про пароль, не
/// прочитав про пароль. Четыре секунды — цена одного прочтения предупреждения.
///
/// ССЫЛКА ПОКАЗЫВАЕТСЯ ТОЛЬКО ПРИ СОЗДАНИИ. Сервер отдаёт её один раз, по ключу подписки не
/// отдаёт никогда, и приложение её не хранит: хранить ссылку входа значит хранить пароль.
/// Поэтому на этот экран, открытый позже, её попросту нет — и раздела тоже нет.
class RecoveryView extends ConsumerStatefulWidget {
  final String accessKey;
  final String? loginUrl;

  const RecoveryView({super.key, required this.accessKey, this.loginUrl});

  @override
  ConsumerState<RecoveryView> createState() => _RecoveryViewState();
}

class _RecoveryViewState extends ConsumerState<RecoveryView> {
  /// Сколько секунд кнопка подтверждения остаётся недоступной после раскрытия ссылки.
  static const _readSeconds = 4;

  final _email = TextEditingController();
  bool _busy = false;
  bool _mailSent = false;
  bool _linkShown = false;
  int _countdown = _readSeconds;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _email.dispose();
    super.dispose();
  }

  void _showLink() {
    setState(() {
      _linkShown = true;
      _countdown = _readSeconds;
    });
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _countdown -= 1);
      if (_countdown <= 0) timer.cancel();
    });
  }

  Future<void> _sendMail() async {
    final address = _email.text.trim();
    if (address.isEmpty) return;
    setState(() => _busy = true);
    final result = await request.bindEmail(widget.accessKey, address);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _mailSent = result.isSuccess;
    });
    if (result.isError) {
      _complain(result.message);
      return;
    }
    dialogs.showNotifier(context.appLocalizations.letterSent);
  }

  Future<void> _bindTelegram() async {
    setState(() => _busy = true);
    final result = await request.bindTelegram(widget.accessKey);
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) {
      _complain(result.message);
      return;
    }
    await dialogs.openUrl(result.data!);
  }

  void _complain(String code) {
    final l = context.appLocalizations;
    dialogs.showNotifier(switch (code) {
      'bad_email' => l.errBadEmail,
      'mail_off' => l.errMailOff,
      'mail_err' => l.errMailOff,
      'tg_off' => l.errTgOff,
      'too_soon' => l.errTooSoon,
      'too_many' => l.errTooMany,
      'unknown_key' => l.errUnknownKey,
      _ => l.errNetwork,
    }, level: MessageLevel.error);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final loginUrl = widget.loginUrl;
    return BaseScaffold(
      title: l.recoverAccess,
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: ListView(
          children: [
            Text(
              l.recoverAccessTip,
              style: context.textTheme.bodyMedium?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            generateSectionV3(
              title: l.bindEmail,
              items: [
                DecorationListItem(
                  title: TextField(
                    controller: _email,
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: l.emailAddress,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  subtitle: _mailSent ? TooltipLabel(l.letterSent) : null,
                  trailing: IconButton(
                    tooltip: l.sendLetter,
                    onPressed: _busy ? null : _sendMail,
                    icon: const Icon(Icons.send),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            generateSectionV3(
              title: l.bindTelegram,
              items: [
                DecorationListItem(
                  title: Text(l.bindTelegram),
                  trailing: FilledButton(
                    onPressed: _busy ? null : _bindTelegram,
                    child: Text(l.confirm),
                  ),
                ),
              ],
            ),
            if (loginUrl != null && loginUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              generateSectionV3(
                title: l.loginLinkTitle,
                items: [
                  DecorationListItem(
                    title: Text(
                      l.loginLinkWarning,
                      style: context.textTheme.bodySmall?.copyWith(
                        color: context.colorScheme.error,
                      ),
                    ),
                  ),
                  if (!_linkShown)
                    DecorationListItem(
                      title: Text(l.showLink),
                      trailing: TextButton(
                        onPressed: _showLink,
                        child: Text(l.showLink),
                      ),
                    )
                  else ...[
                    DecorationListItem(
                      title: SelectableText(
                        loginUrl,
                        style: context.textTheme.bodySmall,
                      ),
                      trailing: IconButton(
                        tooltip: l.copy,
                        icon: const Icon(Icons.copy),
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: loginUrl),
                          );
                          if (mounted) dialogs.showNotifier(l.copy);
                        },
                      ),
                    ),
                    DecorationListItem(
                      title: FilledButton(
                        // Недоступна, пока идёт отсчёт: подтверждение «я понял» до чтения
                        // предупреждения ничего не подтверждает.
                        onPressed: _countdown > 0
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: Text(
                          _countdown > 0
                              ? '${l.savedIt} ($_countdown)'
                              : l.savedIt,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
