import 'dart:async';

/// Server check after connecting (16-11, ticket #204): Russian providers freeze a connection to a
/// foreign hoster after ~16 KB, so a small check passed while no site opened. This answer weighs
/// 32 KB in its headers (the core reads only headers), and passes only when it all came through.
const linkProbeUrl = 'https://mgla.app/probe';

const _legacyTestUrlMark = 'generate_204';

bool isLegacyTestUrl(String? url) =>
    url != null && url.contains(_legacyTestUrlMark);

enum LinkStatus { idle, checking, ok, switched, failed }

class LinkVerdict {
  final LinkStatus status;
  final String? from;

  const LinkVerdict(this.status, {this.from});

  bool get passed => status == LinkStatus.ok || status == LinkStatus.switched;

  @override
  bool operator ==(Object other) =>
      other is LinkVerdict && other.status == status && other.from == from;

  @override
  int get hashCode => Object.hash(status, from);

  @override
  String toString() => 'LinkVerdict($status, from: $from)';
}

typedef LinkDelay = Future<int?> Function(String url, String proxyName);
typedef LinkSelect = Future<bool> Function(String group, String proxyName);
typedef LinkSleep = Future<void> Function(Duration duration);

/// A url-test group of the core keeps its pick for 10 s (fastSingle), re-tests do not reset it.
const groupPickHold = Duration(milliseconds: 10500);

Future<void> _sleep(Duration duration) => Future<void>.delayed(duration);

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

  Future<void> _retest(List<String> members) async {
    await Future.wait(members.map((m) => delay(url, m)));
  }

  Future<bool> _passesAfterRetest(
    String proxyName,
    Map<String, List<String>> members,
  ) async {
    final started = clock();
    if (await _passes(proxyName)) return true;
    final own = members[proxyName];
    if (own == null || own.isEmpty) return false;
    await _retest(own);
    final left = groupPickHold - clock().difference(started);
    if (left > Duration.zero) await sleep(left);
    return _passes(proxyName);
  }

  /// [members] — leaves of every url-test group: re-testing them makes the group re-pick.
  Future<LinkVerdict> run({
    required String main,
    required String selected,
    required String auto,
    required bool hasAuto,
    required Map<String, List<String>> members,
  }) async {
    if (await _passesAfterRetest(selected, members)) {
      return const LinkVerdict(LinkStatus.ok);
    }
    if (!hasAuto || selected == auto) {
      return const LinkVerdict(LinkStatus.failed);
    }
    if (!await select(main, auto)) {
      return const LinkVerdict(LinkStatus.failed);
    }
    if (await _passesAfterRetest(auto, members)) {
      return LinkVerdict(LinkStatus.switched, from: selected);
    }
    return LinkVerdict(LinkStatus.failed, from: selected);
  }
}
