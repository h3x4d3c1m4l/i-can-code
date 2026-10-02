import 'dart:ui' show lerpDouble;

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

  /// How the face is pulled out of shape. [LogoPose.rest] is the mark as drawn.
  final LogoPose pose;

  const AppLogo({this.size = 38, this.pose = LogoPose.rest, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;

    return Transform.translate(
      offset: Offset(0, -pose.lift * size),
      child: Transform.scale(
        scale: pose.scale,
        child: Transform(
          // From the bottom edge, so a squashed tile sits down on the bar
          // rather than shrinking towards its middle.
          alignment: Alignment.bottomCenter,
          transform: Matrix4.diagonal3Values(1 / pose.stretch, pose.stretch, 1),
          child: SizedBox.square(
            dimension: size,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: theme.colors.primary,
                // The design's radii are a third of the tile at both sizes it uses
                // (13/38 and 40/118). Clamped, because the scaled radius would
                // otherwise deform a box this small.
                shape: squircleOf(size / 3, size: size),
              ),
              child: CustomPaint(painter: _MarkPainter(color: theme.colors.primaryForeground, pose: pose)),
            ),
          ),
        ),
      ),
    );
  }

}

/// One frame of the face, as a set of departures from the mark as drawn.
class LogoPose {

  /// The mark as drawn.
  static const rest = LogoPose();

  /// How open each eye is, from 1 (a `^`) to 0 (shut, a `-`).
  final double leftEye;
  final double rightEye;

  /// How far the smile has widened into a grin, from 0 to 1.
  final double grin;

  /// The tile's height against its width. The width takes the inverse, so the
  /// tile keeps its area: below 1 is squashed, above 1 stretched.
  final double stretch;

  /// How far the tile has risen off its spot, as a share of its size.
  final double lift;

  /// The whole tile's size against its own, from its centre.
  final double scale;

  const LogoPose({
    this.leftEye = 1,
    this.rightEye = 1,
    this.grin = 0,
    this.stretch = 1,
    this.lift = 0,
    this.scale = 1,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LogoPose &&
          other.leftEye == leftEye &&
          other.rightEye == rightEye &&
          other.grin == grin &&
          other.stretch == stretch &&
          other.lift == lift &&
          other.scale == scale;

  @override
  int get hashCode => Object.hash(leftEye, rightEye, grin, stretch, lift, scale);

}

/// Draws the mark from its master drawing, a 256-unit square of round-capped
/// strokes, bent by a [LogoPose].
class _MarkPainter extends CustomPainter {

  /// The glyph's share of the tile; the rest is the tile's margin.
  static const _glyphScale = 0.66;

  /// Where each eye's `^` starts, in master units. Each is 64 wide.
  static const _leftEyeX = 44.0;
  static const _rightEyeX = 148.0;
  static const _eyeBase = 109.0;
  static const _eyeApex = 77.0;

  /// A shut eye is a dash halfway up the open one, so a wink does not drop it.
  static const _eyeShut = 93.0;

  /// The smile's two ends and its control point, at rest and at a full grin.
  static const _mouthRest = (left: 72.0, right: 184.0, ends: 153.0, control: 205.0);
  static const _mouthGrin = (left: 58.0, right: 198.0, ends: 145.0, control: 228.0);

  final Color color;
  final LogoPose pose;

  const _MarkPainter({required this.color, required this.pose});

  Path _face() {
    final path = Path();

    void eye(double x, double openness) {
      final base = lerpDouble(_eyeShut, _eyeBase, openness)!;
      path
        ..moveTo(x, base)
        ..lineTo(x + 32, lerpDouble(_eyeShut, _eyeApex, openness)!)
        ..lineTo(x + 64, base);
    }

    eye(_leftEyeX, pose.leftEye);
    eye(_rightEyeX, pose.rightEye);

    double mouth(double rest, double grin) => lerpDouble(rest, grin, pose.grin)!;
    final ends = mouth(_mouthRest.ends, _mouthGrin.ends);
    return path
      ..moveTo(mouth(_mouthRest.left, _mouthGrin.left), ends)
      ..quadraticBezierTo(
        128,
        mouth(_mouthRest.control, _mouthGrin.control),
        mouth(_mouthRest.right, _mouthGrin.right),
        ends,
      );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 256 * _glyphScale;
    canvas
      ..translate(size.width / 2, size.height / 2)
      ..scale(scale)
      ..translate(-128, -128)
      ..drawPath(
        _face(),
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 28
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
  }

  @override
  bool shouldRepaint(_MarkPainter oldDelegate) => oldDelegate.color != color || oldDelegate.pose != pose;

}
