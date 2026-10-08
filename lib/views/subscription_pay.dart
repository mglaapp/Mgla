import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Выбор способа оплаты (05-10): карта РФ / СБП первой, ниже монеты напрямую.
///
/// ПОРЯДОК — РЕШЕНИЕ ВЛАДЕЛЬЦА: так платит большинство, и акцент — на российские карты и СБП,
/// а не на крипту. Тот же вид, что страница оплаты на сайте: монета одной строкой, сети
/// раскрываются внутри, редкие монеты — под «Ещё».
///
/// Возвращает true, если оплата монетой зачтена прямо здесь (экран подписки перечитает статус).
class PaymentMethodView extends ConsumerStatefulWidget {
  final AccountStatus status;
  final Plan plan;
  final String accessKey;

  const PaymentMethodView({
    super.key,
    required this.status,
    required this.plan,
    required this.accessKey,
  });

  @override
  ConsumerState<PaymentMethodView> createState() => _PaymentMethodViewState();
}

class _PaymentMethodViewState extends ConsumerState<PaymentMethodView> {
  /// С какой ширины способы встают в ряд, как на сайте (просьба владельца 06-10).
  static const _rowBreakpoint = 900.0;

  bool _busy = false;
  bool _showRest = false;

  /// Карта уходит в браузер целиком: страница оплаты принадлежит платёжной системе.
  Future<void> _payCard() async {
    setState(() => _busy = true);
    final result = await request.createCardPayment(
      widget.accessKey,
      widget.plan.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) return complainPayment(context, result.message);
    await dialogs.openUrl(result.data!);
  }

  /// Скины — тоже в браузер: страница OmniSkin, там вход через Steam и обмен с ботом. Тариф
  /// включится, когда обмен примут; статус экран подписки перечитает при возврате.
  Future<void> _paySkins() async {
    setState(() => _busy = true);
    final result = await request.createSkinsPayment(
      widget.accessKey,
      widget.plan.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) return complainPayment(context, result.message);
    await dialogs.openUrl(result.data!);
  }

  Future<void> _payCoin(CoinNet net) async {
    setState(() => _busy = true);
    final result = await request.createCryptoInvoice(
      widget.accessKey,
      widget.plan.code,
      net.code,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.isError) return complainPayment(context, result.message);
    final paid = await BaseNavigator.push<bool>(
      context,
      CryptoPayView(invoice: result.data!, accessKey: widget.accessKey),
    );
    if (paid == true && mounted) Navigator.of(context).pop(true);
  }

  /// Монета с одной сетью — сразу счёт; с несколькими — короткий выбор сети.
  Future<void> _pickCoin(CoinGroup group) async {
    if (group.nets.length == 1) return _payCoin(group.nets.first);
    final net = await showDialog<CoinNet>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Row(
          children: [
            CoinIcon(group.icon, size: 26),
            const SizedBox(width: 10),
            Text(group.sym),
          ],
        ),
        children: [
          for (final net in group.nets)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(net),
              child: Row(
                children: [
                  CoinIcon(net.icon, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(net.network)),
                  const Icon(Icons.chevron_right, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (net != null && mounted) await _payCoin(net);
  }

  /// Одна форма для всех способов: заголовок, значки, пара строк и кнопка обычного размера
  /// снизу. Растянутая во всю ширину кнопка при двух строках текста выглядела плакатом
  /// (скрин владельца 06-10). В ряду (fill) кнопки выравниваются по низу.
  Widget _method({
    required String title,
    List<Widget> chips = const [],
    required String text,
    required Widget action,
    Widget? extra,
    bool accent = false,
    required bool fill,
  }) {
    final scheme = context.colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: accent ? scheme.primary : scheme.outlineVariant,
          width: accent ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Text(title, style: context.textTheme.titleMedium?.toBold),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: chips),
          ],
          const SizedBox(height: 10),
          Text(
            text,
            style: context.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
          ?extra,
          if (fill) const Spacer() else const SizedBox(height: 16),
          if (fill) const SizedBox(height: 16),
          action,
        ],
      ),
    );
  }

  Widget _cardBlock(bool fill) {
    final l = context.appLocalizations;
    return _method(
      title: l.payCardSbp,
      accent: true,
      fill: fill,
      chips: const [
        _Chip('МИР', background: Color(0xFF0F754E)),
        _Chip('СБП', background: Color(0xFF5B57A2)),
        _Chip('Visa'),
        _Chip('Mastercard'),
      ],
      text: l.payCardSbpDesc,
      action: FilledButton.icon(
        onPressed: _busy ? null : _payCard,
        icon: const Icon(Icons.credit_card, size: 18),
        label: Text(l.payCardSbpButton),
      ),
    );
  }

  Widget _skinsBlock(bool fill) {
    final l = context.appLocalizations;
    return _method(
      title: l.paySkins,
      fill: fill,
      chips: const [_Chip('CS2'), _Chip('Dota 2'), _Chip('Rust'), _Chip('TF2')],
      text: l.paySkinsDesc('\$${widget.plan.usd.toStringAsFixed(2)}'),
      action: OutlinedButton.icon(
        onPressed: _busy ? null : _paySkins,
        icon: const Icon(Icons.inventory_2_outlined, size: 18),
        label: Text(l.paySkinsButton),
      ),
    );
  }

