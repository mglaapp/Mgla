import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/servers.dart';
import 'package:fl_clash/views/subscription.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Плитка «Сервер» (решение владельца 08-10): страна, через которую идёт VPN; нажатие —
/// список серверов. Без нашей подписки страна была бы неправдой, и сервер не спрашивается.
class ServerCard extends ConsumerStatefulWidget {
  final Future<Result<List<ServerInfo>>> Function()? fetchServers;

  const ServerCard({super.key, this.fetchServers});

  @override
  ConsumerState<ServerCard> createState() => _ServerCardState();
}

class _ServerCardState extends ConsumerState<ServerCard> {
  List<ServerInfo>? _servers;
  bool _failed = false;
  bool _ours = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final ours = ourAccessKey(ref.read(profilesStateProvider)) != null;
    if (mounted) setState(() => _ours = ours);
    if (!ours) return;
    final result = await (widget.fetchServers ?? request.servers)();
    if (!mounted) return;
    setState(() {
      if (result.isSuccess) _servers = result.data;
      _failed = result.isError;
    });
  }

  Future<void> _open() async {
    await BaseNavigator.push(
      context,
      ServersView(fetchServers: widget.fetchServers, initial: _servers),
    );
    if (mounted) await _load();
  }

  String _line(ServerInfo? current, String language) {
    final l = context.appLocalizations;
    if (!_ours) return l.noAccountShort;
    if (current != null) return current.nameFor(language);
    return _servers == null && _failed ? l.serversLoadError : '…';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profilesStateProvider, (prev, next) {
      final was = prev == null ? null : ourAccessKey(prev);
      if (ourAccessKey(next) != was) unawaited(_load());
    });
    final l = context.appLocalizations;
    final servers = _ours ? _servers : null;
    final current = servers == null ? null : currentServerOf(servers);
    final language = Localizations.localeOf(context).languageCode;
    final busy = servers?.where((s) => !s.available).length ?? 0;
    return SizedBox(
      height: getWidgetHeight(1),
      child: CommonCard(
        radius: AppCorner.lg,
        info: Info(label: l.serverTitle, iconData: Icons.public),
        onPressed: _open,
        child: Container(
          padding: baseInfoEdgeInsets.copyWith(top: 4, bottom: 8, right: 12),
          child: Row(
            children: [
              if (current != null) ...[
                CountryFlag(cc: current.cc, width: 22),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  _line(current, language),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textTheme.titleSmall
                      ?.adjustSize(-2)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (busy > 0)
                Text(
                  '+$busy',
                  style: context.textTheme.labelMedium?.copyWith(
                    color: context.colorScheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right,
                color: context.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
