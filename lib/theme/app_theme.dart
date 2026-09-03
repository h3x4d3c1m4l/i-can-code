import 'package:flutter/widgets.dart';

import 'package:forui/forui.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:material_ui/material_ui.dart' show ThemeExtension;
import 'package:theme_tailor_annotation/theme_tailor_annotation.dart';

part 'app_theme.tailor.dart';

/// Caches the fallback tokens per [FThemeData], so a subtree built without an
/// [AppTheme] doesn't rebuild them on every build.
final Expando<AppTheme> _fallbackCache = Expando<AppTheme>('AppTheme fallback');

/// The heading face. Bundled under `assets/fonts/`, not fetched at runtime.
/// Shared by every colour preset; only colour is presettable.
const String kDisplayFontFamily = 'Figtree';

/// The body face.
const String kBodyFontFamily = 'Inter';

/// The code face.
const String kCodeFontFamily = 'JetBrains Mono';

/// The emoji face, bundled like the other three.
///
/// It is never a `fontFamily`, only ever the last entry of a
/// [TextStyle.fontFamilyFallback]: the three faces above carry no emoji, so a
/// glyph reaches this one only when none of them can draw it.
///
/// Bundling it is what makes an emoji look the same everywhere. Left to the
/// platform, the same lesson would show Apple's emoji on a Mac or an iPhone,
/// Google's on Android, and Microsoft's on Windows — and on the web the engine
/// would fetch Noto from `fonts.gstatic.com` per student, which is the request
/// the other three fonts were bundled to avoid.
const String kEmojiFontFamily = 'Noto Color Emoji';

/// Every style in [AppTextStyles] ends here, so an emoji renders the same in a
/// heading, in prose and in the code editor.
const List<String> kEmojiFontFallback = [kEmojiFontFamily];

extension AppThemeContext on BuildContext {

  /// The app's design tokens for this subtree, falling back to the neutral
  /// preset when the ambient theme carries no [AppTheme].
  ///
  /// Reads [FThemeData.extensions] rather than `FThemeData.extension`, which
  /// throws on a theme that has none.
  AppTheme get appTheme {
    final theme = this.theme;
    final extensions = theme.extensions.whereType<AppTheme>();
    if (extensions.isNotEmpty) return extensions.first;

    // The theme still knows its own brightness, so the fallback can at least
    // match it rather than forcing a light scheme onto a dark one.
    return _fallbackCache[theme] ??= AppTheme.of(AppColorPreset.neutral, theme.colors.brightness);
  }

}

/// The app's own design tokens — the roles forui's [FColors] and [FTypography]
/// have no slot for. Read with `context.appTheme`.
///
/// Carried on [FThemeData.extensions]. The [ThemeExtension] base class MUST come
/// from `package:material_ui`, which is what forui types that map against;
/// `package:flutter/material.dart` declares a different one.
@TailorMixin(themeGetter: ThemeGetter.none)
class AppTheme extends ThemeExtension<AppTheme> with _$AppThemeTailorMixin {

  const AppTheme({required this.colors, required this.text});

  factory AppTheme.of(AppColorPreset preset, [Brightness brightness = Brightness.light]) {
    final resolved = preset.resolve(brightness: brightness);
    return AppTheme(colors: resolved.semantic, text: AppTextStyles.of(resolved.colors.foreground));
  }

  @override
  final AppSemanticColors colors;

  @override
  final AppTextStyles text;

}

/// Colours that carry a meaning rather than a place, in whichever
/// [AppColorPreset] is in force.
///
/// Each `*Foreground` is stated next to its fill: some presets have a fill that
/// cannot take white text, so callers MUST NOT pick a foreground themselves.
@TailorMixinComponent()
class AppSemanticColors extends ThemeExtension<AppSemanticColors> with _$AppSemanticColorsTailorMixin {

  const AppSemanticColors({
    required this.success,
    required this.successForeground,
    required this.successSurface,
    required this.warning,
    required this.warningForeground,
    required this.warningSurface,
    required this.errorSurface,
    required this.link,
    required this.codeBackground,
    required this.codeForeground,
    required this.codeMuted,
    required this.progressTrack,
    required this.progressComplete,
    required this.progressCompleteForeground,
    required this.progressCurrent,
  });

  /// A passed assignment.
  @override
  final Color success;

  /// Text and glyphs drawn on top of [success]. Not always white — see the
  /// class doc.
  @override
  final Color successForeground;

  /// The quiet fill behind a "Goed!" message.
  @override
  final Color successSurface;

  /// A check that did not pass yet, and the hint block. Distinct from forui's
  /// `error`, which means "this input is invalid".
  @override
  final Color warning;

  /// Text on top of [warning].
  @override
  final Color warningForeground;

  /// The quiet fill behind a "Nog niet" message.
  @override
  final Color warningSurface;

  /// The quiet fill behind an error message. Its foreground is forui's
  /// `errorForeground`; only the surface is missing there.
  @override
  final Color errorSurface;

