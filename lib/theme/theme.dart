import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/color_extension.dart';
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

  final style = FStyle.inherit(colors: colors, typography: typography, touch: _touch).copyWith(
    borderRadius: kBorderRadius,
    tappableStyle: _clickCursor,
  );

  // forui insets an item from the group's edge by `spacing` above the first and
  // below the last, and by an item padding of the same 4 at the sides.
  final menu = FPopoverMenuStyle.inherit(
    colors: colors,
    style: style,
    typography: typography,
    hapticFeedback: const FHapticFeedback(),
    touch: _touch,
  );

  return FThemeData(
    touch: _touch,
    debugLabel: '${preset.name} ${brightness.name}',
    colors: colors,
    typography: typography,
    style: style,
    dialogStyle: FDialogStyle.inherit(
      colors: colors,
      typography: typography,
      style: style,
      hapticFeedback: const FHapticFeedback(),
      touch: _touch,
    ).copyWith(
      // The bevel `CatalogCard` wears, standing still: a dialog is not pressed.
      decoration: DecorationDelta.shapeDelta(
        shape: squircle(
          kHeroTileCornerRadius,
          side: BorderSide(
            // On a dark card the `border` token is already lighter than the
            // card, so darkening it would sink the edge into the fill.
            color: brightness == Brightness.dark ? colors.border : colors.border.darken(_dialogEdgeDarken),
            width: _dialogEdgeWidth,
          ),
        ),
        shadows: [
          BoxShadow(color: colors.border.darken(_dialogCollarDarken), offset: const Offset(0, _dialogCollarHeight)),
        ],
      ),
    ),
    // forui shapes its surfaces with a `RoundedSuperellipseBorder` of its own,
    // which is a different curve from the app's, so each layer is reshaped:
    // the panel, the item group drawn on top of it, and an item's hover fill.
    popoverStyle: FPopoverStyle.inherit(colors: colors, style: style).copyWith(
      decoration: DecorationDelta.shapeDelta(shape: squircle(_hintCornerRadius, side: _surfaceEdge(colors, style))),
    ),
    tooltipStyle: FTooltipStyle.inherit(
      colors: colors,
      typography: typography,
      style: style,
      hapticFeedback: const FHapticFeedback(),
    ).copyWith(decoration: DecorationDelta.shapeDelta(shape: squircle(_tipCornerRadius))),
    popoverMenuStyle: menu.copyWith(
          decoration: DecorationDelta.shapeDelta(
            shape: squircle(kControlCornerRadius, side: _surfaceEdge(colors, style)),
          ),
          itemGroupStyle: FItemGroupStyleDelta.delta(
            // The same shape as the panel, so the two edges lie on each other.
            decoration: DecorationDelta.shapeDelta(
              shape: squircle(kControlCornerRadius, side: _surfaceEdge(colors, style)),
            ),
            itemStyles: FVariantsDelta.delta([
              FVariantOperation.all(
                FItemStyleDelta.delta(
                  contentDecoration: FVariantsDelta.delta([
                    // Inside the panel's corner, so the two curves run parallel
                    // rather than meeting at the ends of a gap that varies.
                    FVariantOperation.all(
                      DecorationDelta.shapeDelta(
                        shape: squircle(concentricRadius(kControlCornerRadius, inset: menu.itemGroupStyle.spacing)),
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
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

/// A popover that only explains something. A control's radius would bow one
/// line of text inward.
const double _hintCornerRadius = kChipCornerRadius;

/// A tooltip's corner. Tighter than a hint's: one line of a tip is under 30px
/// tall, and a squircle bows inward past half the shortest side.
const double _tipCornerRadius = 8;

/// The quiet outline forui gives its floating surfaces.
BorderSide _surfaceEdge(FColors colors, FStyle style) => BorderSide(color: colors.border, width: style.borderWidth);

/// The dialog's bevel, in the same numbers as `CatalogCard`'s so the two read
/// as one material.
const double _dialogEdgeWidth = 2.5;
const double _dialogCollarHeight = 6;
const double _dialogEdgeDarken = 0.12;
const double _dialogCollarDarken = 0.28;

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
