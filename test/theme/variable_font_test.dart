import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The weights each face is asked for somewhere in the app, lightest first.
const Map<String, List<FontWeight>> _weights = {
  kDisplayFontFamily: [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700],
  kBodyFontFamily: [FontWeight.w400, FontWeight.w500, FontWeight.w600, FontWeight.w700, FontWeight.w800],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final List<Map<String, dynamic>> manifest;

  // Read from the manifest the build writes, so this holds the files
  // `pubspec.yaml` actually bundles.
  setUpAll(() async {
    manifest = (jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>)
        .cast<Map<String, dynamic>>();

    for (final family in manifest) {
      if (!_weights.containsKey(family['family'])) continue;

      final loader = FontLoader(family['family'] as String);
      for (final font in (family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
        loader.addFont(rootBundle.load(font['asset'] as String));
      }
      await loader.load();
    }
  });

  for (final MapEntry(key: family, value: weights) in _weights.entries) {
    test('$family is one file, and every weight the app asks of it is a different drawing', () {
      final fonts = manifest.singleWhere((entry) => entry['family'] == family)['fonts'] as List<dynamic>;
      expect(fonts, hasLength(1), reason: '$family is bundled as one variable font.');

      // Two weights that measure the same mean the weight was ignored, and
      // every style is drawing the font's default instance. Not "heavier is
      // wider": Fredoka at 500 is a hair narrower than at 400.
      final widths = {for (final weight in weights) 'w${weight.value}': _width(family, weight)};
      expect(widths.values.toSet(), hasLength(weights.length), reason: '$family measured $widths.');
    });
  }

  test('a family named Roboto is bundled, so the web engine does not fetch one', () {
    // The engine downloads Roboto from fonts.gstatic.com when the manifest has
    // no family by that name.
    expect(manifest.map((entry) => entry['family']), contains('Roboto'));
  });
}

double _width(String family, FontWeight weight) {
  final painter = TextPainter(
    text: TextSpan(
      text: 'Hamburgefonstiv 0123456789',
      style: TextStyle(fontFamily: family, fontSize: 40, fontWeight: weight),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  final width = painter.width;
  painter.dispose();

  return width;
}
