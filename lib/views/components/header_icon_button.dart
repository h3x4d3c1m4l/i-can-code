import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A glyph on its own in the header — the settings cog, the zen toggle.
///
/// Not an `AppButton.icon`: that one is a control in the page, padded `19 × 19`
/// so it stands beside a line of text, which is far too big for a 76px bar. This
/// one is the header's own size and carries no fill until it is hovered.
///
/// [semanticsLabel] is required for the reason `AppButton.icon`'s is: there is
/// no text in here for a screen reader to fall back on.
class HeaderIconButton extends StatelessWidget {

  /// The tile's width and height. Matches `AppLogo`'s default, so everything in
  /// the bar sits on one square grid.
  static const double size = 38;

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onPress;

  const HeaderIconButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered) ? theme.colors.secondary : const Color(0x00000000),
          shape: squircleOf(kChipCornerRadius, size: size),
        ),
        child: Padding(padding: const EdgeInsets.all(9), child: child),
      ),
      child: Icon(icon, size: 20, color: theme.colors.foreground),
    );
  }

}
