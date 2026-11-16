import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/servers.dart';
import 'package:fl_clash/views/subscription.dart' show ourAccessKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

final linkCheckProvider = NotifierProvider<LinkCheck, LinkVerdict>(
  LinkCheck.new,
);

/// Main selector of our subscription: the select group that offers «Auto».
Group? linkMainGroup(List<Group> groups) {
  for (final group in groups) {
    if (group.type != GroupType.Selector) continue;
    if (group.all.any((p) => p.name == autoGroupName)) return group;
  }
  return null;
}

Map<String, List<String>> linkMembers(List<Group> groups) => {
  for (final g in groups)
    if (g.type == GroupType.URLTest) g.name: [for (final p in g.all) p.name],
};

class LinkCheck extends Notifier<LinkVerdict> {
  bool _running = false;
  bool _again = false;
  bool _refreshed = false;
  String? checkedChoice;

  @override
  LinkVerdict build() => const LinkVerdict(LinkStatus.idle);

  void reset() {
    checkedChoice = null;
    state = const LinkVerdict(LinkStatus.idle);
  }

  @visibleForTesting
  void show(LinkVerdict verdict) => state = verdict;

  bool get _wanted =>
      ref.read(isStartProvider) &&
      ourAccessKey(ref.read(profilesStateProvider)) != null;

  Future<void> _refreshStaleProfile() async {
    if (_refreshed) return;
    final groups = ref.read(groupsProvider);
    final stale = groups.any(
      (g) => g.type == GroupType.URLTest && isLegacyTestUrl(g.testUrl),
    );
    if (!stale) return;
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.type == ProfileType.file) return;
    _refreshed = true;
    try {
      await ref.read(profilesActionProvider.notifier).updateProfile(profile);
      await ref.read(setupActionProvider.notifier).applyProfile(silence: true);
      await Future<void>.delayed(const Duration(seconds: 1));
    } catch (e) {
      commonPrint.log(
        'link: profile refresh failed: $e',
        logLevel: LogLevel.warning,
      );
    }
  }

  Future<void> check({bool quiet = false}) async {
    if (_running) {
      _again = true;
      return;
    }
    if (!_wanted) return;
    _running = true;
    try {
      await _refreshStaleProfile();
      if (!ref.mounted || !_wanted) return;
      final groups = ref.read(groupsProvider);
      final main = linkMainGroup(groups);
      if (main == null) return;
      final selected =
          ref.read(selectedProxyNameProvider(main.name)) ?? main.now ?? '';
      if (selected.isEmpty) return;
      final before = state;
      if (!quiet || !before.passed) {
        state = const LinkVerdict(LinkStatus.checking);
      }
      final proxies = ref.read(proxiesActionProvider.notifier);
      final core = ref.read(coreHandlerProvider);
      final checker = LinkChecker(
        delay: (url, name) async => (await core.getDelay(url, name))?.value,
        select: (group, name) =>
            proxies.changeProxy(groupName: group, proxyName: name),
      );
      final verdict = await checker.run(
        main: main.name,
        selected: selected,
        auto: autoGroupName,
        hasAuto: main.all.any((p) => p.name == autoGroupName),
        members: linkMembers(groups),
      );
      if (!ref.mounted || !_wanted) return;
      if (verdict.status == LinkStatus.switched) {
        proxies.updateGroupsDebounce();
      }
      checkedChoice = verdict.status == LinkStatus.switched
          ? autoGroupName
          : selected;
      state = verdict;
      _announce(before, verdict);
    } catch (e) {
      commonPrint.log('link: check failed: $e', logLevel: LogLevel.warning);
      if (ref.mounted && state.status == LinkStatus.checking) {
        state = const LinkVerdict(LinkStatus.idle);
      }
    } finally {
      _running = false;
      if (_again) {
        _again = false;
        unawaited(check(quiet: true));
      }
    }
  }

  void _announce(LinkVerdict before, LinkVerdict now) {
    final l = currentAppLocalizations;
    if (now.status == LinkStatus.switched) {
      dialogs.showNotifier(l.linkSwitchedAuto, level: MessageLevel.warning);
    } else if (now.status == LinkStatus.failed &&
        before.status != LinkStatus.failed) {
      dialogs.showNotifier(l.linkFailedTip, level: MessageLevel.error);
    }
  }
}

/// Runs [LinkCheck]: once the tunnel is up, after the server changes, every few minutes.
class ServerLinkManager extends ConsumerStatefulWidget {
  final Widget child;

  const ServerLinkManager({super.key, required this.child});

  @override
  ConsumerState<ServerLinkManager> createState() => _ServerLinkManagerState();
}

class _ServerLinkManagerState extends ConsumerState<ServerLinkManager> {
  static const _settle = Duration(seconds: 2);
  static const _every = Duration(minutes: 5);

  Timer? _soon;
  Timer? _periodic;

  LinkCheck get _link => ref.read(linkCheckProvider.notifier);

  @override
  void initState() {
    super.initState();
    ref.listenManual(isStartProvider, (_, isStart) {
      _soon?.cancel();
      _periodic?.cancel();
      if (!isStart) {
        _link.reset();
        return;
      }
      _soon = Timer(_settle, () => _link.check());
      _periodic = Timer.periodic(_every, (_) => _link.check(quiet: true));
    }, fireImmediately: true);
    ref.listenManual(groupsProvider, (_, groups) {
      final main = linkMainGroup(groups);
      if (main == null || !ref.read(isStartProvider)) return;
      final choice = ref.read(selectedProxyNameProvider(main.name));
      final checked = _link.checkedChoice;
      if (choice == null || checked == null || choice == checked) return;
      _soon?.cancel();
      _soon = Timer(_settle, () => _link.check());
    });
  }

  @override
  void dispose() {
    _soon?.cancel();
    _periodic?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
