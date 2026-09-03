import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/catalog_card.dart';

/// How far apart a pixel's channels must be before it counts as coloured
/// rather than as a grey. Small, because a tint is still colour.
const int _chromaThreshold = 12;

/// The share of a rendered screen that MUST carry colour.
///
/// One percent is a low bar on purpose: this is not a design assertion, it is
/// the tripwire for a whole preset silently coming out greyscale — which is
/// exactly what shipped when the app was pinned to forui's neutral scheme and
/// measured 0.00%.
const double _minimumChromaticShare = 0.01;

void main() {
  for (final preset in AppColorPreset.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${preset.name} ${brightness.name} paints in colour', (tester) async {
        final share = await _chromaticShare(tester, preset: preset, brightness: brightness);

        expect(
          share,
          greaterThan(_minimumChromaticShare),
          reason:
              '${preset.name} ${brightness.name} rendered ${(share * 100).toStringAsFixed(2)}% coloured pixels. '
              'A preset whose tokens are all greys reads as a broken theme.',
        );
      });
    }
  }
}

/// Renders a [CatalogCard] on its page and returns the fraction of pixels whose
/// channels are more than [_chromaThreshold] apart.
///
/// A catalog card is used because it exercises the tokens a student meets
/// first: the page, a card, the `primary` tile and its foreground.
Future<double> _chromaticShare(
  WidgetTester tester, {
  required AppColorPreset preset,
  required Brightness brightness,
}) async {
  final key = GlobalKey();
  final theme = buildAppTheme(preset: preset, brightness: brightness);

  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: FTheme(
        data: theme,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: MediaQuery(
            data: const MediaQueryData(size: Size(800, 400)),
            child: ColoredBox(
              color: theme.colors.background,
              child: const Center(
                child: SizedBox(
                  width: 700,
                  child: CatalogCard(
                    label: '1',
                    title: 'Invoer en uitvoer',
                    subtitle: 'Lezen en schrijven',
                    meta: '0 / 5',
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

  // `toImage` and `toByteData` both need a real async gap, which the test
  // binding only allows inside `runAsync`.
  late final ui.Image image;
  await tester.runAsync(() async => image = await boundary.toImage());
  final data = (await tester.runAsync(image.toByteData))!;

  var coloured = 0;
  var total = 0;

  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);

    total++;
    if ([r, g, b].reduce((a, c) => a > c ? a : c) - [r, g, b].reduce((a, c) => a < c ? a : c) > _chromaThreshold) {
      coloured++;
    }
  }

  image.dispose();

  return coloured / total;
}
