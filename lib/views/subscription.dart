import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/views/subscription_pay.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Ключ нашей подписки: сначала выбранный профиль, потом любой наш.
///
/// Человек мог добавить и чужую подписку, и спрашивать наш сервер о чужом ключе незачем —
/// [accessKeyOf] такие и отсеивает. Одна функция на экран подписки и блок на главном: два
/// разных правила выбора ключа показали бы на двух экранах два разных срока.
String? ourAccessKey(ProfilesState state) {
  final ordered = [
    ...state.profiles.where((profile) => profile.id == state.currentProfileId),
    ...state.profiles,
  ];
  for (final profile in ordered) {
    final key = accessKeyOf(profile.url);
    if (key != null) return key;
  }
  return null;
}

/// Есть ли экран выбора: карта (её показываем с акцентом даже одну) или монеты.
bool hasPaymentMethodScreen(AccountStatus status) =>
    status.cardEnabled || (status.coinsEnabled && status.coins.isNotEmpty);

/// Можно ли заплатить внутри приложения хоть чем-то; нет — остаётся сайт.
bool canPayInApp(AccountStatus status) =>
    status.usdtEnabled || hasPaymentMethodScreen(status);

/// Оплата тарифа: карта РФ / СБП и монеты — на экране выбора; старый сервер без монет и без
/// карты — прежний путь USDT; не настроено ничего — сайт.
///
/// Одна дорога для экрана подписки и блока на главном: вторая копия разошлась бы с первой
/// ровно на том способе, который добавят следующим. Возвращается после возврата человека —
/// вызывающий перечитывает статус: карта подтверждается уведомлением платёжки, а не здесь.
Future<void> openPayment(
  BuildContext context,
  AccountStatus status,
  Plan plan,
  String accessKey,
) async {
  if (hasPaymentMethodScreen(status)) {
    await BaseNavigator.push<bool>(
      context,
      PaymentMethodView(status: status, plan: plan, accessKey: accessKey),
    );
    return;
  }
  if (!status.usdtEnabled) {
    await dialogs.openUrl(accountUrl);
    return;
  }
  final result = await request.createUsdtInvoice(accessKey, plan.code);
  if (!context.mounted) return;
  if (result.isError) return complainPayment(context, result.message);
  await BaseNavigator.push(
    context,
    _UsdtPayView(invoice: result.data!, accessKey: accessKey),
  );
}

/// Пробный: страница платёжки в браузере, а без телеграма — сперва бот привязки (сервер продаёт
/// пробный один на телеграм). Вызывающий перечитывает статус после возврата.
Future<void> openTrial(
  BuildContext context,
  TrialOffer trial,
  String accessKey,
) async {
  final result = trial.needTelegram
      ? await request.bindTelegram(accessKey)
      : await request.createTrialPayment(accessKey);
  if (!context.mounted) return;
  if (result.isError) return complainPayment(context, result.message);
  await dialogs.openUrl(result.data!);
}

String trialOfferText(BuildContext context, TrialOffer trial) {
  final l = context.appLocalizations;
  return l.trialOffer(l.daysCount(trial.days), trial.price);
}

/// Завести аккаунт: профиль ставится сразу, ссылка входа показывается сразу.
///
/// Показать её обязательно и именно здесь: аккаунт из приложения ни к чему не привязан, и
/// человек, потерявший ссылку, теряет вход на сайт навсегда. Приложение её не хранит —
/// хранить ссылку входа значит хранить пароль.
Future<void> createAccountFlow(BuildContext context, WidgetRef ref) async {
  final result = await request.createAccount();
  if (!context.mounted) return;
  if (result.isError) return complainPayment(context, result.message);
  final account = result.data!;
  await ref
      .read(profilesActionProvider.notifier)
      .addProfileFormURL(account.subUrl);
  if (!context.mounted) return;
  // Не окно со ссылкой, а экран возврата доступа: почта и телеграм вперёд, ссылка последней.
  // Показать ссылку первой значит предложить как основной способ то, что равно паролю.
  await BaseNavigator.push(
    context,
    RecoveryView(accessKey: account.key, loginUrl: account.loginUrl),
  );
}

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
/// ОПЛАТА (05-10): экран выбора способа [PaymentMethodView] — карта РФ / СБП первой (её страница
/// принадлежит платёжной системе и открывается у неё), ниже монеты напрямую со счётом внутри
/// приложения. Старый сервер без монет — прежний путь USDT.
class SubscriptionView extends ConsumerStatefulWidget {
  final Future<Result<AccountStatus>> Function(String key)? fetchStatus;
  final Future<Result<AccountStatus>> Function(String key, String code)?
  redeemPromo;

