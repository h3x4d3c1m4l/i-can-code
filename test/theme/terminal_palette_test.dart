import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/terminal_palette.dart';

void main() {
  // The terminal draws on the app's code surface, which is dark in every preset
  // and both brightnesses — which is why there is one ANSI palette and not four.
  // This is the test that says so: if a preset ever gives `codeBackground` a
  // light colour, every colour below stops clearing AA at once.
  for (final preset in AppColorPreset.values) {
    for (final brightness in Brightness.values) {
      group('${preset.name} ${brightness.name}', () {
        final semantic = preset.resolve(brightness: brightness).semantic;

        for (final (index, color) in AnsiPalette.all.indexed) {
          test('ANSI colour $index is readable on the code surface', () {
            expect(_contrast(color, semantic.codeBackground), greaterThanOrEqualTo(4.5));
          });
        }

        test('the terminal takes its surface from the app', () {
          final theme = buildTerminalTheme(semantic, cursor: const Color(0xFFFFFFFF));

          expect(theme.background, semantic.codeBackground);
          expect(theme.foreground, semantic.codeForeground);
        });
      });
    }
  }

  test('every ANSI slot is a different colour', () {
    expect(AnsiPalette.all.toSet(), hasLength(AnsiPalette.all.length));
  });
}

double _contrast(Color a, Color b) {
  final (high, low) = (math.max(a.computeLuminance(), b.computeLuminance()), math.min(a.computeLuminance(), b.computeLuminance()));
  return (high + 0.05) / (low + 0.05);
}
