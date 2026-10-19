import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The intro every launch opens with: the mark, an ice cut, the slogan — and gone.
///
/// Owner, 20-10: drop the upstream disclaimer that greeted people first ("non-commercial use
/// only" on a paid service), put our slogan there and a very fast, beautiful intro. Fast is the
/// requirement, not the decoration: under a second, nothing to press, and it never holds the
/// app back — the app builds and starts underneath from the first frame, the intro only covers
/// it and lets every touch and remote key through.
///
/// The motion is the design code's "cut": one curve, no bounce. The mark settles, a thin ice line
/// is drawn left to right like a blade, the slogan rises, and the whole layer dissolves.
class LaunchIntro extends StatefulWidget {
  final Widget child;

  const LaunchIntro({super.key, required this.child});

  /// Whole intro, fade-out included.
  static const total = Duration(milliseconds: 950);

  @override
  State<LaunchIntro> createState() => _LaunchIntroState();
}

class _LaunchIntroState extends State<LaunchIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: LaunchIntro.total,
  );
  bool _done = false;

  Animation<double> _part(double from, double to, Curve curve) =>
      CurvedAnimation(
        parent: _controller,
        curve: Interval(from, to, curve: curve),
      );

  late final _mark = _part(0, 0.32, MglaMotion.cut);
  late final _blade = _part(0.12, 0.46, MglaMotion.cut);
  late final _slogan = _part(0.24, 0.56, MglaMotion.cut);
  late final _leave = _part(0.72, 1, MglaMotion.cutOut);

  @override
  void initState() {
    super.initState();
    _controller.forward().whenComplete(() {
      if (mounted) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Animations turned off in the system settings: no intro at all, not a frozen one.
    if (_done || MediaQuery.maybeDisableAnimationsOf(context) == true) {
      return widget.child;
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        IgnorePointer(
          child: ExcludeFocus(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) => _frame(context),
            ),
          ),
        ),
      ],
    );
  }

  Widget _frame(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slogan = Localizations.of<AppLocalizations>(
      context,
      AppLocalizations,
    )?.slogan;
    return Opacity(
      opacity: 1 - _leave.value,
      child: ColoredBox(
        color: scheme.surface,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: _mark.value,
                child: Transform.scale(
                  scale: 0.9 + 0.1 * _mark.value,
                  child: Image.asset(
                    'assets/images/icon.png',
                    width: 96,
                    height: 96,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: 280,
                height: 2,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: _blade.value,
                    // a childless box is zero high in loose constraints — the line was invisible
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            scheme.primary.withValues(alpha: 0),
                            scheme.primary,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              if (slogan != null)
                Opacity(
                  opacity: _slogan.value,
                  child: Transform.translate(
                    offset: Offset(0, 10 * (1 - _slogan.value)),
                    child: Text(
                      slogan,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
