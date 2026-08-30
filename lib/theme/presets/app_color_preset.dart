import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/presets/thuas_palette.dart';

/// White, named because a preset asks for it in several slots.
const Color _white = Color(0xFFFFFFFF);

/// A colour preset: forui's own tokens plus this app's. The two travel together
/// because they have to agree on foregrounds.
class AppColorPresetData {

  final FColors colors;
  final AppSemanticColors semantic;

  const AppColorPresetData({required this.colors, required this.semantic});

}

/// The colour schemes the app ships with.
///
/// A preset changes colour only — the type scale, the fonts and the radii are
/// the app's own and are shared. Adding one means adding a case to [resolve].
enum AppColorPreset {

  /// Unbranded. forui's own neutral tokens, with the page tinted off white so
  /// that white cards read against it.
  neutral,

  /// De Haagse Hogeschool's house style. A skin; see [ThuasPalette].
  thuas;

  /// This preset's tokens.
  AppColorPresetData resolve() => switch (this) {
    AppColorPreset.neutral => _neutral(),
    AppColorPreset.thuas => _thuas(),
  };

}

AppColorPresetData _neutral() {
  const Color foreground = Color(0xFF0A0A0A);

  return AppColorPresetData(
    // forui's neutral scheme paints the page white, which leaves a white card
    // invisible on it.
    colors: FColors.neutralLight.copyWith(background: const Color(0xFFFAFAFA)),
    semantic: const AppSemanticColors(
      success: Color(0xFF166534),
      successForeground: _white,
      successSurface: Color(0xFFDCFCE7),
      warning: Color(0xFFB45309),
      warningForeground: _white,
      warningSurface: Color(0xFFFEF3C7),
      errorSurface: Color(0xFFFEE2E2),
      codeBackground: Color(0xFF171717),
      codeForeground: Color(0xFFF5F5F5),
      codeMuted: Color(0xFFA3A3A3),
      progressTrack: Color(0xFFE5E5E5),
      progressComplete: Color(0xFF166534),
      progressCurrent: foreground,
    ),
  );
}

AppColorPresetData _thuas() {
  return AppColorPresetData(
    colors: FColors(
      brightness: Brightness.light,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      barrier: ThuasPalette.corporateGrey.withValues(alpha: 0.6),
      background: ThuasPalette.grey05,
      foreground: ThuasPalette.corporateGrey,
      primary: ThuasPalette.corporateGreen,
      // 4.92:1. White would be 2.63:1 and fail.
      primaryForeground: ThuasPalette.corporateGrey,
      secondary: ThuasPalette.grey10,
      secondaryForeground: ThuasPalette.corporateGrey,
      muted: ThuasPalette.grey08,
      // 5.07:1 on white — the quietest grey tint that still clears AA.
      mutedForeground: ThuasPalette.grey70,
      destructive: ThuasPalette.red,
      destructiveForeground: _white,
      error: ThuasPalette.red,
      errorForeground: _white,
      card: _white,
      border: ThuasPalette.grey15,
    ),
    semantic: const AppSemanticColors(
      // The corporate green doubles as the success colour: the house style has
      // no second green.
      success: ThuasPalette.corporateGreen,
      successForeground: ThuasPalette.corporateGrey,
      successSurface: ThuasPalette.greenSurface,
      warning: ThuasPalette.yellow,
      warningForeground: ThuasPalette.corporateGrey,
      warningSurface: ThuasPalette.yellowSurface,
      errorSurface: ThuasPalette.redSurface,
      codeBackground: ThuasPalette.corporateGrey,
      codeForeground: ThuasPalette.grey08,
      codeMuted: ThuasPalette.greyOn55,
      progressTrack: ThuasPalette.grey15,
      progressComplete: ThuasPalette.corporateGreen,
      progressCurrent: ThuasPalette.corporateGrey,
    ),
  );
}
