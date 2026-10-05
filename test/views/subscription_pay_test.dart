import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/subscription_pay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

/// Экран выбора способа оплаты (05-10). Здесь — решения владельца, которые живут в разметке:
/// карта РФ / СБП ПЕРВОЙ, монета одной строкой с сетями внутри, редкие монеты под «Ещё».
/// Разбор ответов сервера — в test/models/account_test.dart.
const _plan = Plan(code: '1m', days: 30, usd: 3.49, title: '1 месяц');

AccountStatus _status({
  bool card = true,
  bool coins = true,
  bool skins = true,
}) {
  return AccountStatus(
    key: 'k',
    active: false,
    blocked: false,
    expiresAt: null,
    daysLeft: null,
    usedGb: null,
    quotaGb: null,
    plans: const [_plan],
    usdtEnabled: true,
    cardEnabled: card,
    coinsEnabled: coins,
    skinsEnabled: skins,
    coins: CoinGroup.listFrom([
      {
        'sym': 'USDT',
        'name': 'Tether',
        'icon': 'usdt',
        'popular': true,
        'nets': [
          {'code': 'usdt_trc20', 'net': 'TRON (TRC-20)', 'icon': 'trx'},
          {'code': 'usdt_ton', 'net': 'TON', 'icon': 'ton'},
        ],
      },
      {
        'sym': 'BTC',
        'name': 'Bitcoin',
        'icon': 'btc',
        'popular': true,
        'nets': [
          {'code': 'btc', 'net': 'Bitcoin', 'icon': 'btc'},
        ],
      },
      {
        'sym': 'DOGE',
        'name': 'Dogecoin',
        'icon': 'doge',
        'popular': false,
        'nets': [
          {'code': 'doge', 'net': 'Dogecoin', 'icon': 'doge'},
        ],
      },
    ]),
  );
}

Future<void> _pump(
  WidgetTester tester,
  AccountStatus status, {
  bool keepSize = false,
}) async {
  if (!keepSize) tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        child: PaymentMethodView(status: status, plan: _plan, accessKey: 'k'),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('карта РФ / СБП стоит ПЕРВОЙ, криптовалюта — ниже', (
    tester,
  ) async {
    await _pump(tester, _status());
    final l = tester.element(find.byType(PaymentMethodView)).appLocalizations;

    final card = find.text(l.payCardSbp);
    final crypto = find.text(l.cryptocurrency);
    expect(card, findsOneWidget);
    expect(crypto, findsOneWidget);
    // На широком экране способы стоят в ряд (06-10), на узком — столбиком: «первой» значит
    // левее в ряду или выше в столбике.
    final c = tester.getTopLeft(card), k = tester.getTopLeft(crypto);
    expect(
      c.dx < k.dx || c.dy < k.dy,
      isTrue,
      reason: 'акцент на рублёвые карты и СБП — решение владельца 05-10',
    );
    expect(find.text('СБП'), findsOneWidget);
    expect(find.text('МИР'), findsOneWidget);
    expect(find.text(l.payCardSbpButton), findsOneWidget);
  });

  testWidgets('монета с несколькими сетями раскрывается, сети внутри', (
    tester,
  ) async {
    await _pump(tester, _status());

    // До раскрытия сети USDT не видны: монета — одна строка, а не плитка на каждую сеть.
    expect(find.text('USDT'), findsOneWidget);
    expect(find.text('TRON (TRC-20)'), findsNothing);
    await tester.tap(find.text('USDT'));
    await tester.pumpAndSettle();
    expect(find.text('TRON (TRC-20)'), findsOneWidget);
    expect(find.text('TON'), findsOneWidget);
    // Монета с одной сетью — сразу строка с сетью, раскрывать нечего.
    expect(find.text('Bitcoin'), findsOneWidget);
  });

  testWidgets('число сетей подписано словом, а не голой цифрой', (
    tester,
  ) async {
    await _pump(tester, _status());
    final l = tester.element(find.byType(PaymentMethodView)).appLocalizations;

    // «Tether · 2» читалось как цена или курс (отзыв владельца на 0.9.5-pre.1).
    expect(find.text(l.networksCount(2)), findsOneWidget);
    expect(find.text('Tether · 2'), findsNothing);
  });

  test('по-русски сети склоняются: 1 сеть, 2 сети, 6 сетей', () async {
    final l = await AppLocalizations.load(const Locale('ru'));
    expect(l.networksCount(1), '1 сеть');
    expect(l.networksCount(2), '2 сети');
    expect(l.networksCount(6), '6 сетей');
    expect(l.daysLeftCount(1), 'остался 1 день');
    expect(l.daysLeftCount(3), 'осталось 3 дня');
    expect(l.daysLeftCount(20), 'осталось 20 дней');
    await AppLocalizations.load(const Locale('en'));
  });

  testWidgets('редкие монеты спрятаны под «Ещё»', (tester) async {
    await _pump(tester, _status());
    final l = tester.element(find.byType(PaymentMethodView)).appLocalizations;

    expect(find.textContaining(l.moreCoins), findsOneWidget);
    expect(find.text('Dogecoin'), findsNothing);
    await tester.tap(find.textContaining(l.moreCoins));
    await tester.pumpAndSettle();
    expect(find.text('Dogecoin'), findsOneWidget);
  });

  testWidgets('без карты блока карты нет, без монет — нет крипты', (
    tester,
  ) async {
    await _pump(tester, _status(card: false));
    var l = tester.element(find.byType(PaymentMethodView)).appLocalizations;
    expect(find.text(l.payCardSbp), findsNothing);
    expect(find.text(l.cryptocurrency), findsOneWidget);

    await _pump(tester, _status(coins: false));
    l = tester.element(find.byType(PaymentMethodView)).appLocalizations;
    expect(find.text(l.payCardSbp), findsOneWidget);
    expect(find.text(l.cryptocurrency), findsNothing);
  });

  testWidgets('скины: блок есть по флагу сервера и стоит последним', (
    tester,
  ) async {
    await _pump(tester, _status());
    final l = tester.element(find.byType(PaymentMethodView)).appLocalizations;
    final skins = find.text(l.paySkins);
    expect(skins, findsOneWidget);
    expect(find.text(l.paySkinsButton), findsOneWidget);
    expect(find.textContaining('\$3.49'), findsWidgets);
    final s = tester.getTopLeft(skins),
        k = tester.getTopLeft(find.text(l.cryptocurrency));
    expect(
      s.dx > k.dx || s.dy > k.dy,
      isTrue,
      reason: 'скины — после карты и монет',
    );

    await _pump(tester, _status(skins: false));
    expect(find.text(l.paySkins), findsNothing);
  });

  testWidgets('на узком экране способы столбиком, без переполнения', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 1800);
    await _pump(tester, _status(), keepSize: true);
    final l = tester.element(find.byType(PaymentMethodView)).appLocalizations;
    expect(
      tester.getTopLeft(find.text(l.payCardSbp)).dy,
      lessThan(tester.getTopLeft(find.text(l.cryptocurrency)).dy),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('незнакомая иконка — кружок с буквой, а не падение', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(children: [CoinIcon('newcoin'), CoinIcon('')]),
        ),
      ),
    );
    expect(find.text('N'), findsOneWidget);
    expect(find.text('?'), findsOneWidget);
  });
}
