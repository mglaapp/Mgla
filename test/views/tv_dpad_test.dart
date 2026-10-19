import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/profiles/access_key.dart';
import 'package:fl_clash/views/profiles/add.dart';
import 'package:fl_clash/views/profiles/tv_login.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:fl_clash/views/subscription_pay.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

const _key = '9ac0394dfc2f68b5846e7ac4';
const _arrows = [
  LogicalKeyboardKey.arrowUp,
  LogicalKeyboardKey.arrowDown,
  LogicalKeyboardKey.arrowLeft,
  LogicalKeyboardKey.arrowRight,
];

const _plans = [
  Plan(code: '1m', days: 30, usd: 3.49, title: '1 month'),
  Plan(code: '3m', days: 90, usd: 8.99, title: '3 months'),
  Plan(code: '1y', days: 365, usd: 29.99, title: '1 year'),
];

AccountStatus _status({bool active = false}) => AccountStatus(
  key: _key,
  active: active,
  blocked: false,
  expiresAt: active ? DateTime.now().add(const Duration(days: 20)) : null,
  daysLeft: active ? 20 : null,
  usedGb: null,
  quotaGb: null,
  plans: _plans,
  usdtEnabled: true,
  cardEnabled: true,
  coinsEnabled: true,
  skinsEnabled: true,
  coins: const [
    CoinGroup(
      sym: 'USDT',
      name: 'Tether',
      icon: '',
      popular: true,
      nets: [
        CoinNet(
          code: 'usdt_trc20',
          network: 'TRON (TRC-20)',
          icon: '',
          byHash: false,
        ),
      ],
    ),
  ],
  trial: active ? null : const TrialOffer(price: '19', days: 3),
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  const size = Size(1280, 720);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      profilesProvider.overrideWith(
        () => TestProfiles([
          Profile.normal(
            label: 'p',
            url: '$subscriptionSite$subscriptionPath$_key',
          ),
        ]),
      ),
    ],
  );
  addTearDown(container.dispose);
  globalState.container = container;
  container.read(viewSizeProvider.notifier).update((_) => size);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: TestApp(child: child),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

String _label(FocusNode node) {
  final context = node.context;
  if (context is! Element) return node.toStringShort();
  final texts = <String>[];
  void visit(Element e) {
    final widget = e.widget;
    if (widget is RichText) texts.add(widget.text.toPlainText());
    if (widget is EditableText) texts.add('field ${widget.controller.text}');
    if (texts.length < 2) e.visitChildren(visit);
  }

  visit(context);
  return texts.isEmpty ? node.toStringShort() : texts.join(' / ');
}

/// What a remote must be able to reach: every focusable control on screen.
List<FocusNode> _targets() => FocusManager
    .instance
    .rootScope
    .traversalDescendants
    .where((node) => node is! FocusScopeNode && node.context != null)
    .where((node) {
      final box = node.context!.findRenderObject();
      return box is RenderBox && box.hasSize && box.size.longestSide > 0;
    })
    .toList();

/// Moves only with arrows, the way a TV remote does, starting from the screen's own first
/// focus, and returns every control the arrows ever landed on.
Future<Set<FocusNode>> _walk(WidgetTester tester) async {
  if (FocusManager.instance.primaryFocus == FocusManager.instance.rootScope ||
      FocusManager.instance.primaryFocus == null) {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
  }
  final start = FocusManager.instance.primaryFocus!;
  final seen = <FocusNode>{start};
  final queue = [start];
  while (queue.isNotEmpty) {
    final node = queue.removeAt(0);
    for (final key in _arrows) {
      node.requestFocus();
      await _settle(tester);
      // Directional traversal remembers the last move and answers "down" after "up" by going
      // back; a jump made by the test is not a move a remote could make, so forget it.
      FocusTraversalGroup.maybeOf(
        node.context!,
      )?.invalidateScopeData(node.nearestScope!);
      await tester.sendKeyEvent(key);
      await _settle(tester);
      final next = FocusManager.instance.primaryFocus;
      if (next != null && next is! FocusScopeNode && seen.add(next)) {
        queue.add(next);
      }
    }
  }
  return seen;
}