  const SubscriptionView({super.key, this.fetchStatus, this.redeemPromo});

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

  String? get _key => ourAccessKey(ref.read(profilesStateProvider));

  Future<void> _load() async {
    final key = _key;
    if (key == null) {
      if (mounted) setState(() => _status = null);
      return;
    }
    setState(() => _busy = true);
    final result = await (widget.fetchStatus ?? request.accountStatus)(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result.isSuccess ? result.data : null;
      _errorCode = result.isError ? result.message : null;
    });
  }

  Future<void> _createAccount() async {
    setState(() => _busy = true);
    await createAccountFlow(context, ref);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  /// Статус перечитывается при любом возврате, а не только после зачтённой монеты: карта
  /// уходит в браузер, и её подтверждение приходит уведомлением платёжки.
  Future<void> _choosePayment(AccountStatus status, Plan plan) async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    await openPayment(context, status, plan, key);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _startTrial(TrialOffer trial) async {
    final key = _key;
    if (key == null) return;
    setState(() => _busy = true);
    await openTrial(context, trial, key);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _enterPromo() async {
    final key = _key;
    if (key == null) return;
    final status = await showDialog<AccountStatus>(
      context: context,
      builder: (_) => PromoDialog(
        accessKey: key,
        redeem: widget.redeemPromo ?? request.redeemPromo,
      ),
    );
    if (status == null || !mounted) return;
    setState(() => _status = status);
    final promo = status.trial?.promo;
    if (promo != null) {
      dialogs.showNotifier(
        context.appLocalizations.promoApplied(promo),
        level: MessageLevel.success,
      );
    }
  }

  Widget _buildTrial(TrialOffer trial) {
    final l = context.appLocalizations;
    final promo = trial.promo;
    final offer = trialOfferText(context, trial);
    return generateSectionV3(
      title: l.trialPeriod,
      items: [
        DecorationListItem(
          title: Text(
            promo == null ? offer : '$offer · ${l.trialPromo(promo)}',
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trial.needTelegram ? l.trialNeedTelegram : l.trialDesc),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : () => _startTrial(trial),
                child: Text(
                  trial.needTelegram ? l.bindTelegram : l.trialButton,
                ),
              ),
              if (promo == null)
                TextButton(
                  onPressed: _busy ? null : _enterPromo,
                  child: Text(l.havePromoCode),
                ),
            ],
          ),
        ),
      ],
    );
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
    final trial = status.trial;
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
        if (trial != null) ...[const SizedBox(height: 12), _buildTrial(trial)],
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
                trailing: canPayInApp(status)
                    ? FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _choosePayment(status, plan),
                        child: Text(
                          hasPaymentMethodScreen(status) ? l.pay : l.payUsdt,
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

/// Promo code entry (08-10): same rules as the site form; the answer is a fresh status with the
/// week-long trial. Refusals stay inside the dialog, in the app's language.
class PromoDialog extends StatefulWidget {
  final String accessKey;
  final Future<Result<AccountStatus>> Function(String key, String code) redeem;

  const PromoDialog({super.key, required this.accessKey, required this.redeem});

  @override
  State<PromoDialog> createState() => _PromoDialogState();
}

class _PromoDialogState extends State<PromoDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final code = _controller.text.trim();
    if (code.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.redeem(widget.accessKey, code);
    if (!mounted) return;
    if (result.isSuccess) {
      Navigator.of(context).pop(result.data);
      return;
    }
    setState(() {
      _busy = false;
      _error = serverErrorText(context.appLocalizations, result.message);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return AlertDialog(
      title: Text(l.promoCode),
      content: TextField(
        key: const ValueKey('promo-field'),
        controller: _controller,
        autofocus: true,
        enabled: !_busy,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9_-]')),
          LengthLimitingTextInputFormatter(20),
        ],
        decoration: InputDecoration(hintText: 'MGLA2026', errorText: _error),
        onSubmitted: (_) => _apply(),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: _busy ? null : _apply,
          child: Text(l.promoApply),
        ),
      ],
    );
  }
}
