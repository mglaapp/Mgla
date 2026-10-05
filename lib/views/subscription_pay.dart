import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
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
  bool _busy = false;

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

  Widget _cardBlock() {
    final l = context.appLocalizations;
    final scheme = context.colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.primary, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.payCardSbp, style: context.textTheme.titleMedium?.toBold),
            const SizedBox(height: 10),
            const Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _Chip('МИР', background: Color(0xFF0F754E)),
                _Chip('СБП', background: Color(0xFF5B57A2)),
                _Chip('Visa'),
                _Chip('Mastercard'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              l.payCardSbpDesc,
              style: context.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _payCard,
                icon: const Icon(Icons.credit_card),
                label: Text(l.payCardSbpButton),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _coinTile(CoinGroup group) {
    final single = group.nets.length == 1;
    if (single) {
      final net = group.nets.first;
      return ListTile(
        leading: CoinIcon(group.icon, size: 32),
        title: Text(group.sym, style: context.textTheme.titleSmall?.toBold),
        subtitle: Text(net.network),
        trailing: const Icon(Icons.chevron_right),
        enabled: !_busy,
        onTap: () => _payCoin(net),
      );
    }
    return ExpansionTile(
      leading: CoinIcon(group.icon, size: 32),
      title: Text(group.sym, style: context.textTheme.titleSmall?.toBold),
      // «Tether · 6 сетей», а не голое «· 6»: число без слова читалось как цена или курс.
      subtitle: Text(
        '${group.name} · '
        '${context.appLocalizations.networksCount(group.nets.length)}',
      ),
      shape: const Border(),
      collapsedShape: const Border(),
      childrenPadding: const EdgeInsets.only(left: 16, bottom: 6),
      children: [
        for (final net in group.nets)
          ListTile(
            dense: true,
            leading: CoinIcon(net.icon, size: 22),
            title: Text(net.network),
            trailing: const Icon(Icons.chevron_right, size: 20),
            enabled: !_busy,
            onTap: () => _payCoin(net),
          ),
      ],
    );
  }

  Widget _cryptoBlock(List<CoinGroup> coins) {
    final l = context.appLocalizations;
    final top = coins.where((group) => group.popular).toList();
    final rest = coins.where((group) => !group.popular).toList();
    return Card(
      elevation: 0,
      color: context.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              l.cryptocurrency,
              style: context.textTheme.titleMedium?.toBold,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l.cryptoDesc,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          for (final group in top.isEmpty ? rest : top) _coinTile(group),
          if (top.isNotEmpty && rest.isNotEmpty)
            ExpansionTile(
              leading: const Icon(Icons.more_horiz),
              title: Text(l.moreCoins),
              subtitle: Text(rest.map((group) => group.sym).join(', ')),
              shape: const Border(),
              collapsedShape: const Border(),
              children: [for (final group in rest) _coinTile(group)],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final status = widget.status;
    final coins = status.coinsEnabled ? status.coins : const <CoinGroup>[];
    return BaseScaffold(
      title: '${l.choosePayment} · ${widget.plan.title}',
      body: Padding(
        padding: kMaterialListPadding.copyWith(top: 16, bottom: 16),
        child: ListView(
          children: [
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Text(
              '${widget.plan.title} — \$${widget.plan.usd.toStringAsFixed(2)}',
              style: context.textTheme.titleLarge?.toBold,
            ),
            const SizedBox(height: 12),
            if (status.cardEnabled) ...[
              _cardBlock(),
              const SizedBox(height: 12),
            ],
            if (coins.isNotEmpty) _cryptoBlock(coins),
          ],
        ),
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
void complainPayment(BuildContext context, String code) {
  final l = context.appLocalizations;
  dialogs.showNotifier(switch (code) {
    'unknown_key' => l.errUnknownKey,
    'usdt_off' => l.errUsdtOff,
    'card_off' => l.errCardOff,
    'coins_off' || 'coins_error' || 'bad_coin' => l.errCoinsOff,
    'too_many' => l.errTooMany,
    _ => l.errNetwork,
  }, level: MessageLevel.error);
}
