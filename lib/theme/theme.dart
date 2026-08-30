import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The app's forui theme in [preset]'s colours. Only colour comes from the
/// preset; the type scale, fonts and radii are shared by all of them.
FThemeData buildAppTheme({AppColorPreset preset = AppColorPreset.neutral}) {
  final resolved = preset.resolve();
  final colors = resolved.colors;

  // forui carries exactly two typefaces: `display` for headings, `body` for the
  // rest.
  final typography = FTypography(
    display: FTypeface.inherit(colors: colors, touch: _touch, fontFamily: kDisplayFontFamily),
    body: FTypeface.inherit(colors: colors, touch: _touch, fontFamily: kBodyFontFamily),
  );

  return FThemeData(
    touch: _touch,
    debugLabel: '${preset.name} light',
    colors: colors,
    typography: typography,
    style: FStyle.inherit(colors: colors, typography: typography, touch: _touch).copyWith(
      borderRadius: kBorderRadius,
      // forui defaults every tappable's cursor to `MouseCursor.defer`, which on
      // the web leaves the ordinary arrow over every button. Every widget style
      // inherits this one, so setting it here covers them all.
      tappableStyle: FTappableStyleDelta.delta(
        cursor: FVariantsValueDelta.delta([
          FVariantValueDeltaOperation.base(SystemMouseCursors.click),
          // A disabled control is not clickable.
          FVariantValueDeltaOperation.exact({FTappableVariantConstraint.disabled}, SystemMouseCursors.basic),
        ]),
      ),
    ),
    extensions: [AppTheme.of(preset)],
  );
}

/// forui sizes its widgets for a finger when set. The app is mouse-driven.
const bool _touch = false;
