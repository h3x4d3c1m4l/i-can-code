import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A row of crumbs that always fits its width.
///
/// While it fits, every crumb is as wide as it wants to be. When it does not:
///
/// 1. Every crumb but the last gives up room, the widest first, down to
///    [minCrumbWidth].
/// 2. Then the last one does, down to the same.
/// 3. Then crumbs leave from the front, each with the divider after it, and
///    what that frees goes back to the ones still standing.
///
/// **Not a [Row] of [Flexible]s.** A flex layout hands each flexible child an
/// equal share of the free width and does not pass on what a short one leaves
/// unused, so a long crumb is cut while the row still has room for it.
///
/// It only narrows a crumb's box. A crumb MUST cut its own content to that box,
/// as a one-line [Text] with an ellipsis does.
class ShrinkingTrail extends MultiChildRenderObjectWidget {

  /// The least a crumb is narrowed to while another still stands beside it.
  ///
  /// SHOULD be the room a crumb needs to still say something. A text narrower
  /// than one letter and its ellipsis draws nothing at all, which would leave
  /// a divider with no crumb on either side of it.
  final double minCrumbWidth;

  /// [divider] is built once between every two of [crumbs].
  ShrinkingTrail({
    required List<Widget> crumbs,
    required Widget divider,
    this.minCrumbWidth = 0,
    super.key,
  }) : super(
         children: [
           for (final (index, crumb) in crumbs.indexed) ...[
             if (index > 0) divider,
             crumb,
           ],
         ],
       );

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderShrinkingTrail(minCrumbWidth);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) =>
      (renderObject as _RenderShrinkingTrail).minCrumbWidth = minCrumbWidth;

}

class _TrailParentData extends ContainerBoxParentData<RenderBox> {
}

/// What each child is laid out under, and the index of the first one that is
/// still part of the trail.
typedef _Plan = ({List<BoxConstraints> shares, int first});

/// Crumbs and dividers alternate, so a crumb is a child at an even index and
/// the last child is the last crumb.
class _RenderShrinkingTrail extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TrailParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TrailParentData> {

  _RenderShrinkingTrail(this._minCrumbWidth);

  double _minCrumbWidth;

  set minCrumbWidth(double value) {
    if (value == _minCrumbWidth) return;
    _minCrumbWidth = value;
    markNeedsLayout();
  }

