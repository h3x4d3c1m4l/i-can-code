import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/extensions/color_extension.dart';
import 'package:i_can_code/theme/bevel_press.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A card to open something with: a thick edge and a hard, unblurred collar
/// under it that the card rises off on hover and sinks into on press. The
/// same device as `AppButton`'s, at the scale of a card.
///
/// Without [onPress] it is drawn as a half-opacity outline and not bevelled:
/// looking pressable is exactly what it must not do then.
class BevelledCard extends StatelessWidget {

  /// The collar under the card. A list of cards SHOULD leave this much more
  /// between two of them than it means to show.
  static const double collarHeight = 6;

  /// Matters of taste, all of them.
  static const double _edgeWidth = 2.5;
  static const double _hoverLift = 2;

  /// How much darker than the `border` token the edge and the collar are, in
  /// [HSLColor] lightness. The token itself is a card's quiet outline and too
  /// faint on the cream page to read as a rim. The edge is darkened in the light
  /// scheme only.
  static const double _edgeDarken = 0.12;
  static const double _collarDarken = 0.28;

  final Widget child;

  final VoidCallback? onPress;

  const BevelledCard({required this.child, this.onPress, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    if (onPress == null) {
      return Opacity(
        opacity: 0.5,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border, width: 2)),
          ),
          child: child,
        ),
      );
    }

    // On a dark card the `border` token is already lighter than the card, so
    // darkening it would sink the edge into the fill it is meant to outline.
    final edge = theme.colors.brightness == Brightness.dark
        ? theme.colors.border
        : theme.colors.border.darken(_edgeDarken);

    return FTappable(
      style: kBevelPressStyle,
      onPress: onPress,
      semanticsButton: true,
      builder: (context, states, child) {
        final lift = switch (states) {
          _ when states.contains(FTappableVariant.pressed) => -collarHeight,
          _ when states.contains(FTappableVariant.hovered) => _hoverLift,
          _ => 0.0,
        };
        final focused = states.contains(FTappableVariant.focused);

        return TweenAnimationBuilder<double>(
          tween: Tween(end: lift),
          duration: context.motion(const Duration(milliseconds: 120)),
          curve: Curves.easeOut,
          // Moving the face up by as much as the collar grows keeps the
          // collar's own bottom edge still: the card rises off the page rather
          // than the whole thing drifting.
          builder: (context, lift, child) => Transform.translate(
            offset: Offset(0, -lift),
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.colors.card,
                shape: squircle(
                  kCardCornerRadius,
                  side: BorderSide(
                    // The only focus indication a card has, so the ink rather
                    // than a brand fill that may not clear 3:1 on the page.
                    color: focused ? theme.colors.foreground : edge,
                    width: _edgeWidth,
                  ),
                ),
                shadows: [
                  BoxShadow(
                    color: theme.colors.border.darken(_collarDarken),
                    offset: Offset(0, collarHeight + lift),
                  ),
                ],
              ),
              child: child,
            ),
          ),
          child: child,
        );
      },
      child: child,
    );
  }

}
