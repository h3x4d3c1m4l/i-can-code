import 'package:flutter/services.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/presets/neobrutalism_palette.dart';
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

  /// Unbranded, and the default. Neobrutalism **as a palette**: see
  /// [NeobrutalismPalette] for what that does and does not mean.
  neutral,

  /// De Haagse Hogeschool's house style. A skin; see [ThuasPalette].
  thuas;

  /// This preset's tokens in [brightness].
  ///
  /// The default keeps every caller that predates dark mode working; the app
  /// shell always passes one explicitly.
  AppColorPresetData resolve({Brightness brightness = Brightness.light}) => switch ((this, brightness)) {
    (AppColorPreset.neutral, Brightness.light) => _neutralLight(),
    (AppColorPreset.neutral, Brightness.dark) => _neutralDark(),
    (AppColorPreset.thuas, Brightness.light) => _thuasLight(),
    (AppColorPreset.thuas, Brightness.dark) => _thuasDark(),
  };

}

AppColorPresetData _neutralLight() {
  return AppColorPresetData(
    colors: FColors(
      brightness: Brightness.light,
      systemOverlayStyle: SystemUiOverlayStyle.dark,
      barrier: const Color(0x66000000),
      background: NeobrutalismPalette.pageLight,
      foreground: NeobrutalismPalette.inkLight,
      primary: NeobrutalismPalette.accent,
      // The accent is a fill and cannot carry light text; see its own doc.
      primaryForeground: NeobrutalismPalette.inkLight,
      secondary: NeobrutalismPalette.secondaryLight,
      secondaryForeground: NeobrutalismPalette.inkLight,
      muted: NeobrutalismPalette.mutedLight,
      mutedForeground: NeobrutalismPalette.inkMutedLight,
      destructive: NeobrutalismPalette.dangerLight,
      destructiveForeground: _white,
      error: NeobrutalismPalette.dangerLight,
      errorForeground: _white,
      card: NeobrutalismPalette.cardLight,
      border: NeobrutalismPalette.borderLight,
    ),
    semantic: const AppSemanticColors(
      success: NeobrutalismPalette.successLight,
      successForeground: NeobrutalismPalette.inkLight,
      successSurface: NeobrutalismPalette.successSurfaceLight,
      warning: NeobrutalismPalette.warningLight,
      warningForeground: NeobrutalismPalette.inkLight,
      warningSurface: NeobrutalismPalette.warningSurfaceLight,
      errorSurface: NeobrutalismPalette.errorSurfaceLight,
      link: NeobrutalismPalette.linkLight,
      neutralButton: NeobrutalismPalette.controlLight,
      neutralButtonForeground: NeobrutalismPalette.pageLight,
      codeBackground: NeobrutalismPalette.codeSurface,
      codeForeground: NeobrutalismPalette.codeInk,
      codeMuted: NeobrutalismPalette.codeInkMuted,
      progressTrack: NeobrutalismPalette.borderLight,
      progressComplete: NeobrutalismPalette.complete,
      progressCompleteForeground: NeobrutalismPalette.inkLight,
      progressCurrent: NeobrutalismPalette.inkLight,
    ),
  );
}

AppColorPresetData _neutralDark() {
  return AppColorPresetData(
    colors: FColors(
      brightness: Brightness.dark,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      barrier: const Color(0x99000000),
      background: NeobrutalismPalette.pageDark,
      foreground: NeobrutalismPalette.inkDark,
      // The accent does not change with the mode: it is the app's one loud
      // colour, and dimming it for dark would be the point of it lost.
      primary: NeobrutalismPalette.accent,
      primaryForeground: NeobrutalismPalette.inkLight,
      secondary: NeobrutalismPalette.secondaryDark,
      secondaryForeground: NeobrutalismPalette.inkDark,
      muted: NeobrutalismPalette.mutedDark,
      mutedForeground: NeobrutalismPalette.inkMutedDark,
      destructive: NeobrutalismPalette.dangerDark,
      // 7.95:1. White would be 1.6:1 and fail.
      destructiveForeground: NeobrutalismPalette.inkLight,
      error: NeobrutalismPalette.dangerDark,
      errorForeground: NeobrutalismPalette.inkLight,
      card: NeobrutalismPalette.cardDark,
      border: NeobrutalismPalette.borderDark,
    ),
    semantic: const AppSemanticColors(
      success: NeobrutalismPalette.successDark,
      successForeground: NeobrutalismPalette.inkLight,
      successSurface: NeobrutalismPalette.successSurfaceDark,
      warning: NeobrutalismPalette.warningLight,
      warningForeground: NeobrutalismPalette.inkLight,
      warningSurface: NeobrutalismPalette.warningSurfaceDark,
      errorSurface: NeobrutalismPalette.errorSurfaceDark,
      link: NeobrutalismPalette.linkDark,
      neutralButton: NeobrutalismPalette.inkDark,
      neutralButtonForeground: NeobrutalismPalette.pageDark,
      codeBackground: NeobrutalismPalette.codeSurface,
      codeForeground: NeobrutalismPalette.codeInk,
      codeMuted: NeobrutalismPalette.codeInkMuted,
      progressTrack: NeobrutalismPalette.borderDark,
      progressComplete: NeobrutalismPalette.complete,
      progressCompleteForeground: NeobrutalismPalette.inkLight,
      progressCurrent: NeobrutalismPalette.inkDark,
    ),
  );
}

