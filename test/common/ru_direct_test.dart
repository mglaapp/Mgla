import 'dart:io';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yaml/yaml.dart';

Config _config(List<DashboardWidget> widgets) => Config(
  themeProps: defaultThemeProps,
  appSettingProps: AppSettingProps(dashboardWidgets: widgets),
);

Future<List<Object?>> _rules({
  required bool ruDirect,
  List<String> profileRules = const ['DOMAIN,mine.example,Mgla', 'MATCH,Mgla'],
  List<Rule> addedRules = const [],
}) async {
  final rawConfig = await decodeJSONTask<Map<String, dynamic>>(
    await encodeJSONTask({'proxies': [], 'rules': profileRules}),
  );
  final res = await makeRealProfileTask(
    MakeRealProfileState(
      profilesPath: '/profiles',
      profileId: 1,
      rawConfig: rawConfig,
      realPatchConfig: const PatchClashConfig(),
      overrideDns: false,
      appendSystemDns: false,
      proxyGroups: const [],
      rules: const [],
      addedRules: addedRules,
      defaultUA: 'Mgla-Test',
      ruDirect: ruDirect,
    ),
  );
  return List<Object?>.from((loadYaml(res.yaml) as YamlMap)['rules'] as List);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  group('withRuDirectRules', () {
    test('встают перед MATCH, правила выше не трогаются', () {
      final out = withRuDirectRules(['DOMAIN,mine.example,Mgla', 'MATCH,Mgla']);
      expect(out, ['DOMAIN,mine.example,Mgla', ...ruDirectRules, 'MATCH,Mgla']);
    });

    test('без MATCH — в конец', () {
      expect(withRuDirectRules(['DOMAIN,a.example,Mgla']), [
        'DOMAIN,a.example,Mgla',
        ...ruDirectRules,
      ]);
    });

    test('повтор ничего не дублирует, недостающие дописываются', () {
      final once = withRuDirectRules(['MATCH,Mgla']);
      expect(withRuDirectRules(once), once);
      final partial = withRuDirectRules([
        'geosite, category-ru ,direct',
        'MATCH,Mgla',
      ]);
      expect(
        partial.where((rule) => rule.toUpperCase().contains('CATEGORY-RU')),
        hasLength(1),
      );
      expect(partial.length, ruDirectRules.length + 1);
      expect(partial.last, 'MATCH,Mgla');
    });

    test('страна по адресу — без DNS-запроса на каждый домен', () {
      expect(ruDirectRules, contains('GEOIP,RU,DIRECT,no-resolve'));
      expect(ruDirectRules, contains('GEOSITE,category-ru,DIRECT'));
      expect(ruDirectRules.every((rule) => rule.contains(',DIRECT')), isTrue);
    });
  });

  test('список category-ru есть во встроенной базе — GitHub не нужен', () {
    final bytes = File('assets/data/GEOSITE.dat').readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    expect(text.contains('CATEGORY-RU'), isTrue);
  });

  group('сборка профиля для ядра', () {
    test('выключено — правила профиля как были', () async {
      expect(await _rules(ruDirect: false), [
        'DOMAIN,mine.example,Mgla',
        'MATCH,Mgla',
      ]);
    });

    test('включено — российское перед MATCH, своё правило выше', () async {
      final rules = await _rules(
        ruDirect: true,
        addedRules: const [
          Rule(
            ruleAction: RuleAction.DOMAIN_SUFFIX,
            content: 'bank.ru',
            ruleTarget: 'Mgla',
          ),
        ],
      );
      expect(rules.first, 'DOMAIN-SUFFIX,bank.ru,Mgla');
      expect(rules.last, 'MATCH,Mgla');
      final at = rules.indexOf('GEOSITE,category-ru,DIRECT');
      expect(at, greaterThan(rules.indexOf('DOMAIN,mine.example,Mgla')));
      expect(rules.sublist(at, at + ruDirectRules.length), ruDirectRules);
    });
  });

  group('плитка «РФ напрямую»', () {
    late SharedPreferences store;

    setUp(() async {
      store = await SharedPreferences.getInstance();
      await store.clear();
    });

    test('новая установка: рядом с подпиской, 4 клетки', () {
      expect(defaultDashboardWidgets.take(2), [
        DashboardWidget.subscription,
        DashboardWidget.ruDirectButton,
      ]);
      final item = DashboardWidget.ruDirectButton.widget;
      expect(item.crossAxisCellCount, 4);
      expect(dashboardWidgetOf(item), DashboardWidget.ruDirectButton);
    });

    test('старая раскладка: вставляется после подписки один раз', () async {
      const old = [DashboardWidget.subscription, DashboardWidget.networkSpeed];
      final seeded = await preferences.seedRuDirectWidget(_config(old));
      expect(seeded.appSettingProps.dashboardWidgets, [
        DashboardWidget.subscription,
        DashboardWidget.ruDirectButton,
        DashboardWidget.networkSpeed,
      ]);
      expect(store.getBool(ruDirectWidgetSeededKey), isTrue);

      final again = await preferences.seedRuDirectWidget(_config(old));
      expect(again.appSettingProps.dashboardWidgets, old);
    });

    test('без подписки в раскладке — первой', () {
      final out = withRuDirectWidget(
        _config(const [DashboardWidget.networkSpeed]),
      );
      expect(out.appSettingProps.dashboardWidgets, [
        DashboardWidget.ruDirectButton,
        DashboardWidget.networkSpeed,
      ]);
    });

    test('настройка по умолчанию выключена и читается из сохранённого', () {
      expect(const NetworkProps().ruDirect, isFalse);
      expect(NetworkProps.fromJson({'ruDirect': true}).ruDirect, isTrue);
      expect(NetworkProps.fromJson(const {}).ruDirect, isFalse);
    });
  });
}
