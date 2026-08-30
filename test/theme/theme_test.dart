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
    group(preset.name, () {
      final resolved = preset.resolve();
      final colors = resolved.colors;
      final semantic = resolved.semantic;

      test('builds a theme', () => expect(buildAppTheme(preset: preset).colors.primary, colors.primary));

      test('carries its own tokens on the theme', () {
        expect(buildAppTheme(preset: preset).extensions, isNotEmpty);
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
        'warning on its foreground': (semantic.warning, semantic.warningForeground),
        'text on the success surface': (semantic.successSurface, colors.foreground),
        'text on the warning surface': (semantic.warningSurface, colors.foreground),
        'text on the error surface': (semantic.errorSurface, colors.foreground),
        'code on the editor': (semantic.codeBackground, semantic.codeForeground),
        'editor chrome on the editor': (semantic.codeBackground, semantic.codeMuted),
      };

      for (final MapEntry(key: name, value: pair) in pairs.entries) {
        test('$name clears WCAG AA', () => expect(_contrast(pair.$1, pair.$2), greaterThanOrEqualTo(4.5)));
      }
    });
  }

  test('every tappable shows a click cursor, but not when disabled', () {
    // forui defaults this to `MouseCursor.defer`, which leaves the ordinary
    // arrow over buttons on the web.
    final cursor = buildAppTheme().style.tappableStyle.cursor;

    expect(cursor.resolve(const {}), SystemMouseCursors.click);
    expect(cursor.resolve({FTappableVariant.disabled}), SystemMouseCursors.basic);
  });

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