AppColorPresetData _thuasLight() {
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
      // The house style has no colour that works as link text on white: the
      // green reaches 2.88:1 even at its darkest handbook variant, the cyan
      // 2.55:1, and the red means "error". So a link is the mid grey (6.27:1),
      // set apart from the body text by weight of colour and by the underline
      // the prose sheet gives every link.
      link: ThuasPalette.greyMid,
      neutralButton: ThuasPalette.corporateGrey,
      neutralButtonForeground: ThuasPalette.grey05,
      codeBackground: ThuasPalette.corporateGrey,
      codeForeground: ThuasPalette.grey08,
      codeMuted: ThuasPalette.greyOn55,
      progressTrack: ThuasPalette.grey15,
      progressComplete: ThuasPalette.corporateGreen,
      progressCompleteForeground: ThuasPalette.corporateGrey,
      progressCurrent: ThuasPalette.corporateGrey,
    ),
  );
}

AppColorPresetData _thuasDark() {
  return AppColorPresetData(
    colors: FColors(
      brightness: Brightness.dark,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      barrier: const Color(0x99000000),
      // The house style's own dark surface becomes the page, and the handbook's
      // darker grey the card above it.
      background: ThuasPalette.corporateGrey,
      foreground: ThuasPalette.grey08,
      primary: ThuasPalette.corporateGreen,
      // Unchanged from light: 4.92:1, and the green cannot take a light
      // foreground in either mode.
      primaryForeground: ThuasPalette.corporateGrey,
      secondary: ThuasPalette.greyMid,
      secondaryForeground: ThuasPalette.grey08,
      muted: ThuasPalette.greyDark,
      // 4.81:1 on the card, which is the tighter of the two surfaces.
      mutedForeground: ThuasPalette.greyOn65,
      destructive: ThuasPalette.redTint50,
      // 6.10:1. The dark scheme's red is a light tint, so its foreground flips.
      destructiveForeground: ThuasPalette.corporateGrey,
      error: ThuasPalette.redTint50,
      errorForeground: ThuasPalette.corporateGrey,
      card: ThuasPalette.greyDark,
      border: ThuasPalette.greyMid,
    ),
    semantic: const AppSemanticColors(
      success: ThuasPalette.corporateGreen,
      successForeground: ThuasPalette.corporateGrey,
      successSurface: ThuasPalette.greenSurfaceDark,
      warning: ThuasPalette.yellow,
      warningForeground: ThuasPalette.corporateGrey,
      warningSurface: ThuasPalette.yellowSurfaceDark,
      errorSurface: ThuasPalette.redSurfaceDark,
      link: ThuasPalette.greenTint60,
      neutralButton: ThuasPalette.grey08,
      neutralButtonForeground: ThuasPalette.corporateGrey,
      codeBackground: ThuasPalette.greyDeep,
      codeForeground: ThuasPalette.grey08,
      codeMuted: ThuasPalette.greyOn55,
      progressTrack: ThuasPalette.greyMid,
      progressComplete: ThuasPalette.corporateGreen,
      progressCompleteForeground: ThuasPalette.corporateGrey,
      progressCurrent: ThuasPalette.grey08,
    ),
  );
}
