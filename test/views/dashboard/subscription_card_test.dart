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

/// Блок подписки на главном экране (решение владельца 05-10): срок и «Продлить» там, куда
/// смотрят каждый день. Сервер подменён: здесь проверяется разметка и дорога к оплате, а
/// разбор ответа сервера — в test/models/account_test.dart.
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
          body: SingleChildScrollView(
            child: SubscriptionCard(fetchStatus: server.call),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

AppLocalizations _l(WidgetTester tester) =>
    tester.element(find.byType(SubscriptionCard)).appLocalizations;

void main() {
  testWidgets('оплачено: дата, остаток дней и «Продлить подписку»', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(server.asked, [_key]);
    expect(find.text('${l.accessPaidUntil} 2026-11-12'), findsOneWidget);
    expect(find.text(l.daysLeftCount(20)), findsOneWidget);
    expect(find.text(l.renewSubscription), findsOneWidget);
    expect(find.text(l.subscriptionDetails), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Продлить»: выбор срока, потом экран выбора способа оплаты', (
    tester,
  ) async {
    final server = _Server(Result.success(_status()));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    await tester.tap(find.text(l.renewSubscription));
    await tester.pumpAndSettle();
    // Тарифов два — сначала срок; ни один экран оплаты ещё не открыт.
    expect(find.text(l.choosePlan), findsOneWidget);
    expect(find.byType(PaymentMethodView), findsNothing);

    await tester.tap(find.text('3 months'));
    await tester.pumpAndSettle();
    final view = tester.widget<PaymentMethodView>(
      find.byType(PaymentMethodView),
    );
    // Та же дорога, что с экрана подписки: выбранный тариф и наш ключ, а не первый попавшийся.
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

    await tester.tap(find.text(l.renewSubscription));
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
    expect(find.text(l.getSubscription), findsOneWidget);
    expect(find.text(l.renewSubscription), findsNothing);
  });

  testWidgets(
    'чужой профиль: сервер не спрашивается, есть «Создать аккаунт» и ключ',
    (tester) async {
      final server = _Server(Result.success(_status()));
      await _pump(tester, url: 'https://example.com/sub/$_key', server: server);
      final l = _l(tester);

      // Чужой ключ на наш сервер не уходит: про чужие подписки он ничего не знает.
      expect(server.asked, isEmpty);
      expect(find.text(l.createAccount), findsOneWidget);
      expect(find.text(l.accessKey), findsOneWidget);
      expect(find.text(l.renewSubscription), findsNothing);
    },
  );

  testWidgets('сервер недоступен: слово об ошибке, без падения', (
    tester,
  ) async {
    final server = _Server(Result.error('network'));
    await _pump(tester, url: _ourUrl, server: server);
    final l = _l(tester);

    expect(find.text(l.errNetwork), findsOneWidget);
    expect(find.text(l.renewSubscription), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
