import 'package:flutter/widgets.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:material_ui/material_ui.dart' show InputBorder;

/// The app's corner, in the one place that will not take a [ShapeBorder].
///
/// forui types a text field's border as Material's [InputBorder], whose two
/// concrete forms draw a plain rounded rectangle and nothing else — so a field
/// is the one control in the app that `squircle()` cannot reach, and it would
/// otherwise sit among the cards and buttons with visibly different corners.
///
/// [InputBorder] is itself a [ShapeBorder], so this is a subclass that hands
/// every question to the real squircle and answers [isOutline] for Material's
/// own layout code. Nothing here is a shape of its own: change [squircle] and
/// this changes with it.
class SquircleInputBorder extends InputBorder {

  /// In the design's own numbers, the way every other radius is stated.
  final double radius;

  const SquircleInputBorder({required this.radius, super.borderSide});

  ShapeBorder get _shape => squircle(radius, side: borderSide);

  /// True so the field lays its label and content out inside the border rather
  /// than above a single underline.
  @override
  bool get isOutline => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(borderSide.width);

  @override
  SquircleInputBorder copyWith({BorderSide? borderSide, double? radius}) =>
      SquircleInputBorder(radius: radius ?? this.radius, borderSide: borderSide ?? this.borderSide);

  @override
  ShapeBorder scale(double t) =>
      SquircleInputBorder(radius: radius * t, borderSide: borderSide.scale(t));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getInnerPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _shape.getOuterPath(rect, textDirection: textDirection);

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0,
    double gapPercentage = 0,
    TextDirection? textDirection,
  }) {
    // The gap arguments are Material's floating-label cut-out, which forui does
    // not use: its label sits above the field rather than on its edge.
    _shape.paint(canvas, rect, textDirection: textDirection);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SquircleInputBorder && other.radius == radius && other.borderSide == borderSide;

  @override
  int get hashCode => Object.hash(radius, borderSide);

}
