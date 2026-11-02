import 'dart:math' as math;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/svg.dart';
import 'package:material_ui/material_ui.dart';

String _bands(List<String> colors) {
  final h = 14 / colors.length;
  final out = StringBuffer();
  for (var i = 0; i < colors.length; i++) {
    out.write(
      '<rect x="0" y="${(h * i).toStringAsFixed(3)}" width="20" '
      'height="${(h + 0.05).toStringAsFixed(3)}" fill="${colors[i]}"/>',
    );
  }
  return out.toString();
}

String _usFlag() {
  const h = 14 / 13;
  final out = StringBuffer('<rect width="20" height="14" fill="#FFFFFF"/>');
  for (var i = 0; i < 13; i += 2) {
    out.write(
      '<rect x="0" y="${(h * i).toStringAsFixed(3)}" width="20" '
      'height="${h.toStringAsFixed(3)}" fill="#B22234"/>',
    );
  }
  out.write(
    '<rect width="8" height="${(h * 7).toStringAsFixed(3)}" fill="#3C3B6E"/>',
  );
  for (var r = 0; r < 4; r++) {
    for (var c = 0; c < 4; c++) {
      out.write(
        '<circle cx="${(1.1 + c * 1.95).toStringAsFixed(2)}" '
        'cy="${(1.0 + r * 1.75).toStringAsFixed(2)}" r="0.38" fill="#FFFFFF"/>',
      );
    }
  }
  return out.toString();
}

String _star(double cx, double cy, double r) {
  final points = <String>[];
  for (var i = 0; i < 10; i++) {
    final radius = i.isOdd ? r * 0.382 : r;
    final a = math.pi + math.pi / 5 * i;
    points.add(
      '${(cx + radius * math.cos(a)).toStringAsFixed(2)},'
      '${(cy + radius * math.sin(a)).toStringAsFixed(2)}',
    );
  }
  return '<polygon points="${points.join(' ')}" fill="#FFFFFF"/>';
}

/// Same drawings as the browser extension (mgla_extension/src/flags.js): Windows has no flag
/// emoji, it renders two letters.
final Map<String, String> _flagArt = {
  'nl': _bands(['#AE1C28', '#FFFFFF', '#21468B']),
  'de': _bands(['#000000', '#DD0000', '#FFCE00']),
  'fi':
      '<rect width="20" height="14" fill="#FFFFFF"/>'
      '<rect x="5.6" y="0" width="3.6" height="14" fill="#002F6C"/>'
      '<rect x="0" y="5.2" width="20" height="3.6" fill="#002F6C"/>',
  'us': _usFlag(),
  'gb':
      '<rect width="20" height="14" fill="#012169"/>'
      '<path d="M0 0L20 14M20 0L0 14" stroke="#FFFFFF" stroke-width="2.8"/>'
      '<path d="M0 0L20 14M20 0L0 14" stroke="#C8102E" stroke-width="0.9"/>'
      '<path d="M10 0V14M0 7H20" stroke="#FFFFFF" stroke-width="4.4"/>'
      '<path d="M10 0V14M0 7H20" stroke="#C8102E" stroke-width="2.6"/>',
  'tr':
      '<rect width="20" height="14" fill="#E30A17"/>'
      '<circle cx="7.4" cy="7" r="3.5" fill="#FFFFFF"/>'
      '<circle cx="8.3" cy="7" r="2.8" fill="#E30A17"/>'
      '${_star(11.75, 7, 1.4)}',
  // 03-11: Latvia (a real server) and the likely next countries, so a new server shows a flag
  // without waiting for an app release.
  'lv':
      '<rect width="20" height="14" fill="#9E3039"/>'
      '<rect x="0" y="5.6" width="20" height="2.8" fill="#FFFFFF"/>',
  'ee': _bands(['#0072CE', '#000000', '#FFFFFF']),
  'lt': _bands(['#FDB913', '#006A44', '#C1272D']),
  'pl': _bands(['#FFFFFF', '#DC143C']),
  'at': _bands(['#ED2939', '#FFFFFF', '#ED2939']),
  'fr':
      '<rect x="0" y="0" width="6.72" height="14" fill="#0055A4"/>'
      '<rect x="6.67" y="0" width="6.72" height="14" fill="#FFFFFF"/>'
      '<rect x="13.33" y="0" width="6.67" height="14" fill="#EF4135"/>',
  'se':
      '<rect width="20" height="14" fill="#006AA7"/>'
      '<rect x="5.6" y="0" width="2.8" height="14" fill="#FECC00"/>'
      '<rect x="0" y="5.6" width="20" height="2.8" fill="#FECC00"/>',
  'ch':
      '<rect width="20" height="14" fill="#DA291C"/>'
      '<rect x="8.6" y="3" width="2.8" height="8" fill="#FFFFFF"/>'
      '<rect x="6" y="5.6" width="8" height="2.8" fill="#FFFFFF"/>',
};

bool hasFlagArt(String cc) => _flagArt.containsKey(cc.toLowerCase());

class CountryFlag extends StatelessWidget {
  final String cc;
  final double width;

  const CountryFlag({super.key, required this.cc, this.width = 24});

  @override
  Widget build(BuildContext context) {
    final art = _flagArt[cc.toLowerCase()];
    final height = width * 0.7;
    if (art == null) {
      return Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: context.colorScheme.outlineVariant),
        ),
        child: Text(
          cc.toUpperCase(),
          style: context.textTheme.labelSmall?.copyWith(fontSize: 9),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SvgPicture.string(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 14">$art</svg>',
        width: width,
        height: height,
      ),
    );
  }
}

