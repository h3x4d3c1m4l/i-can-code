import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/theme/app_theme.dart';

/// The face advances 0.6 em, so at this size one character is 12 whole pixels.
/// A fraction would antialias the two drawings below differently.
const double _fontSize = 20;
const double _advance = 12;

/// Runs a coding font with ligatures draws as one glyph: `!=` as a struck
/// through equals sign, `>=` as `≥`, `->` as an arrow.
const List<String> _runs = [
  '==', '!=', '>=', '<=', '->', '=>', '<-', '//', '**', '+=', '-=', '*=', '/=',
  '<<', '>>', ':=', '::', '...', '--', '++', '&&', '||', '|>', '<>', '#!', '/*', 'www',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late final List<FontWeight> weights;

  // Read from the manifest the build writes, so this holds the files
  // `pubspec.yaml` actually bundles under the family the theme names.
  setUpAll(() async {
    final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
    final fonts = [
      for (final family in manifest.cast<Map<String, dynamic>>())
        if (family['family'] == kCodeFontFamily) ...(family['fonts'] as List<dynamic>).cast<Map<String, dynamic>>(),
    ];
    expect(fonts, isNotEmpty, reason: 'pubspec.yaml bundles no font under "$kCodeFontFamily".');

    final loader = FontLoader(kCodeFontFamily);
    for (final font in fonts) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();

    weights = [for (final font in fonts) FontWeight.values[(font['weight'] as int) ~/ 100 - 1]];
  });

  for (final run in _runs) {
    test('the code font draws $run as the characters that were typed', () async {
      for (final weight in weights) {
        final joined = await _pixels([run], weight);
        final apart = await _pixels(run.split(''), weight);

        expect(
          listEquals(joined, apart),
          isTrue,
          reason:
              '"$run" at w${weight.value} is not drawn as its own characters. '
              'The code font MUST have no ligatures: see kCodeFontFamily.',
        );
      }
    });
  }
}

/// Draws [pieces] side by side, each shaped on its own, and returns the pixels.
///
/// A ligature needs its characters in one run of text, so a string drawn whole
/// and the same string drawn a character at a time only match without one.
Future<Uint8List> _pixels(List<String> pieces, FontWeight weight) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  var x = 0.0;
  var height = 0.0;

  for (final piece in pieces) {
    final painter = TextPainter(
      text: TextSpan(
        text: piece,
        style: TextStyle(
          fontFamily: kCodeFontFamily,
          fontSize: _fontSize,
          fontWeight: weight,
          color: const Color(0xFFFFFFFF),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // The test font every unloaded family falls back to is a full em wide, so
    // this is also what says the real face was drawn. Not an exact match:
    // FreeType scales in fixed point, so on Linux a character is 11.99998 wide.
    expect(painter.width, closeTo(_advance * piece.length, 0.01));

    painter.paint(canvas, Offset(x, 0));
    x += painter.width;
    height = painter.height;
    painter.dispose();
  }

  final image = await recorder.endRecording().toImage(x.ceil(), height.ceil());
  final data = (await image.toByteData())!;
  image.dispose();

  return data.buffer.asUint8List();
}
