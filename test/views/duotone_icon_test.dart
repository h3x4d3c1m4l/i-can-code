import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/services/icons/icon_bundle.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/theme/presets/app_color_preset.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/duotone_icon.dart';

/// Every colour an SVG can name, by the attribute it names it in.
final RegExp _colour = RegExp(r'\b(fill|stroke|color|stop-color|flood-color)="([^"]*)"');

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// How far apart two colours are, channel by channel, out of 255.
int _distance(int r, int g, int b, Color color) => [
  (r - (color.r * 255).round()).abs(),
  (g - (color.g * 255).round()).abs(),
  (b - (color.b * 255).round()).abs(),
].reduce((a, c) => a > c ? a : c);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every icon has its file, and the folder holds nothing else', () {
    // The bundler stops at a missing one. A stray one it leaves out, which is a
    // picture nobody can name.
    final files = Directory('assets/icons').listSync().map((file) => file.uri.pathSegments.last).toSet();

    expect(files, {for (final icon in CourseIcon.values) '${icon.key}.svg'});
  });

  group('every source is drawn in the two keys and nothing else', () {
    final keys = {'NONE', _hex(DuotoneIcon.lineKey), _hex(DuotoneIcon.fillKey)};

    for (final icon in CourseIcon.values) {
      test(icon.key, () {
        final source = File('assets/icons/${icon.key}.svg').readAsStringSync();

        for (final match in _colour.allMatches(source)) {
          expect(keys, contains(match.group(2)!.toUpperCase()), reason: match.group(0));
        }
        // Both would name a colour this test cannot see.
        expect(source, isNot(contains('style=')));
        expect(source, isNot(contains('currentColor')));
        expect(source, contains('viewBox="0 0 96 96"'));
      });
    }
  });

  testWidgets('the bundle holds every icon compiled, and nothing else', (tester) async {
    final bundle = IconBundle.decode((await tester.runAsync(() => rootBundle.load(IconBundle.asset)))!);

    expect(bundle.keys.toSet(), {for (final icon in CourseIcon.values) icon.key});
    for (final icon in CourseIcon.values) {
      final bytes = bundle[icon.key]!;
      expect(bytes.lengthInBytes, greaterThan(0), reason: icon.key);
      expect(bytes.getUint8(0), isNot('<'.codeUnitAt(0)), reason: '${icon.key} reached the bundle uncompiled');
    }
  });

  for (final preset in AppColorPreset.values) {
    for (final brightness in Brightness.values) {
      testWidgets('${preset.name} ${brightness.name} draws the keys in its own two colours', (tester) async {
        final theme = buildAppTheme(preset: preset, brightness: brightness);
        final semantic = preset.resolve(brightness: brightness).semantic;
        final key = GlobalKey();

        await tester.runAsync(() async {
          await tester.pumpWidget(
            FTheme(
              data: theme,
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: Center(
                  child: RepaintBoundary(
                    key: key,
                    child: ColoredBox(
                      color: theme.colors.background,
                      // A large fill under a run of lines, so both colours
                      // cover whole pixels.
                      child: const DuotoneIcon(CourseIcon.list, size: 192),
                    ),
                  ),
                ),
              ),
            ),
          );
          // The picture loads from the bundle, which takes a real async gap.
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();

        final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        late final ui.Image image;
        await tester.runAsync(() async => image = await boundary.toImage());
        final data = (await tester.runAsync(image.toByteData))!;
        image.dispose();

        var line = 0;
        var fill = 0;
        for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
          final (r, g, b) = (data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));

          expect(_distance(r, g, b, DuotoneIcon.lineKey), greaterThan(40), reason: 'a key showed through');
          expect(_distance(r, g, b, DuotoneIcon.fillKey), greaterThan(40), reason: 'a key showed through');
          if (_distance(r, g, b, semantic.illustrationLine) <= 2) line++;
          if (_distance(r, g, b, semantic.illustrationFill) <= 2) fill++;
        }

        expect(line, greaterThan(500), reason: 'the outline is drawn in illustrationLine');
        expect(fill, greaterThan(500), reason: 'the shapes inside it in illustrationFill');
      });
    }
  }
}
