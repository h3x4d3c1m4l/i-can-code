import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The app's mark: `</>` in the code face on a filled tile. Deliberately
/// language-agnostic — the app is not a Python app.
///
/// Used at 38px in the header and 118px on the initialization screen, so [size]
/// is a parameter and everything else scales off it.
class AppLogo extends StatelessWidget {

  /// The tile's width and height.
  final double size;

  const AppLogo({this.size = 38, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.primary,
          // The design's radii are a third of the tile at both sizes it uses
          // (13/38 and 40/118). Clamped, because the scaled radius would
          // otherwise deform a box this small.
          shape: squircleOf(size / 3, size: size),
        ),
        child: Center(
          child: Text(
            '</>',
            style: context.appTheme.text.code.copyWith(
              fontSize: size * 0.32,
              height: 1,
              color: theme.colors.primaryForeground,
            ),
          ),
        ),
      ),
    );
  }

}
