import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The app's forui theme in [preset]'s colours at [brightness]. Only colour
/// comes from the preset; the type scale, fonts and radii are shared by all of
/// them, and do not change with the mode either.
FThemeData buildAppTheme({
  AppColorPreset preset = AppColorPreset.neutral,
  Brightness brightness = Brightness.light,
}) {
  final resolved = preset.resolve(brightness: brightness);
  final colors = resolved.colors;

  // forui carries exactly two typefaces: `display` for headings, `body` for the
  // rest. Both fall back to the emoji face, so forui's own widgets — a button
  // label, a breadcrumb — draw an emoji the same way `AppTextStyles` does.
  final typography = FTypography(
    display: FTypeface.inherit(
      colors: colors,
      touch: _touch,
      fontFamily: kDisplayFontFamily,
      fontFamilyFallback: kEmojiFontFallback,
    ),
    body: FTypeface.inherit(
      colors: colors,
      touch: _touch,
      fontFamily: kBodyFontFamily,
      fontFamilyFallback: kEmojiFontFallback,
    ),
  );

  return FThemeData(
    touch: _touch,
    debugLabel: '${preset.name} ${brightness.name}',
    colors: colors,
    typography: typography,
    style: FStyle.inherit(colors: colors, typography: typography, touch: _touch).copyWith(
      borderRadius: kBorderRadius,
      tappableStyle: _clickCursor,
    ),
    // **Both** places, and they are not the same object.
    //
    // A bare `FTappable` reads `FThemeData.tappableStyle` — the top-level field
    // right here — while a forui widget built from `FStyle` reads the one on the
    // style above. Setting only the style leaves every plain `FTappable` (the
    // progress bar's segments, `AppButton`) on forui's `MouseCursor.defer`,
    // which on the web is the ordinary arrow. `FThemeData` defaults this field
    // to a bare `FTappableStyle()` rather than deriving it from the style, so
    // nothing carries one to the other.
    tappableStyle: _clickCursor(FTappableStyle()),
    extensions: [AppTheme.of(preset, brightness)],
  );
}

/// A pointer over anything tappable, and the plain arrow when it is disabled.
///
/// forui defaults every tappable to `MouseCursor.defer`, which leaves the arrow
/// over buttons, breadcrumb crumbs, the settings cog and the progress bar.
final FTappableStyleDelta _clickCursor = FTappableStyleDelta.delta(
  cursor: FVariantsValueDelta.delta([
    FVariantValueDeltaOperation.base(SystemMouseCursors.click),
    // A disabled control is not clickable.
    FVariantValueDeltaOperation.exact({FTappableVariantConstraint.disabled}, SystemMouseCursors.basic),
  ]),
);

/// forui sizes its widgets for a finger when set. The app is mouse-driven.
const bool _touch = false;
