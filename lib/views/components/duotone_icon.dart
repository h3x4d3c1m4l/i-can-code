import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/icons/icon_bundle.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:vector_graphics/vector_graphics_compat.dart';

/// A [CourseIcon], drawn in the theme's two illustration colours.
///
/// It MUST stand on the page or on a card, never on `primary`: see
/// [AppSemanticColors.illustrationLine].
///
/// How it gets two colours out of one picture. `bin/bundle_icons.dart` compiles
/// every file under `assets/icons/` into one [IconBundle] at build time, and a
/// compiled picture keeps the colours it was drawn in: one [ColorFilter] over
/// all of it is the only way to change them afterwards. `ColorMapper` and
/// `SvgTheme` reach only SVG parsed at runtime. So each file is drawn in two
/// keys, [lineKey] and [fillKey], and one [ColorFilter.matrix] sends red to the
/// line colour and green to the fill.
///
/// What that leans on:
/// - Skia applies a matrix filter to unpremultiplied colour, so alpha passes
///   through and a half-covered edge keeps its coverage.
/// - Where an edge mixes the two keys, red and green still add up to one, and
///   the matrix turns the mix into the same mix of the two theme colours. That
///   holds only while a file uses no colour but the keys, and both theme
///   colours are opaque. `duotone_icon_test.dart` holds the files to it.
/// - A picture that fails to load is an empty box and no error, so the same
///   test holds [CourseIcon], the files and the bundle to each other.
class DuotoneIcon extends StatelessWidget {

  /// What the outline of every icon is drawn in.
  static const Color lineKey = Color(0xFFFF0000);

  /// What the shapes inside the outline are drawn in.
  static const Color fillKey = Color(0xFF00FF00);

  final CourseIcon icon;

  /// Width and height. Fixed, so nothing moves when the picture arrives.
  final double size;

  const DuotoneIcon(this.icon, {required this.size, super.key});

  /// [icon] inside a line of text set in [style], followed by a space.
  ///
  /// As tall as the line can take without growing, through the same text
  /// scaler as the words beside it.
  static InlineSpan span(BuildContext context, CourseIcon icon, {required TextStyle style}) {
    final scaler = MediaQuery.textScalerOf(context);
    final fontSize = scaler.scale(style.fontSize ?? 14);
    final size = math.min(fontSize * (style.height ?? 1.2), fontSize * 1.2);

    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: EdgeInsetsDirectional.only(end: fontSize * 0.3),
        child: DuotoneIcon(icon, size: size),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return createCompatVectorGraphic(
      loader: _BundledIcon(icon),
      width: size,
      height: size,
      // A picture rather than vector_graphics' default raster: an icon is drawn
      // at several sizes, and a raster costs a pixel read-back per size on the
      // web.
      strategy: RenderingStrategy.picture,
      excludeFromSemantics: true,
      colorFilter: _keyed(colors.illustrationLine, colors.illustrationFill),
    );
  }

  static ColorFilter _keyed(Color line, Color fill) => ColorFilter.matrix([
    line.r, fill.r, 0, 0, 0,
    line.g, fill.g, 0, 0, 0,
    line.b, fill.b, 0, 0, 0,
    0, 0, 0, 1, 0,
  ]);

}

/// One icon's bytes, out of the bundle that holds them all. The bundle is
/// fetched once, by whichever icon asks first.
class _BundledIcon extends BytesLoader {

  static Future<IconBundle>? _bundle;

  final CourseIcon icon;

  const _BundledIcon(this.icon);

  static Future<IconBundle> _load() async {
    try {
      return IconBundle.decode(await rootBundle.load(IconBundle.asset));
    } catch (_) {
      // So the next icon asks again, rather than every one staying empty for
      // as long as the page is open.
      _bundle = null;
      rethrow;
    }
  }

  @override
  Future<ByteData> loadBytes(BuildContext? context) async {
    final bundle = await (_bundle ??= _load());

    return bundle[icon.key] ?? (throw StateError('The icon bundle holds no ${icon.key}.'));
  }

  // vector_graphics caches a picture by its loader, so two loaders of one
  // icon MUST be equal for every tile to share one decode.
  @override
  bool operator ==(Object other) => other is _BundledIcon && other.icon == icon;

  @override
  int get hashCode => icon.hashCode;

}
