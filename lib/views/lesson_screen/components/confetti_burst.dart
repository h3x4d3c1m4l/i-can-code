import 'package:flutter/widgets.dart';
import 'package:flutter_confetti/flutter_confetti.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// Two cannons in the bottom corners, fired once when this widget appears.
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

  const ConfettiBurst({super.key});

  @override
  State<ConfettiBurst> createState() => _ConfettiBurstState();

}

class _ConfettiBurstState extends State<ConfettiBurst> {

  /// One per cannon. [Confetti] registers its launcher against the controller it
  /// is handed, so two of them sharing one would leave only the second armed.
  final ConfettiController _left = ConfettiController();
  final ConfettiController _right = ConfettiController();

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return const SizedBox.shrink();

    final colors = _palette(context);

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
    required List<Color> colors,
  }) {
    return Confetti(
      controller: controller,
      // Fires in the widget's own first frame, which is what makes appearing on
      // screen the trigger.
      instant: true,
      options: ConfettiOptions(
        colors: colors,
        particleCount: 60,
        angle: angle,
        spread: 62,
        startVelocity: 52,
        scalar: 1.1,
        x: x,
        y: 0.82,
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
