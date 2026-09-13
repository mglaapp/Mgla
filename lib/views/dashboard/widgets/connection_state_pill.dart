import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum _TunnelState { connected, suspended, disconnected }

/// The answer to the first question a person has: is the tunnel up.
///
/// Three signals at once — word, dot shape and colour. Remove any one of them and the state is
/// still readable, which is what keeps it working for colour-blind eyes and in a screenshot.
class ConnectionStatePill extends ConsumerWidget {
  const ConnectionStatePill({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isStart = ref.watch(isStartProvider);
    final suspend = ref.watch(suspendProvider);
    final state = switch ((isStart, suspend)) {
      (true, true) => _TunnelState.suspended,
      (true, false) => _TunnelState.connected,
      _ => _TunnelState.disconnected,
    };
    final scheme = context.colorScheme;
    final appLocalizations = context.appLocalizations;
    final color = switch (state) {
      _TunnelState.connected => scheme.primary,
      _TunnelState.suspended => MglaPalette.warn,
      _TunnelState.disconnected => scheme.onSurfaceVariant,
    };
    final label = switch (state) {
      _TunnelState.connected => appLocalizations.connected,
      _TunnelState.suspended => appLocalizations.suspended,
      _TunnelState.disconnected => appLocalizations.disconnected,
    };
    return Semantics(
      liveRegion: true,
      label: label,
      child: AnimatedContainer(
        duration: MglaMotion.slow,
        curve: MglaMotion.cut,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            StateDot(filled: state != _TunnelState.disconnected, color: color),
            const SizedBox(width: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.bodyMedium?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
