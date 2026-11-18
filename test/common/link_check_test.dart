import 'package:fl_clash/common/link_check.dart';
import 'package:flutter_test/flutter_test.dart';

const _url = LinkPick.urlTest;
const _fb = LinkPick.fallback;

/// The core as far as the check sees it (mihomo, adapter.go / urltest.go / fallback.go):
/// every name keeps its own «live» mark from the last time THAT name was tested; a fallback
/// takes its first member marked live, at once; a url-test takes the first live one and holds
/// that pick for 10 s. A mark goes stale until the name is tested again — exactly what left a
/// frozen direct server «live» in front of the bridge.
class _Core {
  final Map<String, LinkGroup> groups;
  final Set<String> works;
  final Map<String, bool> mark;
  final Map<String, String> picked = {};
  final Map<String, Duration> pickedAt = {};
  final List<String> calls = [];
  final List<String> selects = [];
  final List<Duration> slept = [];
  final Set<String> urls = {};
  Duration now = Duration.zero;
  bool refuse = false;

  _Core({required this.groups, required this.works, Map<String, bool>? mark})
    : mark = {...?mark};

  DateTime clock() => DateTime(2026).add(now);

  Future<void> sleep(Duration duration) async {
    slept.add(duration);
    now += duration;
  }

  bool _live(String name) => mark[name] ?? true;

  String leaf(String name) {
    final group = groups[name];
    if (group == null) return name;
    final live = group.members.where(_live);
    final best = live.isNotEmpty ? live.first : group.members.first;
    if (group.pick == _fb) return leaf(best);
    final at = pickedAt[name];
    if (at == null || now - at >= const Duration(seconds: 10)) {
      picked[name] = best;
      pickedAt[name] = now;
    }
    return leaf(picked[name]!);
  }

  Future<int?> delay(String url, String name) async {
    calls.add(name);
    urls.add(url);
    final ok = works.contains(leaf(name));
    now += const Duration(milliseconds: 300);
    mark[name] = ok;
    return ok ? 120 : -1;
  }

  Future<bool> select(String group, String name) async {
    selects.add('$group->$name');
    return !refuse;
  }
}

LinkChecker _checker(_Core core) => LinkChecker(
  delay: core.delay,
  select: core.select,
  sleep: core.sleep,
  clock: core.clock,
);

Future<LinkVerdict> _run(_Core core, String selected, {bool hasAuto = true}) =>
    _checker(core).run(
      main: 'Mgla',
      selected: selected,
      auto: 'Auto',
      hasAuto: hasAuto,
      groups: core.groups,
    );

/// Before the bridge: url-test everywhere.
const _plain = {
  'Auto': LinkGroup(_url, ['SE Reality', 'SE AWG', 'NL Reality', 'NL AWG']),
  'Mgla SE': LinkGroup(_url, ['SE Reality', 'SE AWG']),
  'Mgla NL': LinkGroup(_url, ['NL Reality', 'NL AWG']),
};

/// The live subscription since 17-11 (omnivpn sub.mihomo_config with bridges.json).
const _bridged = {
  'Auto': LinkGroup(_fb, [
    'Auto direct',
    'DE Reality via RU',
    'DE XHTTP via RU',
    'SE Reality via RU',
  ]),
  'Auto direct': LinkGroup(_url, ['DE Reality', 'DE XHTTP', 'SE Reality']),
  'Mgla DE': LinkGroup(_fb, [
    'DE Reality',
    'DE XHTTP',
    'DE Reality via RU',
    'DE XHTTP via RU',
  ]),
  'Mgla SE': LinkGroup(_fb, ['SE Reality', 'SE Reality via RU']),
};

