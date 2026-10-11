import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:material_ui/material_ui.dart' show InputBorder;

/// Every border a forui text field draws, as a squircle of [radius].
///
/// All five states are restated because an override costs that much here: the
/// border carries its own colour, so replacing one replaces the colour with
/// it. The colours are the ones forui picks for each state, read back off the
/// theme rather than chosen here: a field only has a corner problem, and
/// picking a border colour at a call site is how a control ends up illegible
/// in one preset.
FVariantsValueDelta<FTextFieldVariantConstraint, FTextFieldVariant, InputBorder, Delta> squircleFieldBorder(
  BuildContext context, {
  required double radius,
}) {
  final colors = context.theme.colors;
  final width = context.theme.style.borderWidth;

  SquircleInputBorder border(Color color) =>
      SquircleInputBorder(radius: radius, borderSide: BorderSide(color: color, width: width));

  return FVariantsValueDelta.delta([
    FVariantValueDeltaOperation.base(border(colors.border)),
    FVariantValueDeltaOperation.exact({FTextFieldVariantConstraint.focused}, border(colors.primary)),
    FVariantValueDeltaOperation.exact({FTextFieldVariantConstraint.disabled}, border(colors.disable(colors.border))),
    FVariantValueDeltaOperation.exact({FTextFieldVariantConstraint.error}, border(colors.error)),
    FVariantValueDeltaOperation.exact(
      {FTextFieldVariantConstraint.error, FTextFieldVariantConstraint.disabled},
      border(colors.disable(colors.error)),
    ),
  ]);
}

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
