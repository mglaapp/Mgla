import 'package:fl_clash/common/link_check.dart';
import 'package:flutter_test/flutter_test.dart';

class _Net {
  final Set<String> alive;
  final Map<String, String> choice;
  final Map<String, List<String>> members;
  final List<String> calls = [];
  final List<String> selects = [];
  final List<Duration> slept = [];
  final Map<String, Duration> pickedAt = {};
  final Set<String> retested = {};
  Duration now = Duration.zero;
  bool refuse = false;

  _Net({required this.alive, required this.choice, required this.members});

  DateTime clock() => DateTime(2026).add(now);

  Future<void> sleep(Duration duration) async {
    slept.add(duration);
    now += duration;
  }

  String _leaf(String name) {
    final picked = choice[name];
    return picked == null ? name : _leaf(picked);
  }

  Future<int?> delay(String url, String name) async {
    calls.add('$name@$url');
    now += const Duration(milliseconds: 300);
    final group = members[name];
    if (group == null) {
      retested.add(name);
    } else {
      final at = pickedAt[name];
      if (at == null) {
        pickedAt[name] = now;
      } else if (group.any(retested.contains) &&
          now - at >= const Duration(seconds: 10)) {
        final live = group.where((m) => alive.contains(_leaf(m)));
        if (live.isNotEmpty) choice[name] = live.first;
        pickedAt[name] = now;
      }
    }
    return alive.contains(_leaf(name)) ? 120 : -1;
  }

  Future<bool> select(String group, String name) async {
    selects.add('$group->$name');
    if (refuse) return false;
    choice[group] = name;
    return true;
  }
}

LinkChecker _checker(_Net net) => LinkChecker(
  delay: net.delay,
  select: net.select,
  sleep: net.sleep,
  clock: net.clock,
);

Future<LinkVerdict> _run(_Net net, String selected) => _checker(net).run(
  main: 'Mgla',
  selected: selected,
  auto: 'Auto',
  hasAuto: true,
  members: net.members,
);

void main() {
  final members = {
    'Auto': ['SE Reality', 'SE AWG', 'NL Reality', 'NL AWG'],
    'Mgla SE': ['SE Reality', 'SE AWG'],
    'Mgla NL': ['NL Reality', 'NL AWG'],
  };

  test('the check goes to the heavy probe, not generate_204', () async {
    final net = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla NL': 'NL Reality'},
      members: members,
    );
    await _run(net, 'Mgla NL');
    expect(net.calls, isNotEmpty);
    expect(net.calls.every((c) => c.endsWith('@$linkProbeUrl')), isTrue);
    expect(linkProbeUrl, isNot(contains('generate_204')));
  });

  test('a live server stays, nothing is switched', () async {
    final net = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla NL': 'NL Reality'},
      members: members,
    );
    expect(await _run(net, 'Mgla NL'), const LinkVerdict(LinkStatus.ok));
    expect(net.selects, isEmpty);
  });

  test('a country whose other protocol works re-picks inside itself', () async {
    final net = _Net(
      alive: {'SE AWG', 'NL Reality'},
      choice: {'Mgla SE': 'SE Reality'},
      members: members,
    );
    expect(await _run(net, 'Mgla SE'), const LinkVerdict(LinkStatus.ok));
    expect(net.selects, isEmpty);
    expect(net.calls, contains('SE AWG@$linkProbeUrl'));
  });

  test('a frozen country goes to Auto, Auto re-picks a live node', () async {
    final net = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla SE': 'SE Reality', 'Auto': 'SE Reality'},
      members: members,
    );
    final verdict = await _run(net, 'Mgla SE');
    expect(verdict, const LinkVerdict(LinkStatus.switched, from: 'Mgla SE'));
    expect(verdict.passed, isTrue);
    expect(net.selects, ['Mgla->Auto']);
  });

  test('Auto itself re-picks without a switch', () async {
    final net = _Net(
      alive: {'NL AWG'},
      choice: {'Auto': 'SE Reality'},
      members: members,
    );
    expect(await _run(net, 'Auto'), const LinkVerdict(LinkStatus.ok));
    expect(net.selects, isEmpty);
  });

  test('nothing passes -> failed, never «connected»', () async {
    final net = _Net(
      alive: {},
      choice: {'Mgla SE': 'SE Reality', 'Auto': 'SE Reality'},
      members: members,
    );
    final verdict = await _run(net, 'Mgla SE');
    expect(verdict.status, LinkStatus.failed);
    expect(verdict.passed, isFalse);
    expect(await _run(net, 'Auto'), const LinkVerdict(LinkStatus.failed));
  });

  test('the core refused the switch -> failed, not «switched»', () async {
    final net = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla SE': 'SE Reality', 'Auto': 'SE Reality'},
      members: members,
    )..refuse = true;
    expect(await _run(net, 'Mgla SE'), const LinkVerdict(LinkStatus.failed));
  });

  test('without Auto in the profile a dead server is just failed', () async {
    final net = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla SE': 'SE Reality'},
      members: members,
    );
    final verdict = await _checker(net).run(
      main: 'Mgla',
      selected: 'Mgla SE',
      auto: 'Auto',
      hasAuto: false,
      members: members,
    );
    expect(verdict.status, LinkStatus.failed);
    expect(net.selects, isEmpty);
  });

  test('a re-check waits out the group pick hold, a pass does not', () async {
    final net = _Net(
      alive: {'NL AWG'},
      choice: {'Auto': 'SE Reality'},
      members: members,
    );
    await _run(net, 'Auto');
    expect(net.slept, hasLength(1));
    expect(net.slept.single, lessThanOrEqualTo(groupPickHold));
    expect(net.slept.single, greaterThan(const Duration(seconds: 8)));

    final live = _Net(
      alive: {'NL Reality'},
      choice: {'Mgla NL': 'NL Reality'},
      members: members,
    );
    await _run(live, 'Mgla NL');
    expect(live.slept, isEmpty);
  });

  test('legacy test address is recognised, the new one is not', () {
    expect(isLegacyTestUrl('https://www.gstatic.com/generate_204'), isTrue);
    expect(isLegacyTestUrl(linkProbeUrl), isFalse);
    expect(isLegacyTestUrl(null), isFalse);
  });

  test('verdict equality and text', () {
    const a = LinkVerdict(LinkStatus.switched, from: 'x');
    expect(a, const LinkVerdict(LinkStatus.switched, from: 'x'));
    expect(a == const LinkVerdict(LinkStatus.switched), isFalse);
    expect(
      a.hashCode,
      const LinkVerdict(LinkStatus.switched, from: 'x').hashCode,
    );
    expect(a.toString(), contains('switched'));
  });
}
