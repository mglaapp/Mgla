import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/subscription_card.dart';
import 'package:fl_clash/views/subscription_pay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

/// Плитка подписки на панели (решение владельца 06-10): срок одной строкой и компактная
/// «Продлить». Сервер подменён: здесь разметка и дорога к оплате, разбор ответа сервера — в
/// test/models/account_test.dart.
const _key = '9ac0394dfc2f68b5846e7ac4';
const _ourUrl = '$subscriptionSite$subscriptionPath$_key';

const _plans = [
  Plan(code: '1m', days: 30, usd: 3.49, title: '1 month'),
  Plan(code: '3m', days: 90, usd: 8.99, title: '3 months'),
];

AccountStatus _status({
  bool active = true,
  int? daysLeft = 20,
  List<Plan> plans = _plans,
}) {
  return AccountStatus(
    key: _key,
    active: active,
    blocked: false,
    expiresAt: active ? DateTime.utc(2026, 11, 12) : null,
    daysLeft: active ? daysLeft : null,
    usedGb: null,
    quotaGb: null,
    plans: plans,
    usdtEnabled: true,
    cardEnabled: true,
  );
}

class _Server {
  final Result<AccountStatus> answer;
  final asked = <String>[];

  _Server(this.answer);

  Future<Result<AccountStatus>> call(String key) async {
    asked.add(key);
    return answer;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required String url,
  required _Server server,
  double width = 1000,
}) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final profile = Profile.normal(label: 'p', url: url);
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(() => TestProfiles([profile])),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        child: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: SubscriptionCard(fetchStatus: server.call),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester tester) =>
    tester.element(find.byType(SubscriptionCard)).appLocalizations;

Color? _lineColor(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style?.color;

void main() {
  testWidgets('оплачено: срок одной строкой и компактная «Продлить»', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(server.asked, [_key]);
    expect(find.text(l.subscription), findsOneWidget);
    expect(
      find.text(l.subscriptionUntilDays('20', '2026-11-12')),
      findsOneWidget,
    );
    expect(find.byTooltip(l.renewSubscription), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('высота как у соседних плиток — одна строка сетки', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: _ourUrl, server: server);

    expect(
      tester.getSize(find.byType(SubscriptionCard)).height,
      getWidgetHeight(1),
    );
  });

  testWidgets('узкая плитка (телефон, 4 клетки из 8): без переполнения', (
    tester,
  ) async {
    final server = _Server(Result.success(_status(daysLeft: 342)));
    await _pump(tester, url: _ourUrl, server: server, width: 150);

    expect(tester.takeException(), isNull);
    expect(find.byTooltip(_l(tester).renewSubscription), findsOneWidget);
  });

  testWidgets('срок кончается: строка и кнопка цвета предупреждения', (
    tester,
  ) async {
    final server = _Server(Result.success(_status(daysLeft: 2)));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(
      _lineColor(tester, l.subscriptionUntilDays('2', '2026-11-12')),
      MglaPalette.warn,
    );
    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.tooltip, l.renewSubscription);
    expect(button.style?.backgroundColor?.resolve(const {}), MglaPalette.warn);
    expect(
      find.descendant(
        of: find.byType(IconButton),
        matching: find.byIcon(Icons.autorenew),
      ),
      findsOneWidget,
    );
  });

  testWidgets('«Продлить»: выбор срока, потом экран выбора способа оплаты', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    await tester.tap(find.byTooltip(l.renewSubscription));
    await tester.pumpAndSettle();
    expect(find.text(l.choosePlan), findsOneWidget);
    expect(find.byType(PaymentMethodView), findsNothing);

    await tester.tap(find.text('3 months'));
    await tester.pumpAndSettle();
    final view = tester.widget<PaymentMethodView>(
      find.byType(PaymentMethodView),
    );
    expect(view.plan.code, '3m');
    expect(view.accessKey, _key);
  });

  testWidgets('один тариф — к оплате без вопроса о сроке', (tester) async {
    final server = _Server(
      Result.success(
        _status(
          plans: const [
            Plan(code: '1m', days: 30, usd: 3.49, title: '1 month'),
          ],
        ),
      ),
    );
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    await tester.tap(find.byTooltip(l.renewSubscription));
    await tester.pumpAndSettle();
    expect(find.text(l.choosePlan), findsNothing);
    expect(find.byType(PaymentMethodView), findsOneWidget);
  });

  testWidgets('не оплачено: «Доступ не оплачен» и «Оформить подписку»', (
    tester,
  ) async {
    final server = _Server(Result.success(_status(active: false)));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(find.text(l.accessNotPaid), findsOneWidget);
    expect(find.byTooltip(l.getSubscription), findsOneWidget);
    expect(find.byTooltip(l.renewSubscription), findsNothing);
  });

  testWidgets('чужой профиль: сервер не спрашивается, есть «Создать аккаунт»', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: 'https://example.com/sub/$_key', server: server);
    final l = _l(tester);

    expect(server.asked, isEmpty);
    expect(find.text(l.noAccountShort), findsOneWidget);
    expect(find.byTooltip(l.createAccount), findsOneWidget);
    expect(find.byTooltip(l.renewSubscription), findsNothing);
  });

  testWidgets('сервер недоступен: «Нет связи» и «Обновить», без падения', (
    tester,
  ) async {
    final server = _Server(Result.error('network'));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(find.text(l.offlineShort), findsOneWidget);
    expect(find.byTooltip(l.renewSubscription), findsNothing);

    await tester.tap(find.byTooltip(l.sync));
    await tester.pumpAndSettle();
    expect(server.asked, [_key, _key]);
    expect(tester.takeException(), isNull);
  });
}
