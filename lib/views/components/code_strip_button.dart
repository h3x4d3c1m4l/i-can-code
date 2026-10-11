import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A glyph in the strip over a code card: the editor's reset, a sample's copy.
///
/// Drawn in the code palette, which is dark in every preset, and sized for
/// that strip. [semanticsLabel] is required because there is no text in here
/// for a screen reader to fall back on.
class CodeStripButton extends StatelessWidget {

  static const double _size = 18;

  final IconData icon;
  final String semanticsLabel;
  final VoidCallback onPress;

  const CodeStripButton({
    required this.icon,
    required this.semanticsLabel,
    required this.onPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? colors.codeForeground.withValues(alpha: 0.12)
              : const Color(0x00000000),
          shape: squircleOf(kChipCornerRadius, size: _size + 8),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      ),
      child: Icon(icon, size: _size, color: colors.codeMuted),
    );
  }

}
