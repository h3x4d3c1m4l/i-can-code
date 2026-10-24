import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';

/// How far around the button's box is checked for paint, in logical pixels.
const double _band = 4;

/// The MacBook's ratio, where a cut outline showed.
const double _pixelRatio = 2;

/// How far a channel may drift from the page before it counts as paint.
///
/// The squircle's flanks leave a 1/255 trace of antialiasing just past the box.
/// The outline that used to stand out past it was the full ink.
const int _tolerance = 8;

void main() {
  for (final tone in AppButtonTone.values) {
    // A scroll view clips at its own edge, so a button flush against it lost
    // whatever it drew past its box: the left half of its outline.
    testWidgets('a ${tone.name} button draws nothing beside or above its box', (tester) async {
      final key = GlobalKey();
      final theme = buildAppTheme(preset: AppColorPreset.neutral, brightness: Brightness.light);
      const origin = Offset(40, 40);

      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: FTheme(
            data: theme,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: ColoredBox(
                color: theme.colors.background,
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: origin.dx, top: origin.dy),
                    child: AppButton.icon(
                      icon: FLucideIcons.chevronLeft,
                      semanticsLabel: 'Terug',
                      tone: tone,
                      onPress: () {},
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final box = origin & tester.getSize(find.byType(AppButton));
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;

      // `toImage` and `toByteData` both need a real async gap, which the test
      // binding only allows inside `runAsync`.
      late final ui.Image image;
      await tester.runAsync(() async => image = await boundary.toImage(pixelRatio: _pixelRatio));
      final data = (await tester.runAsync(image.toByteData))!;
      final width = image.width;

      bool isPage(int x, int y) {
        for (var channel = 0; channel < 3; channel++) {
          if ((data.getUint8((y * width + x) * 4 + channel) - data.getUint8(channel)).abs() > _tolerance) {
            return false;
          }
        }
        return true;
      }

      final painted = <String>[];

      // Below is left out: the collar is a shadow and hangs beneath on purpose.
      final regions = {
        'left': Rect.fromLTRB(box.left - _band, box.top - _band, box.left, box.bottom),
        'right': Rect.fromLTRB(box.right, box.top - _band, box.right + _band, box.bottom),
        'above': Rect.fromLTRB(box.left, box.top - _band, box.right, box.top),
      };

      for (final MapEntry(key: side, value: region) in regions.entries) {
        for (var y = (region.top * _pixelRatio).round(); y < (region.bottom * _pixelRatio).round(); y++) {
          for (var x = (region.left * _pixelRatio).round(); x < (region.right * _pixelRatio).round(); x++) {
            if (!isPage(x, y)) {
              painted.add('$side ($x, $y)');
            }
          }
        }
      }

      image.dispose();

      expect(painted, isEmpty, reason: 'pixels painted outside the box, in device pixels: ${painted.take(5)}');
    });
  }
}
