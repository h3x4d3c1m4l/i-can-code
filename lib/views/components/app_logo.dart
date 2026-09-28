import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// The app's mark on a filled tile: a face made of code, two `^` for eyes and
/// a bracket for a smile. Deliberately language-agnostic — the app is not a
/// Python app.
///
/// `web/icon.svg`, the icons beside it and the splash in `web/index.html` draw
/// the same mark and MUST be changed alongside it.
///
/// Used at 38px in the header and 118px on the initialization screen, so [size]
/// is a parameter and everything else scales off it.
class AppLogo extends StatelessWidget {

  /// The tile's width and height.
  final double size;

  const AppLogo({this.size = 38, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.primary,
          // The design's radii are a third of the tile at both sizes it uses
          // (13/38 and 40/118). Clamped, because the scaled radius would
          // otherwise deform a box this small.
          shape: squircleOf(size / 3, size: size),
        ),
        child: CustomPaint(painter: _MarkPainter(color: theme.colors.primaryForeground)),
      ),
    );
  }

}

/// Draws the mark from its master drawing, a 256-unit square of round-capped strokes.
class _MarkPainter extends CustomPainter {

  /// The glyph's share of the tile; the rest is the tile's margin.
  static const _glyphScale = 0.66;

  static final _path = Path()
    ..moveTo(44, 109)
    ..lineTo(76, 77)
    ..lineTo(108, 109)
    ..moveTo(148, 109)
    ..lineTo(180, 77)
    ..lineTo(212, 109)
    ..moveTo(72, 153)
    ..quadraticBezierTo(128, 205, 184, 153);

  final Color color;

  const _MarkPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 256 * _glyphScale;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-128, -128)
      ..drawPath(
        _path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 28
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color;

}
