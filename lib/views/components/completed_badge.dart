import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The mark on a finished row: a tick knocked out of a lit badge, rather than
/// drawn as a bare stroke, so it reads as a mark that was *awarded*.
///
/// **Every number this draws is a constant at the top of the class.** They are
/// meant to be turned — the look is a matter of taste, and nothing else in the
/// app reads them.
///
/// A circle, and the one shape in the app that is not a squircle. The squircle
/// rule is about corners; this is a lamp, and the shape says so. A flat disc,
/// with no outline: a ring around it was tried and read as a second shape
/// rather than as a crisper edge.
///
/// The glow is a stack of shadows rather than one, all at zero offset: a tight
/// core, a halo and a wide bloom. **One shadow cannot do this.** A small blur
/// reads as a ring drawn around the badge and a large one thins the colour
/// until it disappears — against the dark card especially, where a translucent
/// green barely lifts the surface it is over. Stacking them is what makes the
/// falloff look like light.
///
/// It is not the neobrutalist hard offset shadow the preset deliberately leaves
/// out. That one is a device of the whole style and would belong in the shared
/// metrics; this is one lamp under one mark, lit by whatever green the preset
/// completes a step in.
class CompletedBadge extends StatelessWidget {

  // ---------------------------------------------------------------- tuning

  /// The badge's diameter. Small enough to sit on the same line as the step
  /// count it replaces, without moving a catalog row's height.
  static const double size = 28;

  /// The tick inside it, drawn in `progressCompleteForeground`.
  static const double iconSize = 16;

  /// The glow, tightest layer first. Each is the badge's own colour at [alpha],
  /// blurred by [blur] and inflated by [spread], drawn at no offset.
  ///
  /// Raising every [alpha] together makes it brighter; raising the outer
  /// [blur]s spreads the bloom. The dark card is the one to check after a
  /// change — a translucent green over a dark surface is where a glow is
  /// hardest to see.
  static const List<({double alpha, double blur, double spread})> glow = [
    (alpha: 0.75, blur: 6, spread: 0),
    (alpha: 0.6, blur: 16, spread: 1),
    (alpha: 0.4, blur: 32, spread: 3),
  ];

  // ------------------------------------------------------------------------

  const CompletedBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final complete = context.appTheme.colors.progressComplete;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: complete,
          shape: const CircleBorder(),
          shadows: [
            for (final layer in glow)
              BoxShadow(
                color: complete.withValues(alpha: layer.alpha),
                blurRadius: layer.blur,
                spreadRadius: layer.spread,
              ),
          ],
        ),
        child: Center(
          // Whatever the preset pairs with its own green — white on the light
          // page, ink on the dark one. See `progressCompleteForeground`.
          child: Icon(
            FLucideIcons.check,
            size: iconSize,
            color: context.appTheme.colors.progressCompleteForeground,
          ),
        ),
      ),
    );
  }

}
