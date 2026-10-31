import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/guttered_scroll_view.dart';

/// Lays [child] out at the width it is given, and scrolls it sideways only when
/// it cannot get that narrow.
///
/// Made for a table whose columns stop shrinking at their longest word. A plain
/// horizontal scroll view hands its child an unbounded width, so a table in one
/// never wraps a cell: it runs wider than the page even where it would have fit.
/// Here the child gets the viewport's width, or its own minimum intrinsic width
/// when that is more, and the view has something to scroll only in that case.
///
/// The child MUST answer for its minimum intrinsic width. A [LayoutBuilder]
/// below this one cannot, and throws.
///
/// The scroll view is a [GutteredScrollView], so it is always taller than the
/// child by the scrollbar's gutter, even when nothing scrolls.
class FitOrScrollSideways extends StatelessWidget {

  final Widget child;

  const FitOrScrollSideways({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => GutteredScrollView(
        scrollDirection: Axis.horizontal,
        child: _AtLeastNarrowest(width: constraints.maxWidth, child: child),
      ),
    );
  }

}

class _AtLeastNarrowest extends SingleChildRenderObjectWidget {

  /// The viewport's width, read outside the scroll view that unbounds it.
  final double width;

  const _AtLeastNarrowest({required this.width, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderAtLeastNarrowest(width);

  @override
  void updateRenderObject(BuildContext context, _RenderAtLeastNarrowest renderObject) {
    renderObject.width = width;
  }

}

class _RenderAtLeastNarrowest extends RenderProxyBox {

  double _width;

  _RenderAtLeastNarrowest(this._width);

  set width(double value) {
    if (value == _width) {
      return;
    }
    _width = value;
    markNeedsLayout();
  }

  BoxConstraints _childConstraints(RenderBox child) {
    final narrowest = child.getMinIntrinsicWidth(double.infinity);
    return BoxConstraints.tightFor(width: _width.isFinite ? math.max(_width, narrowest) : narrowest);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) {
      return constraints.smallest;
    }
    return constraints.constrain(child.getDryLayout(_childConstraints(child)));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_childConstraints(child), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

}