  /// A link in a lesson's prose.
  ///
  /// **Not `primary`**, which is a fill: a preset is free to make it a colour
  /// that cannot carry text, and the neutral preset's accent is exactly that at
  /// 1.2:1 on the page. A link MUST clear AA on both the page and a card, so it
  /// is a role of its own.
  @override
  final Color link;

  /// The dark card the code editor and the sample snippets are drawn on.
  @override
  final Color codeBackground;

  /// Code drawn on [codeBackground].
  @override
  final Color codeForeground;

  /// The editor chrome — the `main.py` label and the runtime status.
  @override
  final Color codeMuted;

  /// A lesson step not reached yet.
  @override
  final Color progressTrack;

  /// A lesson step already completed.
  @override
  final Color progressComplete;

  /// The tick drawn on top of [progressComplete], where it is a fill rather
  /// than a bar — the badge on a finished row in the catalog.
  ///
  /// Stated here rather than picked at the call site for the reason the class
  /// doc gives: the greens both presets complete a step with are light enough
  /// that white fails on them — 1.67:1 on the neutral preset's, under even the
  /// 3:1 floor for graphics — so a widget reaching for the obvious white tick
  /// would be drawing an illegible one. Ink, and it was tried the other way.
  @override
  final Color progressCompleteForeground;

  /// The step being worked on now.
  @override
  final Color progressCurrent;

}

/// The type scale, transcribed from the design canvas. Shared by every preset;
/// only the text colour varies.
///
/// The canvas states tracking in `em`, which [TextStyle.letterSpacing] has no
/// equivalent for, so each value below is the `em` figure multiplied by that
/// style's own font size.
@TailorMixinComponent()
class AppTextStyles extends ThemeExtension<AppTextStyles> with _$AppTextStylesTailorMixin {

  const AppTextStyles({
    required this.display,
    required this.h1,
    required this.h2,
    required this.h3,
    required this.body,
    required this.bodySmall,
    required this.label,
    required this.code,
    required this.codeSmall,
  });

  /// The scale in [foreground], the preset's own text colour.
  ///
  /// Colour is baked in because these go straight to [Text.style], and a
  /// [TextStyle] without one falls back to the ambient [DefaultTextStyle].
  AppTextStyles.of(Color foreground)
    : this(
        display: TextStyle(
          fontFamily: kDisplayFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 58,
          fontWeight: FontWeight.w800,
          letterSpacing: 58 * -0.04,
          height: 1,
        ),
        h1: TextStyle(
          fontFamily: kDisplayFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 46,
          fontWeight: FontWeight.w800,
          letterSpacing: 46 * -0.035,
          height: 1.05,
        ),
        h2: TextStyle(
          fontFamily: kDisplayFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 34,
          fontWeight: FontWeight.w800,
          letterSpacing: 34 * -0.03,
          height: 1.12,
        ),
        h3: TextStyle(
          fontFamily: kDisplayFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 26,
          fontWeight: FontWeight.w700,
          letterSpacing: 26 * -0.02,
          height: 1.2,
        ),
        body: TextStyle(
          fontFamily: kBodyFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 21,
          height: 1.65,
        ),
        bodySmall: TextStyle(
          fontFamily: kBodyFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 19,
          height: 1.6,
        ),
        label: TextStyle(
          fontFamily: kBodyFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          color: foreground,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 13 * 0.1,
        ),
        code: const TextStyle(
          fontFamily: kCodeFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          fontSize: 16,
          height: 1.8,
        ),
        codeSmall: const TextStyle(
          fontFamily: kCodeFontFamily,
          fontFamilyFallback: kEmojiFontFallback,
          fontSize: 12,
          height: 1.4,
        ),
      );

  /// The one-word screens: "Leer Python" on login, "Klaar!" on completion.
  @override
  final TextStyle display;

  /// A screen title: the catalog heading, a lesson step's title.
  @override
  final TextStyle h1;

  /// An assignment's title, in the narrower left column of the task screen.
  @override
  final TextStyle h2;

  /// A course card's title in the catalog.
  @override
  final TextStyle h3;

  /// Lesson prose on a full-width text step.
  @override
  final TextStyle body;

  /// Lesson prose in the task screen's left column, where the measure is
  /// narrower.
  @override
  final TextStyle bodySmall;

  /// An uppercase eyebrow: the "Opdracht" chip, the "Uitvoer" panel heading.
  /// Callers MUST uppercase the string themselves; this style only sets the
  /// weight and tracking that make uppercase readable.
  @override
  final TextStyle label;

  /// Code, in the editor and in a sample block. Carries no colour — it is drawn
  /// on both dark and light surfaces, so the caller supplies the foreground.
  @override
  final TextStyle code;

  /// The editor's chrome — the `main.py` filename and the runtime status.
  @override
  final TextStyle codeSmall;

}