void main() {
  group('before the bridge (url-test groups)', () {
    test('the check goes to the heavy probe, not generate_204', () async {
      final core = _Core(groups: _plain, works: {'NL Reality'});
      await _run(core, 'Mgla NL');
      expect(core.calls, isNotEmpty);
      expect(core.urls, {linkProbeUrl});
      expect(linkProbeUrl, isNot(contains('generate_204')));
    });

    test('a live server stays, nothing is switched', () async {
      final core = _Core(groups: _plain, works: {'NL Reality'});
      expect(await _run(core, 'Mgla NL'), const LinkVerdict(LinkStatus.ok));
      expect(core.selects, isEmpty);
      expect(core.slept, isEmpty);
    });

    test(
      'a country whose other protocol works re-picks inside itself',
      () async {
        final core = _Core(groups: _plain, works: {'SE AWG', 'NL Reality'});
        expect(await _run(core, 'Mgla SE'), const LinkVerdict(LinkStatus.ok));
        expect(core.selects, isEmpty);
        expect(core.calls, contains('SE AWG'));
        expect(core.leaf('Mgla SE'), 'SE AWG');
      },
    );

    test('a frozen country goes to Auto, Auto re-picks a live node', () async {
      final core = _Core(groups: _plain, works: {'NL Reality'});
      final verdict = await _run(core, 'Mgla SE');
      expect(verdict, const LinkVerdict(LinkStatus.switched, from: 'Mgla SE'));
      expect(verdict.passed, isTrue);
      expect(core.selects, ['Mgla->Auto']);
    });

    test('Auto itself re-picks without a switch', () async {
      final core = _Core(groups: _plain, works: {'NL AWG'});
      expect(await _run(core, 'Auto'), const LinkVerdict(LinkStatus.ok));
      expect(core.selects, isEmpty);
    });

    test('a re-check waits out the url-test pick hold, once', () async {
      final core = _Core(groups: _plain, works: {'NL AWG'});
      await _run(core, 'Auto');
      expect(core.slept, hasLength(1));
      expect(core.slept.single, lessThanOrEqualTo(groupPickHold));
      expect(core.slept.single, greaterThan(const Duration(seconds: 8)));
    });

    test('without Auto in the profile a dead server is just failed', () async {
      final core = _Core(groups: _plain, works: {'NL Reality'});
      final verdict = await _run(core, 'Mgla SE', hasAuto: false);
      expect(verdict.status, LinkStatus.failed);
      expect(core.selects, isEmpty);
    });
  });

  group('with the bridge (fallback groups, 17-11)', () {
    const bridges = {
      'DE Reality via RU',
      'DE XHTTP via RU',
      'SE Reality via RU',
    };

    test(
      'direct first: a live direct server keeps the country off the bridge',
      () async {
        final core = _Core(
          groups: _bridged,
          works: {'DE Reality', 'DE XHTTP', 'SE Reality', ...bridges},
        );
        expect(await _run(core, 'Mgla DE'), const LinkVerdict(LinkStatus.ok));
        expect(core.calls, ['Mgla DE']);
        expect(core.leaf('Mgla DE'), 'DE Reality');
      },
    );

    test(
      'a country whose direct servers froze goes on through its bridge',
      () async {
        // The core still holds the frozen direct servers «live» from its last check.
        final core = _Core(groups: _bridged, works: bridges);
        expect(await _run(core, 'Mgla DE'), const LinkVerdict(LinkStatus.ok));
        expect(core.selects, isEmpty);
        expect(core.calls, containsAll(['DE Reality', 'DE XHTTP']));
        expect(core.leaf('Mgla DE'), 'DE Reality via RU');
        // a fallback re-picks at once: nothing to wait out
        expect(core.slept, isEmpty);
      },
    );

    test('Auto goes past the hidden «Auto direct» to a bridge', () async {
      final core = _Core(groups: _bridged, works: {'SE Reality via RU'});
      expect(await _run(core, 'Auto'), const LinkVerdict(LinkStatus.ok));
      expect(core.selects, isEmpty);
      expect(core.leaf('Auto'), 'SE Reality via RU');
      // the inner group is asked again only after its servers and the pick hold
      final inner = core.calls.lastIndexOf('Auto direct');
      expect(inner, greaterThan(0));
      for (final server in ['DE Reality', 'DE XHTTP', 'SE Reality']) {
        expect(core.calls.indexOf(server), lessThan(inner));
      }
      expect(core.slept, hasLength(1));
      expect(core.calls.last, 'Auto');
    });

    test(
      'the bridge of the country is dead too -> Auto takes another',
      () async {
        final core = _Core(groups: _bridged, works: {'SE Reality via RU'});
        final verdict = await _run(core, 'Mgla DE');
        expect(
          verdict,
          const LinkVerdict(LinkStatus.switched, from: 'Mgla DE'),
        );
        expect(core.selects, ['Mgla->Auto']);
        expect(core.leaf('Auto'), 'SE Reality via RU');
      },
    );

    test('nothing passes, the bridge included -> failed', () async {
      final core = _Core(groups: _bridged, works: {});
      final verdict = await _run(core, 'Mgla DE');
      expect(verdict, const LinkVerdict(LinkStatus.failed, from: 'Mgla DE'));
      expect(verdict.passed, isFalse);
      expect(await _run(core, 'Auto'), const LinkVerdict(LinkStatus.failed));
    });

    test('the core refused the switch -> failed, not «switched»', () async {
      final core = _Core(groups: _bridged, works: {'SE Reality via RU'})
        ..refuse = true;
      expect(await _run(core, 'Mgla DE'), const LinkVerdict(LinkStatus.failed));
    });

    test('a group inside itself does not hang the check', () async {
      final core = _Core(
        groups: const {
          'Loop': LinkGroup(_fb, ['Loop', 'X']),
        },
        works: {'X'},
        mark: {'Loop': false},
      );
      expect(await _run(core, 'Loop', hasAuto: false), isA<LinkVerdict>());
    });
  });

  test('a bridge server is told by its name', () {
    expect(isBridgeProxy('DE Reality via RU'), isTrue);
    expect(isBridgeProxy('DE Reality'), isFalse);
    expect(isBridgeProxy('Mgla DE'), isFalse);
    expect(isBridgeProxy(null), isFalse);
  });

  test('legacy test address is recognised, the new one is not', () {
    expect(isLegacyTestUrl('https://www.gstatic.com/generate_204'), isTrue);
    expect(isLegacyTestUrl(linkProbeUrl), isFalse);
    expect(isLegacyTestUrl(null), isFalse);
  });

  test('verdict equality, text and the bridge mark', () {
    const a = LinkVerdict(LinkStatus.switched, from: 'x');
    expect(a, const LinkVerdict(LinkStatus.switched, from: 'x'));
    expect(a == const LinkVerdict(LinkStatus.switched), isFalse);
    expect(
      a.hashCode,
      const LinkVerdict(LinkStatus.switched, from: 'x').hashCode,
    );
    expect(a.toString(), contains('switched'));
    expect(
      a.withVia(true),
      const LinkVerdict(LinkStatus.switched, from: 'x', via: true),
    );
    expect(a.withVia(true) == a, isFalse);
    // a failed check is never «via Russia»
    expect(const LinkVerdict(LinkStatus.failed).withVia(true).via, isFalse);
  });
}
