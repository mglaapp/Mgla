import 'package:fl_clash/widgets/launch_intro.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

const _ru = 'Одна подписка — все твои устройства';

Widget _app({bool reduceMotion = false, List<String>? taps}) => TestApp(
  locale: const Locale('ru'),
  child: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: LaunchIntro(
        child: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps?.add('home'),
              child: const Text('home'),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('the intro shows the slogan and is gone in under a second', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    expect(
      find.text(_ru),
      findsOneWidget,
      reason: 'the owner\'s slogan (13-10, №7)',
    );
    expect(find.byType(Image), findsOneWidget, reason: 'the mark');

    await tester.pump(const Duration(milliseconds: 500));
    final shown = tester.widget<Opacity>(
      find.ancestor(of: find.text(_ru), matching: find.byType(Opacity)).first,
    );
    expect(
      shown.opacity,
      greaterThan(0.9),
      reason: 'the slogan is up mid-intro',
    );

    await tester.pump(const Duration(milliseconds: 460));
    await tester.pump();
    expect(LaunchIntro.total, lessThan(const Duration(seconds: 1)));
    expect(
      find.text(_ru),
      findsNothing,
      reason: 'gone after ${LaunchIntro.total}',
    );
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('the app under the intro takes taps from the first frame', (
    tester,
  ) async {
    final taps = <String>[];
    await tester.pumpWidget(_app(taps: taps));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('home'), warnIfMissed: false);
    expect(taps, ['home'], reason: 'the intro never holds the app back');
    await tester.pumpAndSettle();
  });

  testWidgets('animations off in the system: no intro at all', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    expect(find.text(_ru), findsNothing);
    expect(find.text('home'), findsOneWidget);
    await tester.pumpAndSettle();
  });
}
