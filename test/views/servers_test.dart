import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:fl_clash/views/dashboard/widgets/server_card.dart';
import 'package:fl_clash/views/servers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _answer = {
  'ok': true,
  'servers': [
    {
      'id': 'nl',
      'cc': 'nl',
      'name': {'ru': 'Нидерланды', 'en': 'Netherlands'},
      'status': 'ok',
    },
    {
      'id': 'de',
      'cc': 'de',
      'name': {'ru': 'Германия', 'en': 'Germany'},
      'status': 'busy',
    },
    {
      'id': 'fi',
      'cc': 'fi',
      'name': {'ru': 'Финляндия', 'en': 'Finland'},
      'status': 'busy',
    },
    {
      'id': 'us',
      'cc': 'us',
      'name': {'ru': 'США', 'en': 'United States'},
      'status': 'busy',
    },
    {
      'id': 'gb',
      'cc': 'gb',
      'name': {'ru': 'Великобритания', 'en': 'United Kingdom'},
      'status': 'busy',
    },
    {
      'id': 'tr',
      'cc': 'tr',
      'name': {'ru': 'Турция', 'en': 'Türkiye'},
      'status': 'busy',
    },
  ],
};

final _servers = ServerInfo.listFrom(_answer['servers']);

Future<Result<List<ServerInfo>>> _ok() async => Result.success(_servers);

Future<Result<List<ServerInfo>>> _offline() async => Result.error('network');

