import 'package:flutter/widgets.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/components/tour_target.dart';

/// Confetti fired once when this widget appears: two cannons in the bottom
/// corners, or one small puff for a step done right, out of [from] when that
/// is on screen and from the bottom centre otherwise.
///
/// A widget rather than `Confetti.launch`, which is the package's headline API:
/// that one inserts an [OverlayEntry] into the enclosing [Navigator], so the
/// burst outlives the screen that fired it and has to be started from somewhere
/// that is not a build. Drawn declaratively instead, it begins when the end page
/// does and goes with it.
///
/// MUST be laid over the whole screen and MUST NOT sit inside a scroll view:
/// particles are positioned in their container, so a scrolling one would carry
/// them with it and clip them at its edge.
///
/// Draws nothing at all when the reader has asked for less motion. On the web
/// that is `prefers-reduced-motion: reduce`, which Flutter's engine maps onto
/// both `reduceMotion` and `disableAnimations`.
class ConfettiBurst extends StatefulWidget {

  /// A pass is celebrated many times per lesson, so it gets a fraction of what
  /// finishing the lesson gets.
  final bool small;

  /// The [TourTarget] a small burst comes out of: the Run button whose run
  /// earned it.
  final Object? from;

  const ConfettiBurst({super.key}) : small = false, from = null;

  const ConfettiBurst.small({this.from, super.key}) : small = true;

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();

}

class _ConfettiBurstState extends State<ConfettiBurst> {

  /// One per cannon. [Confetti] registers its launcher against the controller it
  /// is handed, so two of them sharing one would leave only the second armed.
  final ConfettiController _left = ConfettiController();
  final ConfettiController _right = ConfettiController();

  /// How far down the box a cannon at the bottom stands, as a fraction.
  static const double _low = 0.82;

  /// Where the small burst comes out of, as fractions of this widget's box.
  /// Null while [ConfettiBurst.from] waits to be measured against that box,
  /// which exists only once the first frame has laid it out.
  Offset? _origin;

  @override
  void initState() {
    super.initState();
    if (widget.from == null) {
      _origin = const Offset(0.5, _low);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _origin = _measure() ?? const Offset(0.5, _low));
      });
    }
  }

  /// The centre of [ConfettiBurst.from] in this box, or null when it is not on
  /// screen: a burst from past the edge would only be seen falling back in.
  Offset? _measure() {
    final target = TourTargetScope.maybeOf(context)?.rectOf(widget.from!);
    final box = context.findRenderObject();
    if (target == null || box is! RenderBox || !box.hasSize || box.size.isEmpty) return null;

    final centre = box.globalToLocal(target.center);
    if (!(Offset.zero & box.size).contains(centre)) return null;

    return Offset(centre.dx / box.size.width, centre.dy / box.size.height);
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();

    final colors = _palette(context);

    if (widget.small) {
      // The whole box while it waits, which is what [_measure] measures against.
      final origin = _origin;
      if (origin == null) return const SizedBox.expand();

      return _buildCannon(
        controller: _left,
        x: origin.dx,
        y: origin.dy,
        angle: 90,
        colors: colors,
        particleCount: 36,
        spread: 70,
        startVelocity: 40,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Fired inward and upward from either corner, low enough that the arc
        // peaks over the panel rather than over the header.
        _buildCannon(controller: _left, x: 0, angle: 60, colors: colors),
        _buildCannon(controller: _right, x: 1, angle: 120, colors: colors),
      ],
    );
  }

  Widget _buildCannon({
    required ConfettiController controller,
    required double x,
    required double angle,
    double y = _low,
    required List<Color> colors,
    int particleCount = 60,
    double spread = 62,
    double startVelocity = 52,
  }) {
    return Confetti(
      controller: controller,
      // Fires in the widget's own first frame, which is what makes appearing on
      // screen the trigger.
      instant: true,
      options: ConfettiOptions(
        colors: colors,
        particleCount: particleCount,
        angle: angle,
        spread: spread,
        startVelocity: startVelocity,
        scalar: 1.1,
        x: x,
        y: y,
      ),
    );
  }

  /// The preset's own colours, so a new colour preset gets confetti in its
  /// palette without anything here changing.
  ///
  /// Deliberately not a token of its own: these are flakes in flight, not text
  /// and not a fill behind any, so none of them needs the paired foreground or
  /// the contrast floor that every colour in [AppSemanticColors] is held to.
  ///
  /// Fills only. The ink tokens — `foreground`, and `progressCurrent`, which
  /// every preset sets to it — are near-black on the light page and read as
  /// dirt rather than as confetti. `progressComplete` is left out as well: both
  /// presets set it to the same green as `success`, so it only weights the mix.
  static List<Color> _palette(BuildContext context) {
    final colors = context.theme.colors;
    final semantic = context.appTheme.colors;

    return [colors.primary, semantic.success, semantic.warning, semantic.link];
  }

}
