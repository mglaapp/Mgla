import 'package:fl_clash/common/constant.dart';
import 'package:fl_clash/common/preferences.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/views/dashboard/widget_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _oldLayout = [DashboardWidget.networkSpeed, DashboardWidget.trafficUsage];

Config _config(List<DashboardWidget> widgets) => Config(
  themeProps: defaultThemeProps,
  appSettingProps: AppSettingProps(dashboardWidgets: widgets),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  late SharedPreferences store;

  setUp(() async {
    store = await SharedPreferences.getInstance();
    await store.clear();
  });

  test('новая установка: плитка подписки первой в наборе по умолчанию', () {
    expect(defaultDashboardWidgets.first, DashboardWidget.subscription);
  });

  test('плитка подписки — обычная плитка сетки в 4 клетки', () {
    final item = DashboardWidget.subscription.widget;
    expect(item.crossAxisCellCount, 4);
    expect(dashboardWidgetOf(item), DashboardWidget.subscription);
  });

  test('сохранённая раскладка читается с плиткой подписки', () {
    final props = AppSettingProps.fromJson({
      'dashboardWidgets': ['subscription', 'networkSpeed'],
    });
    expect(props.dashboardWidgets, [
      DashboardWidget.subscription,
      DashboardWidget.networkSpeed,
    ]);
  });

  test('старая раскладка: плитка вставляется первой и сохраняется', () async {
    final seeded = await preferences.seedSubscriptionWidget(
      _config(_oldLayout),
    );

    expect(seeded.appSettingProps.dashboardWidgets, [
      DashboardWidget.subscription,
      ..._oldLayout,
    ]);
    final saved = await preferences.getConfig();
    expect(
      saved!.appSettingProps.dashboardWidgets.first,
      DashboardWidget.subscription,
    );
    expect(store.getBool(subscriptionWidgetSeededKey), isTrue);
  });

  test('убранная после вставки плитка не возвращается', () async {
    await preferences.seedSubscriptionWidget(_config(_oldLayout));

    final again = await preferences.seedSubscriptionWidget(_config(_oldLayout));

    expect(again.appSettingProps.dashboardWidgets, _oldLayout);
  });

  test('раскладка уже с плиткой: конфиг тот же, отметка ставится', () async {
    final config = _config(const [
      DashboardWidget.networkSpeed,
      DashboardWidget.subscription,
    ]);

    final seeded = await preferences.seedSubscriptionWidget(config);

    expect(identical(seeded, config), isTrue);
    expect(await preferences.getConfig(), isNull);
    expect(store.getBool(subscriptionWidgetSeededKey), isTrue);
  });
}
