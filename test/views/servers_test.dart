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

/// Экран серверов читает ядро (группы подписки) — ему нужен ProviderScope, как в приложении.
Widget _scoped(
  Widget child, {
  List<Group> groups = const [],
  List<_Switch>? log,
}) {
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(() => TestProfiles(const [])),
      groupsProvider.overrideWith(() => _FakeGroups(groups)),
      if (log != null)
        proxiesActionProvider.overrideWith(() => _FakeProxies(log)),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  return UncontrolledProviderScope(container: container, child: child);
}

typedef _Switch = (String group, String proxy);

class _FakeGroups extends Groups {
  final List<Group> value;
  _FakeGroups(this.value);

  @override
  List<Group> build() => value;
}

class _FakeProxies extends ProxiesAction {
  final List<_Switch> log;
  _FakeProxies(this.log);

  @override
  void build() {}

  @override
  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    log.add((groupName, proxyName));
  }
}

// Ответ сайта при трёх узлах (03-11): у рабочих — имя группы страны в подписке.
const _multi = [
  {
    'id': 'nl',
    'cc': 'nl',
    'name': {'ru': 'Нидерланды', 'en': 'Netherlands'},
    'status': 'ok',
    'group': 'Mgla NL',
  },
  {
    'id': 'de',
    'cc': 'de',
    'name': {'ru': 'Германия', 'en': 'Germany'},
    'status': 'ok',
    'group': 'Mgla DE',
  },
  {
    'id': 'lv',
    'cc': 'lv',
    'name': {'ru': 'Латвия', 'en': 'Latvia'},
    'status': 'ok',
    'group': 'Mgla LV',
  },
  {
    'id': 'fi',
    'cc': 'fi',
    'name': {'ru': 'Финляндия', 'en': 'Finland'},
    'status': 'busy',
  },
];

/// Группы подписки как их отдаёт ядро: главный переключатель + url-test стран.
List<Group> _coreGroups(String now) => [
  Group(
    type: GroupType.Selector,
    name: 'Mgla',
    now: now,
    all: const [
      Proxy(name: 'Auto', type: 'URLTest'),
      Proxy(name: 'Mgla NL', type: 'URLTest'),
      Proxy(name: 'Mgla DE', type: 'URLTest'),
      Proxy(name: 'Mgla LV', type: 'URLTest'),
    ],
  ),
  const Group(
    type: GroupType.URLTest,
    name: 'Mgla DE',
    all: [Proxy(name: 'Mgla DE Reality', type: 'Vless')],
  ),
];

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
      await _pump(tester, _scoped(const ServersView(fetchServers: _ok)));
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
                  builder: (_) => _scoped(const ServersView(fetchServers: _ok)),
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
      await _pump(tester, _scoped(const ServersView(fetchServers: _offline)));
      final l = tester.element(find.byType(ServersView)).appLocalizations;
      expect(find.text(l.serversLoadError), findsOneWidget);
      expect(find.text(l.sync), findsOneWidget);
    });
  });

  group('несколько узлов: выбор = переключение в ядре (03-11)', () {
    final servers = ServerInfo.listFrom(_multi);
    Future<Result<List<ServerInfo>>> multi() async => Result.success(servers);

    test('группа сервера разобрана, у заглушки её нет', () {
      expect(servers.map((s) => s.group), [
        'Mgla NL',
        'Mgla DE',
        'Mgla LV',
        null,
      ]);
      expect(_servers.every((s) => s.group == null), isTrue);
    });

    test('«Авто» первым только при группах', () {
      expect(pickerServers(servers).first.id, autoServerId);
      expect(pickerServers(servers).first.group, autoGroupName);
      expect(
        pickerServers(_servers).map((s) => s.id),
        _servers.map((s) => s.id),
      );
    });

    test('главный переключатель — select с группами стран, не url-test', () {
      final list = pickerServers(servers);
      expect(mainGroupOf(_coreGroups('Auto'), list), 'Mgla');
      expect(mainGroupOf(_coreGroups('Auto').skip(1).toList(), list), isNull);
      expect(mainGroupOf(_coreGroups('Auto'), _servers), isNull);
    });

    test('текущий сервер — выбранный в ядре, а не первый рабочий', () {
      final list = pickerServers(servers);
      expect(currentServerOf(list, selected: 'Mgla DE')?.id, 'de');
      expect(currentServerOf(list, selected: 'Auto')?.id, autoServerId);
      expect(currentServerOf(list, selected: 'чужое')?.id, autoServerId);
    });

    /// Экран открыт ПОВЕРХ стартовой страницы, как в приложении: выбор закрывает его.
    Future<void> openPicker(
      WidgetTester tester,
      List<Group> groups,
      List<_Switch> log,
    ) async {
      // контейнер один на весь тест: страница выбора открывается выше корня, ей нужен тот же
      final page = _scoped(
        ServersView(fetchServers: multi),
        groups: groups,
        log: log,
      );
      await _pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(
              context,
            ).push<String>(MaterialPageRoute(builder: (_) => page)),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('нажатие на Германию переключает «Mgla» на «Mgla DE»', (
      tester,
    ) async {
      final log = <_Switch>[];
      await openPicker(tester, _coreGroups('Mgla LV'), log);
      final l = tester.element(find.byType(ServersView)).appLocalizations;
      expect(find.text(l.serverAuto), findsOneWidget);
      expect(find.byType(CountryFlag), findsNWidgets(4));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('server-lv')),
          matching: find.byIcon(Icons.check),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('server-de')));
      await tester.pumpAndSettle();
      expect(log, [('Mgla', 'Mgla DE')]);
      expect(find.byType(ServersView), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('server-auto')));
      await tester.pumpAndSettle();
      expect(log.last, ('Mgla', 'Auto'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('КОНТРОЛЬ: без групп в подписке ядро не трогается', (
      tester,
    ) async {
      final log = <_Switch>[];
      await _pump(
        tester,
        _scoped(const ServersView(fetchServers: _ok), log: log),
      );
      await tester.tap(find.byKey(const ValueKey('server-nl')));
      await tester.pumpAndSettle();
      expect(log, isEmpty);
    });

    test('флаг Латвии нарисован', () => expect(hasFlagArt('lv'), isTrue));
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