  /// Плитка монеты: значок, тикер и одна короткая строка — сеть или «6 сетей».
  Widget _coinTile(CoinGroup group, double width) {
    final l = context.appLocalizations;
    final scheme = context.colorScheme;
    final single = group.nets.length == 1;
    return SizedBox(
      width: width,
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : () => _pickCoin(group),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CoinIcon(group.icon, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.sym,
                        style: context.textTheme.titleSmall?.toBold,
                      ),
                      Text(
                        single
                            ? group.nets.first.network
                            : l.networksCount(group.nets.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!single)
                  Icon(
                    Icons.expand_more,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// [inner] — ширина содержимого карточки: плитки считаются от неё заранее. LayoutBuilder тут
  /// нельзя — в ряду карточки меряются IntrinsicHeight, а LayoutBuilder своих размеров не отдаёт.
  Widget _cryptoBlock(List<CoinGroup> coins, bool fill, double inner) {
    final l = context.appLocalizations;
    final top = coins.where((group) => group.popular).toList();
    final rest = coins.where((group) => !group.popular).toList();
    final shown = [
      ...(top.isEmpty ? rest : top),
      if (_showRest && top.isNotEmpty) ...rest,
    ];
    const gap = 8.0;
    final cols = (inner / 150).floor().clamp(1, 3);
    final width = ((inner - gap * (cols - 1)) / cols).floorToDouble();
    final grid = Wrap(
      spacing: gap,
      runSpacing: gap,
      children: [for (final group in shown) _coinTile(group, width)],
    );
    return _method(
      title: l.cryptocurrency,
      fill: fill,
      text: l.cryptoDesc,
      extra: Padding(padding: const EdgeInsets.only(top: 14), child: grid),
      action: top.isNotEmpty && rest.isNotEmpty
          ? TextButton.icon(
              onPressed: () => setState(() => _showRest = !_showRest),
              icon: Icon(_showRest ? Icons.expand_less : Icons.expand_more),
              label: Text(
                _showRest
                    ? l.moreCoins
                    : '${l.moreCoins}: ${rest.map((group) => group.sym).join(', ')}',
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final status = widget.status;
    final coins = status.coinsEnabled ? status.coins : const <CoinGroup>[];
    return BaseScaffold(
      title: l.choosePayment,
      body: LayoutBuilder(
        builder: (_, constraints) {
          final count = [
            status.cardEnabled,
            coins.isNotEmpty,
            status.skinsEnabled,
          ].where((on) => on).length;
          // В ряд — только когда есть что ставить рядом: один способ в «ряду» растягивался бы
          // под высоту, которой у прокрутки нет (поймано тестом блока подписки 06-10).
          final row = constraints.maxWidth >= _rowBreakpoint && count > 1;
          final content = (constraints.maxWidth - 40).clamp(
            0.0,
            row ? 1080.0 : 560.0,
          );
          final column = row ? (content - 14 * (count - 1)) / count : content;
          final blocks = [
            if (status.cardEnabled) _cardBlock(row),
            if (coins.isNotEmpty) _cryptoBlock(coins, row, column - 38),
            if (status.skinsEnabled) _skinsBlock(row),
          ];
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: row ? 1080 : 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    Text(
                      '${widget.plan.title} — '
                      '\$${widget.plan.usd.toStringAsFixed(2)}',
                      style: context.textTheme.headlineSmall?.toBold,
                    ),
                    const SizedBox(height: 16),
                    if (row)
                      // Ряд одной высоты: кнопки по низу, как на сайте.
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = 0; i < blocks.length; i++) ...[
                              if (i > 0) const SizedBox(width: 14),
                              Expanded(child: blocks[i]),
                            ],
                          ],
                        ),
                      )
                    else
                      for (var i = 0; i < blocks.length; i++) ...[
                        if (i > 0) const SizedBox(height: 12),
                        blocks[i],
                      ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Счёт на оплату монетой: QR, точная сумма, адрес, сеть и «Я оплатил».
///
/// Сумма и адрес — с копированием, а не только текстом: ручной ввод суммы — главный источник
/// «перевёл не столько, доступ не включился». Возвращает true, когда счёт зачтён.
class CryptoPayView extends ConsumerStatefulWidget {
  final CryptoInvoice invoice;
  final String accessKey;

  const CryptoPayView({
    super.key,
    required this.invoice,
    required this.accessKey,
  });

  @override
  ConsumerState<CryptoPayView> createState() => _CryptoPayViewState();
}

class _CryptoPayViewState extends ConsumerState<CryptoPayView> {
  final _hash = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _hash.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    setState(() => _busy = true);
    final invoice = widget.invoice;
    final result = invoice.byHash
        ? await request.claimCryptoHash(
            widget.accessKey,
            invoice.id,
            _hash.text.trim(),
          )
        : await request.checkCryptoPayment(widget.accessKey, invoice.id);
    if (!mounted) return;
    setState(() => _busy = false);
    final l = context.appLocalizations;
    if (result.isError) return complainPayment(context, result.message);
    if (result.data!.paid) {
      dialogs.showNotifier(l.paymentReceived, level: MessageLevel.info);
      Navigator.of(context).pop(true);
      return;
    }
    // «Не видно» — не отказ: перевод в сети идёт минутами. Для хеша — своя причина.
    dialogs.showNotifier(
      invoice.byHash ? l.errHashNotAccepted : l.paymentNotSeen,
    );
  }

  Widget _row(String label, String value, {Widget? leading}) {
    return DecorationListItem(
      leading: leading,
      title: Text(label),
      subtitle: TooltipLabel(value),
      trailing: IconButton(
        tooltip: context.appLocalizations.copy,
        icon: const Icon(Icons.copy),
        onPressed: () async {
          await Clipboard.setData(ClipboardData(text: value));
          if (mounted) dialogs.showNotifier(context.appLocalizations.copy);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final invoice = widget.invoice;
    final muted = context.textTheme.bodySmall?.copyWith(
      color: context.colorScheme.onSurfaceVariant,
    );
    return BaseScaffold(
      title: '${l.pay} ${invoice.sym}',
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: ListView(
          children: [
            if (invoice.qrSvg.isNotEmpty) ...[
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
            Text(l.payExact, style: muted),
            const SizedBox(height: 8),
            generateSectionV3(
              title: '${l.pay} ${invoice.sym}',
              items: [
                _row(
                  l.usdtAmount,
                  '${invoice.amount} ${invoice.sym}',
                  leading: CoinIcon(invoice.coinIcon, size: 28),
                ),
                _row(l.usdtAddress, invoice.address),
                DecorationListItem(
                  leading: CoinIcon(invoice.netIcon, size: 22),
                  title: Text(l.usdtNetwork),
                  subtitle: TooltipLabel(invoice.network),
                ),
                DecorationListItem(
                  title: Text(l.minutesLeftLabel),
                  subtitle: TooltipLabel('${invoice.minutesLeft}'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('• ${l.networkOnlyWarn}', style: muted),
            const SizedBox(height: 4),
            Text('• ${l.payExchangeWarn}', style: muted),
            const SizedBox(height: 16),
            if (invoice.byHash) ...[
              TextField(
                controller: _hash,
                enabled: !_busy,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: l.txHashLabel,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _check,
                icon: const Icon(Icons.done),
                label: Text(invoice.byHash ? l.checkTransfer : l.iPaid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Значок монеты или сети из assets/coins. Имя не из набора — кружок с буквой, а не пустота:
/// сервер может прислать монету новее этого выпуска приложения.
class CoinIcon extends StatelessWidget {
  /// Картинки, которые лежат в приложении (assets/coins). Список явный: проверка
  /// «есть ли файл» во время работы стоила бы чтения ассетов на каждый кадр.
  static const known = {
    'arb', 'base', 'bnb', 'btc', 'doge', 'eth', 'ltc', 'pol', 'sol', 'ton', //
    'trx', 'usdc', 'usdt', 'xrp',
  };

  final String name;
  final double size;

  const CoinIcon(this.name, {super.key, this.size = 28});

  @override
  Widget build(BuildContext context) {
    if (known.contains(name)) {
      return SvgPicture.asset(
        'assets/coins/$name.svg',
        width: size,
        height: size,
      );
    }
    return CircleAvatar(
      radius: size / 2,
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
        style: TextStyle(fontSize: size * 0.45),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String text;
  final Color? background;

  const _Chip(this.text, {this.background});

  @override
  Widget build(BuildContext context) {
    final filled = background != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
        border: filled
            ? null
            : Border.all(color: context.colorScheme.outlineVariant),
      ),
      child: Text(
        text,
        style: context.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: filled ? Colors.white : context.colorScheme.onSurface,
        ),
      ),
    );
  }
}

/// Отказ сервера кодом -> текст на языке приложения (код один, языков четыре).
String serverErrorText(AppLocalizations l, String code) => switch (code) {
  'unknown_key' => l.errUnknownKey,
  'usdt_off' => l.errUsdtOff,
  'card_off' => l.errCardOff,
  'coins_off' || 'coins_error' || 'bad_coin' => l.errCoinsOff,
  'skins_off' => l.errSkinsOff,
  'trial_off' => l.errTrialOff,
  'trial_used' || 'promo_trial_used' => l.errTrialUsed,
  'trial_need_tg' => l.errTrialNeedTelegram,
  'tg_off' => l.errTgOff,
  'too_many' => l.errTooMany,
  'promo_unknown' => l.promoErrUnknown,
  'promo_used' || 'promo_used_tg' => l.promoErrUsed,
  'promo_paid' => l.promoErrPaid,
  'promo_off' || 'promo_refused' => l.promoErrOff,
  _ => l.errNetwork,
};

void complainPayment(BuildContext context, String code) {
  dialogs.showNotifier(
    serverErrorText(context.appLocalizations, code),
    level: MessageLevel.error,
  );
}