Future<void> _expectRemoteReachesAll(WidgetTester tester) async {
  final targets = _targets();
  expect(targets, isNotEmpty, reason: 'nothing focusable was found');
  final seen = await _walk(tester);
  // One control may own nested nodes (a card's wrapper around its ink): landing on either is
  // landing on the control.
  bool reached(FocusNode node) =>
      seen.contains(node) ||
      seen.any((s) => s.ancestors.contains(node)) ||
      node.ancestors.any(seen.contains);
  final missed = [
    for (final node in targets)
      if (!reached(node)) _label(node),
  ];
  expect(missed, isEmpty, reason: 'arrows never reach: $missed');
}

void main() {
  testWidgets('home without a profile: key card above the dashboard tiles', (
    tester,
  ) async {
    final pressed = <String>[];
    Widget tile(String label) => SizedBox(
      height: 80,
      child: CommonCard(
        onPressed: () => pressed.add(label),
        child: Text(label),
      ),
    );
    await _pump(
      tester,
      Scaffold(
        body: FocusTraversalGroup(
          policy: PageTraversalPolicy(),
          child: PageFocusScope(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AccessKeyCard(isTV: true),
                Row(
                  children: [
                    Expanded(child: tile('tile left')),
                    Expanded(child: tile('tile right')),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final first = FocusManager.instance.primaryFocus;
    expect(_label(first!), contains(currentAppLocalizations.signInWithPhone));
    await _expectRemoteReachesAll(tester);

    first.requestFocus();
    await _settle(tester);
    for (var i = 0; i < 4 && pressed.isEmpty; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _settle(tester);
      if (_label(FocusManager.instance.primaryFocus!) == 'tile left') {
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await _settle(tester);
      }
    }
    expect(pressed, ['tile left'], reason: 'down from the card, then OK');
  });

  testWidgets('add-profile sheet on a TV', (tester) async {
    await _pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => AddProfileView(context: context, isTV: true),
        ),
      ),
    );
    await _expectRemoteReachesAll(tester);
  });

  testWidgets('the remote centre button opens phone sign-in', (tester) async {
    await _pump(tester, const Scaffold(body: AccessKeyCard(isTV: true)));

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _settle(tester);

    expect(find.byType(TvLoginView), findsOneWidget);
  });

  testWidgets('an expired TV code puts the remote on the new-code button', (
    tester,
  ) async {
    const login = TvLoginStart(
      code: 'ABC234',
      codeText: 'ABC 234',
      secret: 's',
      url: 'https://mgla.app/tv?c=ABC234',
      qrSvg: '',
      expiresIn: 600,
      pollEvery: 1,
    );
    await _pump(
      tester,
      TvLoginView(
        start: () async => Result.success(login),
        poll: (_, _) async => Result.success(const TvPoll(state: 'expired')),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    await _settle(tester);

    expect(
      _label(FocusManager.instance.primaryFocus!),
      contains(currentAppLocalizations.tvNewCode),
    );
  });

  testWidgets('subscription without access: plans, trial and promo', (
    tester,
  ) async {
    await _pump(
      tester,
      SubscriptionView(fetchStatus: (_) async => Result.success(_status())),
    );
    await _expectRemoteReachesAll(tester);
  });

  testWidgets('subscription with access', (tester) async {
    await _pump(
      tester,
      SubscriptionView(
        fetchStatus: (_) async => Result.success(_status(active: true)),
      ),
    );
    await _expectRemoteReachesAll(tester);
  });

  testWidgets('payment methods: card, coins and skins', (tester) async {
    await _pump(
      tester,
      PaymentMethodView(status: _status(), plan: _plans[1], accessKey: _key),
    );
    await _expectRemoteReachesAll(tester);
  });

  // 20-10, TV emulator: the page lives in a nested Navigator, so "leave the page to the parent
  // scope" stopped there — left from the page jumped to an invisible control and the rail with
  // profiles, tools and settings was out of the remote's reach. The real shell: rail outside,
  // page inside its own Navigator under the page traversal policy.
  testWidgets('left from the page reaches the rail, right comes back', (
    tester,
  ) async {
    final selected = <int>[];
    await _pump(
      tester,
      Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: 96,
              child: SidebarFocus(
                child: NavigationRail(
                  selectedIndex: 0,
                  onDestinationSelected: selected.add,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dashboard),
                      label: Text('home'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder),
                      label: Text('profiles'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings),
                      label: Text('tools'),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: FocusTraversalGroup(
                policy: PageTraversalPolicy(),
                child: Navigator(
                  pages: const [
                    MaterialPage(
                      child: PageFocusScope(
                        child: Scaffold(body: AccessKeyCard(isTV: true)),
                      ),
                    ),
                  ],
                  onDidRemovePage: (_) {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
    bool inRail() =>
        FocusManager.instance.primaryFocus?.ancestors.contains(
          sidebarFocusScope,
        ) ??
        false;
    final start = FocusManager.instance.primaryFocus!;
    expect(_label(start), contains(currentAppLocalizations.signInWithPhone));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await _settle(tester);
    expect(
      inRail(),
      isTrue,
      reason: 'left from the page edge goes to the rail',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _settle(tester);
    expect(inRail(), isTrue, reason: 'down moves along the rail');
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await _settle(tester);
    expect(selected, [1], reason: 'OK on the second item opens it');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await _settle(tester);
    expect(
      FocusManager.instance.primaryFocus,
      start,
      reason: 'right returns to where the page was left',
    );
  });

  // 20-10, TV emulator: the first-run disclaimer opened, the home with the phone sign-in button
  // finished building UNDER it, and that button's autofocus pulled the remote into the page
  // behind the dialog — arrows scrolled the dashboard, OK pressed nothing, and the first screen
  // of the app was a dead end on a TV. The disclaimer is gone (owner, 20-10), but the boot still
  // opens messages over the home (interrupted launch, crash recovery), so the same check stands.
  for (final homeFirst in [false, true]) {
    testWidgets(
      'a message over the home keeps the remote (home built ${homeFirst ? 'before' : 'under'} it)',
      (tester) async {
        system.debugIsTV = true;
        addTearDown(() => system.debugIsTV = false);
        final showHome = ValueNotifier(homeFirst);
        addTearDown(showHome.dispose);
        await _pump(
          tester,
          Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showHome,
              builder: (context, on, child) =>
                  on ? const AccessKeyCard(isTV: true) : const SizedBox(),
            ),
          ),
        );
        bool inDialog() =>
            FocusManager.instance.primaryFocus?.context
                ?.findAncestorWidgetOfExactType<AlertDialog>() !=
            null;
        Future<bool?> open() => dialogs.showMessage(
          cancelable: false,
          dismissible: false,
          message: const TextSpan(text: 'launch interrupted'),
        );

        bool? accepted;
        unawaited(open().then((r) => accepted = r));
        await _settle(tester);
        showHome.value = true;
        await _settle(tester);
        expect(
          _label(FocusManager.instance.primaryFocus!),
          currentAppLocalizations.confirm,
          reason: 'the remote starts on the only button',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.select);
        await _settle(tester);
        expect(accepted, isTrue, reason: 'OK presses it');
        expect(
          _label(FocusManager.instance.primaryFocus!),
          contains(currentAppLocalizations.signInWithPhone),
          reason: 'after the message the remote is on the home again',
        );

        unawaited(open());
        await _settle(tester);
        for (final key in _arrows) {
          await tester.sendKeyEvent(key);
          await _settle(tester);
          expect(inDialog(), isTrue, reason: '$key left the message');
        }
      },
    );
  }

  testWidgets('recovery: e-mail, telegram and the login link', (tester) async {
    await _pump(
      tester,
      const RecoveryView(
        accessKey: _key,
        loginUrl: 'https://mgla.app/login/token',
      ),
    );
    await _expectRemoteReachesAll(tester);
  });
}
