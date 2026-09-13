import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/dashboard/widgets/connection_state_pill.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<ProviderContainer> _pump(WidgetTester tester, {int? runTime}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(runTimeProvider.notifier).value = runTime;

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        includeNavigatorKey: false,
        setTheme: false,
        homeBuilder: (child) => Scaffold(body: Center(child: child)),
        child: const ConnectionStatePill(),
      ),
    ),
  );
  await tester.pump();
  return container;
}

StateDot _dot(WidgetTester tester) {
  return tester.widget<StateDot>(find.byType(StateDot));
}

void main() {
  testWidgets('running reads as filled dot, a word and the accent colour', (
    tester,
  ) async {
    await _pump(tester, runTime: 1000);

    expect(find.text('Connected'), findsOneWidget);
    expect(_dot(tester).filled, isTrue);
  });

  testWidgets('stopped reads as hollow dot and its own word', (tester) async {
    await _pump(tester);

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.text('Connected'), findsNothing);
    expect(_dot(tester).filled, isFalse);
  });

  testWidgets('the word and the shape change together with the state', (
    tester,
  ) async {
    final container = await _pump(tester);
    final stoppedColour = _dot(tester).color;

    container.read(runTimeProvider.notifier).value = 1000;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Connected'), findsOneWidget);
    expect(_dot(tester).filled, isTrue);
    expect(_dot(tester).color, isNot(stoppedColour));
  });

  testWidgets('colour alone never carries the state', (tester) async {
    await _pump(tester, runTime: 1000);
    final connected = find.text('Connected');
    expect(connected, findsOneWidget);

    final semantics = tester.getSemantics(connected);
    expect(semantics.label, contains('Connected'));
  });
}