Config _config(List<DashboardWidget> widgets) => Config(
  themeProps: defaultThemeProps,
  appSettingProps: AppSettingProps(dashboardWidgets: widgets),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(TestApp(child: child));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('разбор списка серверов', () {
    test('рабочий и заглушки, имена по языку', () {
      expect(_servers.map((s) => s.id), ['nl', 'de', 'fi', 'us', 'gb', 'tr']);
      expect(_servers.first.available, isTrue);
      expect(_servers.skip(1).every((s) => !s.available), isTrue);
      expect(_servers.first.nameFor('ru'), 'Нидерланды');
      expect(_servers.first.nameFor('ja'), 'Netherlands');
      expect(currentServerOf(_servers)?.id, 'nl');
    });

    test('мусор отбрасывается, неизвестный статус = нельзя выбрать', () {
      final list = ServerInfo.listFrom([
        {'id': 'x', 'cc': 'xyz', 'status': 'ok'},
        {'id': '', 'cc': 'de', 'status': 'ok'},
        'junk',
        {'id': 'pl', 'cc': 'PL', 'status': 'maybe'},
      ]);
      expect(list.single.cc, 'pl');
      expect(list.single.available, isFalse);
      expect(list.single.nameFor('ru'), 'PL');
      expect(ServerInfo.listFrom(null), isEmpty);
      expect(currentServerOf(list), isNull);
    });
  });

  group('экран выбора сервера', () {
    testWidgets('шесть стран, выбран рабочий, пять «Загружен»', (tester) async {
      await _pump(tester, const ServersView(fetchServers: _ok));
      final l = tester.element(find.byType(ServersView)).appLocalizations;

      expect(find.byType(ListTile), findsNWidgets(6));
      expect(find.text(l.serverBusy), findsNWidgets(5));
      expect(find.byType(CountryFlag), findsNWidgets(6));
      final nl = find.byKey(const ValueKey('server-nl'));
      expect(
        find.descendant(of: nl, matching: find.byIcon(Icons.check)),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-de')),
          matching: find.text(l.serverBusy),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('заглушку не выбрать: экран не закрывается', (tester) async {
      String? picked = 'none';
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              picked = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => const ServersView(fetchServers: _ok),
                ),
              );
            },
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-de')));
      await tester.pumpAndSettle();
      expect(find.byType(ServersView), findsOneWidget);
      expect(picked, 'none');

      await tester.tap(find.byKey(const ValueKey('server-nl')));
      await tester.pumpAndSettle();
      expect(find.byType(ServersView), findsNothing);
      expect(picked, 'nl');
    });

    testWidgets('без сети — понятный отказ и повтор', (tester) async {
      await _pump(tester, const ServersView(fetchServers: _offline));
      final l = tester.element(find.byType(ServersView)).appLocalizations;
      expect(find.text(l.serversLoadError), findsOneWidget);
      expect(find.text(l.sync), findsOneWidget);
    });
  });

  group('плитка «Сервер»', () {
    Future<int> pumpCard(WidgetTester tester, List<Profile> profiles) async {
      var asked = 0;
      final container = ProviderContainer(
        overrides: [
          profilesProvider.overrideWith(() => TestProfiles(profiles)),
        ],
      );
      addTearDown(container.dispose);
      globalState.container = container;
      await _pump(
        tester,
        UncontrolledProviderScope(
          container: container,
          child: Scaffold(
            body: ServerCard(
              fetchServers: () {
                asked++;
                return _ok();
              },
            ),
          ),
        ),
      );
      return asked;
    }

    testWidgets('наша подписка: страна рабочего сервера и число заглушек', (
      tester,
    ) async {
      final asked = await pumpCard(tester, [
        Profile.normal(
          label: 'p',
          url: '$subscriptionSite${subscriptionPath}9ac0394dfc2f68b5846e7ac4',
        ),
      ]);
      expect(asked, 1);
      expect(find.text('Netherlands'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);
      expect(find.byType(CountryFlag), findsOneWidget);
    });

    testWidgets(
      'без нашей подписки страну не выдумывает и сервер не спрашивает',
      (tester) async {
        final asked = await pumpCard(tester, [
          Profile.normal(label: 'p', url: 'https://other.example/sub/x'),
        ]);
        final l = tester.element(find.byType(ServerCard)).appLocalizations;
        expect(asked, 0);
        expect(find.text(l.noAccountShort), findsOneWidget);
        expect(find.text('Netherlands'), findsNothing);
      },
    );

    test('новая установка: отдельным рядом после «РФ напрямую»', () {
      expect(defaultDashboardWidgets.take(3), [
        DashboardWidget.subscription,
        DashboardWidget.ruDirectButton,
        DashboardWidget.server,
      ]);
      final item = DashboardWidget.server.widget;
      expect(item.crossAxisCellCount, 8);
      expect(dashboardWidgetOf(item), DashboardWidget.server);
    });

    test(
      'старая раскладка: вставляется один раз, убранная не вернётся',
      () async {
        final store = await SharedPreferences.getInstance();
        await store.clear();
        const old = [
          DashboardWidget.subscription,
          DashboardWidget.ruDirectButton,
          DashboardWidget.networkSpeed,
        ];
        final seeded = await preferences.seedServerWidget(_config(old));
        expect(seeded.appSettingProps.dashboardWidgets, [
          DashboardWidget.subscription,
          DashboardWidget.ruDirectButton,
          DashboardWidget.server,
          DashboardWidget.networkSpeed,
        ]);
        expect(store.getBool(serverWidgetSeededKey), isTrue);
        final again = await preferences.seedServerWidget(_config(old));
        expect(again.appSettingProps.dashboardWidgets, old);
      },
    );

    test('все три плитки вставляются одним вызовом при запуске', () async {
      final store = await SharedPreferences.getInstance();
      await store.clear();
      final seeded = await preferences.seedDashboardWidgets(
        _config(const [DashboardWidget.networkSpeed]),
      );
      expect(seeded.appSettingProps.dashboardWidgets, [
        DashboardWidget.subscription,
        DashboardWidget.ruDirectButton,
        DashboardWidget.server,
        DashboardWidget.networkSpeed,
      ]);
    });

    test('без «РФ напрямую» — после подписки, без обеих — первой', () {
      expect(
        withServerWidget(
          _config(const [
            DashboardWidget.subscription,
            DashboardWidget.networkSpeed,
          ]),
        ).appSettingProps.dashboardWidgets,
        [
          DashboardWidget.subscription,
          DashboardWidget.server,
          DashboardWidget.networkSpeed,
        ],
      );
      expect(
        withServerWidget(
          _config(const [DashboardWidget.networkSpeed]),
        ).appSettingProps.dashboardWidgets,
        [DashboardWidget.server, DashboardWidget.networkSpeed],
      );
    });
  });
}
