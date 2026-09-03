import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/presets/thuas_palette.dart';
import 'package:i_can_code/theme/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final preset in AppColorPreset.values) {
    for (final brightness in Brightness.values) {
      group('${preset.name} ${brightness.name}', () {
        final resolved = preset.resolve(brightness: brightness);
        final colors = resolved.colors;
        final semantic = resolved.semantic;

        test('builds a theme', () {
          expect(buildAppTheme(preset: preset, brightness: brightness).colors.primary, colors.primary);
        });

        test('is the brightness it was asked for', () {
          expect(buildAppTheme(preset: preset, brightness: brightness).colors.brightness, brightness);
        });

        test('carries its own tokens on the theme', () {
          expect(buildAppTheme(preset: preset, brightness: brightness).extensions, isNotEmpty);
        });

        // Every pair a widget could plausibly get backwards. The THUAS corporate
        // green looks bright enough to take white text, and does not.
        final pairs = <String, (Color, Color)>{
          'primary on its foreground': (colors.primary, colors.primaryForeground),
          'destructive on its foreground': (colors.destructive, colors.destructiveForeground),
          'error on its foreground': (colors.error, colors.errorForeground),
          'body text on the page': (colors.background, colors.foreground),
          'body text on a card': (colors.card, colors.foreground),
          'muted text on the page': (colors.background, colors.mutedForeground),
          'success on its foreground': (semantic.success, semantic.successForeground),
          // The tick on a finished catalog row. Every preset completes a step
          // in a green light enough that white fails on it, which is why it has
          // a foreground of its own rather than the obvious one.
          'the completed tick on its badge': (semantic.progressComplete, semantic.progressCompleteForeground),
          'warning on its foreground': (semantic.warning, semantic.warningForeground),
          'text on the success surface': (semantic.successSurface, colors.foreground),
          'text on the warning surface': (semantic.warningSurface, colors.foreground),
          'text on the error surface': (semantic.errorSurface, colors.foreground),
          // The "Verdieping" badge is filled with `secondary` and labelled in
          // `secondaryForeground`.
          'the optional-step badge on its foreground': (colors.secondary, colors.secondaryForeground),
          'code on the editor': (semantic.codeBackground, semantic.codeForeground),
          'editor chrome on the editor': (semantic.codeBackground, semantic.codeMuted),
          // A prose link is text, so it has to clear both surfaces it is drawn
          // on. This is the pair `primary` cannot satisfy, and the reason `link`
          // is a role of its own.
          'a link on the page': (colors.background, semantic.link),
          'a link on a card': (colors.card, semantic.link),
        };

        for (final MapEntry(key: name, value: pair) in pairs.entries) {
          test('$name clears WCAG AA', () => expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5)));
        }
      });
    }
  }

  // Both fields, because they are different objects and only one of them is
  // what a bare `FTappable` reads. Asserting the style alone passed for a
  // release in which every cursor on the site was still forui's arrow.
  for (final (name, style) in [
    ('a bare FTappable reads', buildAppTheme().tappableStyle),
    ('a widget built from FStyle reads', buildAppTheme().style.tappableStyle),
  ]) {
    test('the cursor $name is a pointer, and an arrow when disabled', () {
      // forui defaults both to `MouseCursor.defer`, which on the web leaves the
      // ordinary arrow over buttons, crumbs, the cog and the progress bar.
      expect(style.cursor.resolve(const {}), SystemMouseCursors.click);
      expect(style.cursor.resolve({FTappableVariant.disabled}), SystemMouseCursors.basic);
    });
  }

  test('the THUAS corporate green cannot take white text', () {
    // Guards the trap, not the fix: if this passes, the palette has drifted off
    // the house style.
    expect(_contrast(ThuasPalette.corporateGreen, const Color(0xFFFFFFFF)), lessThan(4.5));
  });
}

double _contrast(Color a, Color b) {
  final (high, low) = (math.max(_luminance(a), _luminance(b)), math.min(_luminance(a), _luminance(b)));
  return (high + 0.05) / (low + 0.05);
}

double _luminance(Color color) => color.computeLuminance();
