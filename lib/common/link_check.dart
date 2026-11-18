import 'dart:async';

/// Server check after connecting (16-11, ticket #204): Russian providers freeze a connection to a
/// foreign hoster after ~16 KB, so a small check passed while no site opened. This answer weighs
/// 32 KB in its headers (the core reads only headers), and passes only when it all came through.
const linkProbeUrl = 'https://mgla.app/probe';

const _legacyTestUrlMark = 'generate_204';

bool isLegacyTestUrl(String? url) =>
    url != null && url.contains(_legacyTestUrlMark);

/// The subscription names a server reached through a bridge `DE Reality via RU` (omnivpn
/// sub.bridge_suffix, 17-11): the bridge in Russia forwards to the same node.
const bridgeProxyMark = ' via RU';

bool isBridgeProxy(String? name) =>
    name != null && name.endsWith(bridgeProxyMark);

enum LinkStatus { idle, checking, ok, switched, failed }

class LinkVerdict {
  final LinkStatus status;
  final String? from;

  /// Passed, and the traffic goes through the bridge in Russia: the direct servers are cut.
  final bool via;

  const LinkVerdict(this.status, {this.from, this.via = false});

  bool get passed => status == LinkStatus.ok || status == LinkStatus.switched;

  LinkVerdict withVia(bool value) =>
      LinkVerdict(status, from: from, via: value && passed);

  @override
  bool operator ==(Object other) =>
      other is LinkVerdict &&
      other.status == status &&
      other.from == from &&
      other.via == via;

  @override
  int get hashCode => Object.hash(status, from, via);

  @override
  String toString() => 'LinkVerdict($status, from: $from, via: $via)';
}

typedef LinkDelay = Future<int?> Function(String url, String proxyName);
typedef LinkSelect = Future<bool> Function(String group, String proxyName);
typedef LinkSleep = Future<void> Function(Duration duration);

/// A url-test group of the core keeps its pick for 10 s (fastSingle), re-tests do not reset it.
const groupPickHold = Duration(milliseconds: 10500);

/// How a group of the core picks its server.
///
/// [urlTest] — the fastest live one, held for [groupPickHold]. [fallback] — the first live one
/// in order, at once (17-11: country = direct protocols first, then the same node via the
/// bridge; Auto = fallback over the hidden url-test «Auto direct», then the bridges).
enum LinkPick { urlTest, fallback }

class LinkGroup {
  final LinkPick pick;
  final List<String> members;

  const LinkGroup(this.pick, this.members);
}

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

/// What a re-check of one group has to test, bottom up.
///
/// The core marks a server live or dead only when that very name is tested: a fallback over a
/// group reads the inner group's own mark, not its servers'. So servers go first, then inner
/// groups from the deepest up, and only then the group itself is asked again.
class _Retest {
  final Set<String> leaves = {};
  final Map<String, int> _height = {};
  bool holds = false;

  _Retest(String root, Map<String, LinkGroup> groups) {
    _walk(root, groups, {});
    _height.remove(root);
  }

  int _walk(String name, Map<String, LinkGroup> groups, Set<String> path) {
    final group = groups[name];
    if (group == null || path.contains(name)) {
      leaves.add(name);
      return 0;
    }
    final known = _height[name];
    if (known != null) return known;
    if (group.pick == LinkPick.urlTest) holds = true;
    var height = 1;
    path.add(name);
    for (final member in group.members) {
      final h = _walk(member, groups, path) + 1;
      if (h > height) height = h;
    }
    path.remove(name);
    _height[name] = height;
    return height;
  }

  /// Inner groups by height: every group comes after all groups inside it.
  List<List<String>> get levels {
    final byHeight = <int, List<String>>{};
    for (final entry in _height.entries) {
      byHeight.putIfAbsent(entry.value, () => []).add(entry.key);
    }
    final heights = byHeight.keys.toList()..sort();
    return [for (final h in heights) byHeight[h]!];
  }
}

class LinkChecker {
  final LinkDelay delay;
  final LinkSelect select;
  final LinkSleep sleep;
  final DateTime Function() clock;
  final String url;

  const LinkChecker({
    required this.delay,
    required this.select,
    this.sleep = _sleep,
    this.clock = DateTime.now,
    this.url = linkProbeUrl,
  });

  Future<bool> _passes(String proxyName) async {
    final ms = await delay(url, proxyName);
    return ms != null && ms > 0;
  }

  Future<void> _retest(Iterable<String> names) async {
    await Future.wait(names.map((m) => delay(url, m)));
  }

  Future<bool> _passesAfterRetest(
    String proxyName,
    Map<String, LinkGroup> groups,
  ) async {
    final started = clock();
    if (await _passes(proxyName)) return true;
    if (!groups.containsKey(proxyName)) return false;
    final plan = _Retest(proxyName, groups);
    if (plan.leaves.isEmpty) return false;
    await _retest(plan.leaves);
    if (plan.holds) {
      final left = groupPickHold - clock().difference(started);
      if (left > Duration.zero) await sleep(left);
    }
    for (final level in plan.levels) {
      await _retest(level);
    }
    return _passes(proxyName);
  }

  /// [groups] — every url-test and fallback group, hidden ones too: re-testing their servers
  /// makes them re-pick, and the bridge is just the last server of a fallback.
  Future<LinkVerdict> run({
    required String main,
    required String selected,
    required String auto,
    required bool hasAuto,
    required Map<String, LinkGroup> groups,
  }) async {
    if (await _passesAfterRetest(selected, groups)) {
      return const LinkVerdict(LinkStatus.ok);
    }
    if (!hasAuto || selected == auto) {
      return const LinkVerdict(LinkStatus.failed);
    }
    if (!await select(main, auto)) {
      return const LinkVerdict(LinkStatus.failed);
    }
    if (await _passesAfterRetest(auto, groups)) {
      return LinkVerdict(LinkStatus.switched, from: selected);
    }
    return LinkVerdict(LinkStatus.failed, from: selected);
  }
}
