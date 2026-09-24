import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// Dims everything but [hole], which stays lit **and live**: a press inside it
/// reaches the control underneath, and a press anywhere else is swallowed.
///
/// Both halves come from one [ClipPath]. `RenderClipPath.hitTest` answers
/// false outside its own path, so cutting the hole out of the paint cuts it
/// out of the hit test as well, and the opaque fill takes every press around
/// it. A hole that looked open but caught the press would be a control that
/// seems to do nothing.
///
/// The hole is a squircle like every other corner in the app, which is the
/// reason this is not a coach-mark package: the ones that exist cut a plain
/// rounded rectangle or a circle.
class SpotlightScrim extends StatelessWidget {

  /// In the scrim's own coordinates. Null dims everything.
  final Rect? hole;

  const SpotlightScrim({this.hole, super.key});

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: _HoleClipper(hole),
      child: ColoredBox(color: context.theme.colors.barrier),
    );
  }

}

class _HoleClipper extends CustomClipper<Path> {

  final Rect? hole;

  const _HoleClipper(this.hole);

  @override
  Path getClip(Size size) {
    // Even-odd rather than `Path.combine`: inside the hole is inside two
    // shapes, so it is outside the path. The combined path came out as the
    // whole rectangle on the web build, with no hole to draw or to press.
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size);
    if (hole case final Rect hole) {
      path.addPath(squircleOf(kChipCornerRadius, size: hole.shortestSide).getOuterPath(hole), Offset.zero);
    }
    return path;
  }

  @override
  bool shouldReclip(_HoleClipper oldClipper) => hole != oldClipper.hole;

}
