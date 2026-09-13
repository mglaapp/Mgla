import 'package:fl_clash/common/common.dart';
import 'package:material_ui/material_ui.dart';

/// Filled when something runs, hollow when it does not.
///
/// The shape carries the state on its own: colour is the third signal, never the only one.
class StateDot extends StatelessWidget {
  final bool filled;
  final Color color;
  final double size;

  const StateDot({
    super.key,
    required this.filled,
    required this.color,
    this.size = 8,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: MglaMotion.slow,
      curve: MglaMotion.cut,
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: filled ? color : Colors.transparent,
        border: Border.all(color: color, width: 1.5),
      ),
    );
  }
}