/// «Auto» — the fastest live server, chosen by the core itself (url-test group of the subscription,
/// the site names it so: omnivpn/sub.py AUTO_NAME). Shown first when the site sends server groups.
const autoServerId = 'auto';
const autoGroupName = 'Auto';

/// Server list for the picker: «Auto» first when the subscription carries server groups (03-11,
/// several nodes); otherwise the list as the site sent it (one node — nothing to switch).
List<ServerInfo> pickerServers(List<ServerInfo> servers) {
  if (!servers.any((s) => s.available && s.group != null)) return servers;
  return [
    const ServerInfo(
      id: autoServerId,
      cc: '',
      names: {},
      available: true,
      group: autoGroupName,
    ),
    ...servers,
  ];
}

/// The subscription's main selector: the select group that lists the server groups (or «Auto»).
/// null — the profile is not ours or carries no server groups yet (old subscription).
String? mainGroupOf(List<Group> groups, List<ServerInfo> servers) {
  final wanted = {
    for (final s in servers)
      if (s.group != null) s.group!,
  };
  if (wanted.isEmpty) return null;
  for (final group in groups) {
    if (group.type != GroupType.Selector) continue;
    if (group.all.any((p) => wanted.contains(p.name))) return group.name;
  }
  return null;
}

/// Server the app connects through. With server groups — the one whose group is selected in the
/// main selector (what the core really uses); without — the first one that can be chosen.
ServerInfo? currentServerOf(List<ServerInfo> servers, {String? selected}) {
  if (selected != null) {
    for (final server in servers) {
      if (server.group == selected) return server;
    }
  }
  for (final server in servers) {
    if (server.available) return server;
  }
  return null;
}

/// [currentServerOf] from the live core state: main selector of the subscription and its choice.
ServerInfo? liveServerOf(WidgetRef ref, List<ServerInfo> servers) {
  final list = pickerServers(servers);
  final main = mainGroupOf(ref.watch(groupsProvider), list);
  final selected = main == null
      ? null
      : ref.watch(selectedProxyNameProvider(main));
  return currentServerOf(list, selected: selected);
}

/// Name of the server in the UI language; «Auto» has no name from the site.
String serverName(BuildContext context, ServerInfo server) {
  if (server.id == autoServerId) return context.appLocalizations.serverAuto;
  return server.nameFor(Localizations.localeOf(context).languageCode);
}

/// Flag of the server; «Auto» — a bolt, it is not a country.
Widget serverLeading(BuildContext context, ServerInfo server, double width) {
  if (server.id == autoServerId) {
    return SizedBox(
      width: width,
      height: width * 0.7,
      child: Icon(
        Icons.bolt,
        size: width * 0.7,
        color: context.colorScheme.primary,
      ),
    );
  }
  return CountryFlag(cc: server.cc, width: width);
}

class BusyBadge extends StatelessWidget {
  const BusyBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final style = context.textTheme.labelMedium?.copyWith(
      color: MglaPalette.warn,
      fontWeight: FontWeight.w600,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final h in const [4.0, 7.0, 11.0])
          Container(
            width: 3,
            height: h,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              color: MglaPalette.warn,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        const SizedBox(width: 4),
        Text(context.appLocalizations.serverBusy, style: style),
      ],
    );
  }
}

class ServersView extends ConsumerStatefulWidget {
  final Future<Result<List<ServerInfo>>> Function()? fetchServers;
  final List<ServerInfo>? initial;

  const ServersView({super.key, this.fetchServers, this.initial});

  @override
  ConsumerState<ServersView> createState() => _ServersViewState();
}

class _ServersViewState extends ConsumerState<ServersView> {
  List<ServerInfo>? _servers;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _servers = widget.initial;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final result = await (widget.fetchServers ?? request.servers)();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) _servers = result.data;
      _failed = result.isError && _servers == null;
    });
  }

  /// Choosing = switching the main selector of the subscription in the core (03-11). Until then
  /// the tap only closed the list: with one real server there was nothing to switch, and with
  /// three the choice silently stayed on the first one (owner's screenshot 03-11).
  Future<void> _choose(ServerInfo server, String? main) async {
    final group = server.group;
    if (main != null && group != null) {
      await ref
          .read(proxiesActionProvider.notifier)
          .changeProxy(groupName: main, proxyName: group);
    }
    if (mounted) Navigator.of(context).pop(server.id);
  }

  Widget _row(ServerInfo server, ServerInfo? current, String? main) {
    final l = context.appLocalizations;
    final name = serverName(context, server);
    final chosen = server.id == current?.id;
    return ListTile(
      key: ValueKey('server-${server.id}'),
      leading: serverLeading(context, server, 28),
      title: Text(
        name,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: server.available
              ? null
              : context.colorScheme.onSurface.withValues(alpha: 0.55),
        ),
      ),
      trailing: server.available
          ? (chosen
                ? Icon(Icons.check, color: context.colorScheme.primary)
                : null)
          : const BusyBadge(),
      selected: chosen,
      onTap: server.available
          ? () => _choose(server, main)
          : () => dialogs.showNotifier(
              l.serverBusyTip,
              level: MessageLevel.warning,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final servers = _servers == null ? null : pickerServers(_servers!);
    final main = servers == null
        ? null
        : mainGroupOf(ref.watch(groupsProvider), servers);
    final current = servers == null ? null : liveServerOf(ref, _servers!);
    return BaseScaffold(
      title: l.serversTitle,
      body: servers == null
          ? Center(
              child: _failed
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l.serversLoadError),
                        const SizedBox(height: 12),
                        FilledButton.tonal(
                          onPressed: _load,
                          child: Text(l.sync),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: kMaterialListPadding.copyWith(top: 8, bottom: 16),
              children: [
                for (final server in servers) _row(server, current, main),
              ],
            ),
    );
  }
}
