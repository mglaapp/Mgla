import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/tv_login.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _key = '0123456789abcdef01234567';

const _login = TvLoginStart(
  code: 'ABC234',
  codeText: 'ABC 234',
  secret: 'tv-secret',
  url: 'https://mgla.app/tv?c=ABC234',
  qrSvg: '',
  expiresIn: 600,
  pollEvery: 1,
);

ProviderContainer _container(
  WidgetTester tester, {
  List<Profile> profiles = const [],
}) {
  const size = Size(1400, 1000);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [profilesProvider.overrideWith(() => TestProfiles(profiles))],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  return container;
}

/// Pushes [view] from a button and reports what it popped with.
Future<List<String?>> _open(WidgetTester tester, Widget view) async {
  final popped = <String?>[];
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container(tester),
      child: TestApp(
        child: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                popped.add(
                  await Navigator.of(
                    context,
                  ).push<String>(MaterialPageRoute(builder: (_) => view)),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return popped;
}

void main() {
  testWidgets(
    'shows the code and leaves with the key once the phone confirms',
    (tester) async {
      final polls = <String>[];
      final popped = await _open(
        tester,
        TvLoginView(
          start: () async => Result.success(_login),
          poll: (code, secret) async {
            polls.add('$code/$secret');
            return Result.success(
              polls.length < 2
                  ? const TvPoll(state: 'wait')
                  : const TvPoll(state: 'done', key: _key),
            );
          },
        ),
      );
      final l = currentAppLocalizations;

      expect(find.text('ABC 234'), findsOneWidget);
      expect(find.text(l.tvOrEnterCode('mgla.app/tv')), findsOneWidget);
      expect(find.text(l.tvWaiting), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(popped, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 400));
      expect(polls, ['ABC234/tv-secret', 'ABC234/tv-secret']);
      expect(popped, [subscriptionUrlOf(_key)]);
    },
  );

  testWidgets('an expired code waits for the remote instead of renewing', (
    tester,
  ) async {
    var starts = 0;
    var polls = 0;
    await _open(
      tester,
      TvLoginView(
        start: () async {
          starts += 1;
          return Result.success(_login);
        },
        poll: (_, _) async {
          polls += 1;
          return Result.success(const TvPoll(state: 'expired'));
        },
      ),
    );
    final l = currentAppLocalizations;

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text(l.tvCodeExpired), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(starts, 1);
    expect(polls, 1);

    await tester.tap(find.text(l.tvNewCode));
    await tester.pump();
    await tester.pump();
    expect(starts, 2);
    expect(find.text('ABC 234'), findsOneWidget);
  });

  testWidgets('a refused start says why and offers to try again', (
    tester,
  ) async {
    await _open(
      tester,
      TvLoginView(
        start: () async => Result.error('too_many'),
        poll: (_, _) async => Result.success(const TvPoll(state: 'wait')),
      ),
    );
    final l = currentAppLocalizations;

    expect(find.text(l.errTooMany), findsOneWidget);
    expect(find.text(l.redo), findsOneWidget);
  });

  testWidgets('a TV offers sign-in with phone instead of the camera', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(tester),
        child: TestApp(
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const AccessKeyCard(isTV: true),
                  Expanded(child: AddProfileView(context: context, isTV: true)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = currentAppLocalizations;

    expect(find.text(l.signInWithPhone), findsNWidgets(2));
    expect(find.text(l.qrcode), findsNothing);
    expect(find.text(l.accessKey), findsWidgets);
  });

  testWidgets('a phone keeps the camera and has no phone sign-in', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: _container(tester),
        child: TestApp(
          child: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  const AccessKeyCard(isTV: false),
                  Expanded(
                    child: AddProfileView(context: context, isTV: false),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l = currentAppLocalizations;

    expect(find.text(l.signInWithPhone), findsNothing);
    expect(find.text(l.qrcode), findsOneWidget);
  });

  group('phone confirms a TV code', () {
    final sent = <String>[];

    Future<void> pumpPhone(WidgetTester tester, List<Profile> profiles) async {
      sent.clear();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: _container(tester, profiles: profiles),
          child: TestApp(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => confirmTvSignIn(
                    ref,
                    'abc234',
                    send: (key, code) async {
                      sent.add('$key/$code');
                      return Result.success(true);
                    },
                  ),
                  child: const Text('link'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('link'));
      await tester.pumpAndSettle();
    }

    final ours = Profile.normal(
      label: 'p',
      url: '$subscriptionSite$subscriptionPath$_key',
    );

    testWidgets('without our key it explains instead of sending', (
      tester,
    ) async {
      await pumpPhone(tester, const []);

      expect(find.text(currentAppLocalizations.tvNeedsKey), findsOneWidget);
      expect(sent, isEmpty);
    });

    testWidgets('shows the code with the warning and sends only on confirm', (
      tester,
    ) async {
      await pumpPhone(tester, [ours]);
      final l = currentAppLocalizations;

      expect(find.text(l.connectTvConfirm('ABC 234')), findsOneWidget);
      expect(sent, isEmpty);

      await tester.tap(find.widgetWithText(TextButton, l.connectTv));
      await tester.pumpAndSettle();

      expect(sent, ['$_key/ABC234']);
    });

    testWidgets('cancel sends nothing', (tester) async {
      await pumpPhone(tester, [ours]);

      await tester.tap(find.text(currentAppLocalizations.cancel));
      await tester.pumpAndSettle();

      expect(sent, isEmpty);
    });
  });
}