  /// The first child the last layout kept. The ones before it are laid out at
  /// no size and MUST NOT be painted: an icon draws its glyph whatever the
  /// size of its box.
  int _first = 0;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TrailParentData) child.parentData = _TrailParentData();
  }

  /// Takes [excess] out of the [widths] at [indices] between them, the widest
  /// first and none to under [floor]. Returns what they could not give up.
  static double _narrow(List<double> widths, List<int> indices, double excess, double floor) {
    final widestFirst = [for (final index in indices) widths[index]]..sort((a, b) => b.compareTo(a));

    // The width none of them may pass: the widest are levelled down to the
    // next one until that has freed enough. Null when all of it is too little.
    double? level;
    var taken = 0.0;
    for (var count = 1; count <= widestFirst.length; count++) {
      taken += widestFirst[count - 1];
      final next = count < widestFirst.length ? widestFirst[count] : 0.0;
      if (taken - count * next >= excess) {
        level = (taken - excess) / count;
        break;
      }
    }
    // Stated rather than added up, so a rounding error cannot ask the next
    // crumb in line for a millionth of a pixel and get an ellipsis for it.
    final enough = level != null && level >= floor;
    final cap = enough ? level : floor;

    var freed = 0.0;
    for (final index in indices) {
      if (widths[index] <= cap) continue;
      freed += widths[index] - cap;
      widths[index] = cap;
    }
    return enough ? 0 : excess - freed;
  }

  /// How the children share [constraints] for the trail to fit them.
  ///
  /// A child that keeps the width it wants is left unbounded. Handing it that
  /// width back as a limit would be asking the text to fit the number it just
  /// reported, a rounding error away from an ellipsis nothing called for.
  _Plan _planFor(BoxConstraints constraints) {
    final children = getChildrenAsList();
    final maxWidth = constraints.maxWidth;
    final loose = BoxConstraints(maxHeight: constraints.maxHeight);
    if (children.isEmpty || maxWidth.isInfinite) return (shares: List.filled(children.length, loose), first: 0);

    final wanted = [for (final child in children) child.getMaxIntrinsicWidth(double.infinity)];
    final last = children.length - 1;

    for (var first = 0; ; first += 2) {
      final widths = [...wanted];
      var excess = -maxWidth;
      for (var index = first; index <= last; index++) {
        excess += widths[index];
      }

      final others = [for (var index = first; index < last; index += 2) index];
      if (excess > 0) excess = _narrow(widths, others, excess, _minCrumbWidth);
      // Alone, the last crumb takes whatever there is.
      if (excess > 0) excess = _narrow(widths, [last], excess, first == last ? 0 : _minCrumbWidth);
      if (excess > 0 && first < last) continue;

      return (
        shares: [
          for (var index = 0; index <= last; index++)
            if (index < first)
              BoxConstraints.tight(Size.zero)
            else if (widths[index] < wanted[index])
              loose.copyWith(maxWidth: widths[index])
            else
              loose,
        ],
        first: first,
      );
    }
  }

  /// The trail's size under [constraints] and each child's under its share of
  /// them, measured by [layoutChild]: a real layout, or a dry one.
  (Size, List<Size>) _measure(BoxConstraints constraints, List<BoxConstraints> shares, ChildLayouter layoutChild) {
    final sizes = <Size>[];
    for (var child = firstChild; child != null; child = childAfter(child)) {
      sizes.add(layoutChild(child, shares[sizes.length]));
    }

    final width = sizes.fold(0.0, (sum, size) => sum + size.width);
    final height = sizes.fold(0.0, (tallest, size) => math.max(tallest, size.height));

    return (constraints.constrain(Size(width, height)), sizes);
  }

  @override
  void performLayout() {
    final plan = _planFor(constraints);
    final (trail, sizes) = _measure(constraints, plan.shares, ChildLayoutHelper.layoutChild);
    size = trail;
    _first = plan.first;

    var x = 0.0;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      (child.parentData! as _TrailParentData).offset = Offset(x, (trail.height - sizes[index].height) / 2);
      x += sizes[index].width;
      index++;
    }
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      _measure(constraints, _planFor(constraints).shares, ChildLayoutHelper.dryLayoutChild).$1;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) {
    final plan = _planFor(constraints);
    final (trail, sizes) = _measure(constraints, plan.shares, ChildLayoutHelper.dryLayoutChild);

    double? highest;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (index >= plan.first) {
        if (child.getDryBaseline(plan.shares[index], baseline) case final double distance) {
          final fromTop = (trail.height - sizes[index].height) / 2 + distance;
          highest = math.min(highest ?? fromTop, fromTop);
        }
      }
      index++;
    }
    return highest;
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    double? highest;
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (index >= _first) {
        if (child.getDistanceToActualBaseline(baseline) case final double distance) {
          final fromTop = (child.parentData! as _TrailParentData).offset.dy + distance;
          highest = math.min(highest ?? fromTop, fromTop);
        }
      }
      index++;
    }
    return highest;
  }

  /// The last crumb alone, and that narrowed to nothing.
  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      width += child.getMaxIntrinsicWidth(height);
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  /// Narrowing a crumb cuts its line short and never wraps it, so the height
  /// does not depend on the width.
  @override
  double computeMaxIntrinsicHeight(double width) {
    var height = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      height = math.max(height, child.getMaxIntrinsicHeight(double.infinity));
    }
    return height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var index = 0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      if (index >= _first) context.paintChild(child, (child.parentData! as _TrailParentData).offset + offset);
      index++;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

}
