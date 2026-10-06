import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/outbound_mode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/test_app.dart';
import '../../helpers/test_profiles.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [profilesProvider.overrideWith(TestProfiles.new)],
    );
    globalState.container = container;
    container.read(viewSizeProvider.notifier).value = const Size(1200, 1000);
  });

  tearDown(() => container.dispose());

  Future<void> pumpTile(WidgetTester tester, {double width = 300}) async {
    tester.view.physicalSize = const Size(1200, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(width: width, child: const OutboundMode()),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  final help = find.byKey(const ValueKey('outbound_mode_help'));

  testWidgets('справка открывается и объясняет три режима', (tester) async {
    await pumpTile(tester);
    expect(help, findsOneWidget);

    await tester.tap(help);
    await tester.pumpAndSettle();

    final tip = currentAppLocalizations.outboundModeTip;
    expect(find.text(tip, findRichText: true), findsOneWidget);
    expect(tip, contains(currentAppLocalizations.rule));
    expect(tip, contains(currentAppLocalizations.global));
    expect(tip, contains(currentAppLocalizations.direct));
    expect(tester.takeException(), isNull);
  });

  testWidgets('справка не меняет режим', (tester) async {
    await pumpTile(tester);
    final before = container.read(patchClashConfigProvider).mode;

    await tester.tap(help);
    await tester.pumpAndSettle();

    expect(container.read(patchClashConfigProvider).mode, before);
    expect(before, Mode.rule);
  });

  testWidgets('узкая плитка: заголовок с кнопкой без переполнения', (
    tester,
  ) async {
    await pumpTile(tester, width: 160);
    expect(help, findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
