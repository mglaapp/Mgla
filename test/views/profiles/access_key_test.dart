import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/test_app.dart';

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1000, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer();
  addTearDown(container.dispose);
  globalState.container = container;
  container
      .read(viewSizeProvider.notifier)
      .update((_) => const Size(1000, 800));

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(
        setTheme: false,
        homeBuilder: (child) => Scaffold(body: Center(child: child)),
        child: child,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the first screen asks for a key, not for a URL', (tester) async {
    await _pump(tester, const AccessKeyCard());

    expect(find.text('Access key'), findsWidgets);
    expect(
      find.text(
        'Paste the key from your account — the address is known already',
      ),
      findsOneWidget,
    );
    expect(find.byType(AccessKeyButton), findsOneWidget);
  });

  testWidgets('the button opens a field for the key', (tester) async {
    await _pump(tester, const AccessKeyButton());

    await tester.tap(find.byType(AccessKeyButton));
    await tester.pumpAndSettle();

    expect(find.byType(InputDialog), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });
}
