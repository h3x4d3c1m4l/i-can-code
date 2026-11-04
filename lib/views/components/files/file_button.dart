import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/hover_tip.dart';
import 'package:i_can_code/views/components/shortened_tip.dart';

/// A file's name, drawn as a control in the outlined button's own ink: what a
/// lesson's files card is made of, and the folder the console and the program
/// page share.
class FileButton extends StatelessWidget {

  /// The height the corners are worked out for: a line of the code face at
  /// 15px and the padding around it.
  static const double _height = 40;

  static const EdgeInsets _padding = EdgeInsets.symmetric(horizontal: 14, vertical: 8);
  static const double _iconSize = 18;
  static const double _gap = 8;

  /// In the code face. Null for a button that is only its [icon].
  final String? label;

  final IconData? icon;

  /// A word after the label, in the muted colour, such as "gewijzigd".
  final String? note;

  /// Where the label is cut off with an ellipsis, and then said in full on
  /// hover. Null to never cut it.
  final double? maxLabelWidth;

  /// Shown on hover, for a button whose [icon] is all it says.
  final String? tip;

  /// What a screen reader hears in place of everything drawn.
  final String semanticsLabel;

  final VoidCallback onPress;

  const FileButton({
    required this.semanticsLabel,
    required this.onPress,
    this.label,
    this.icon = FLucideIcons.fileText,
    this.note,
    this.maxLabelWidth,
    this.tip,
    super.key,
  }) : assert(label != null || icon != null, 'A button with nothing to show');

  static TextStyle _labelStyle(BuildContext context) =>
      context.appTheme.text.code.copyWith(fontSize: 15, color: context.appTheme.colors.neutralButton);

  static TextStyle _noteStyle(BuildContext context) =>
      context.appTheme.text.bodySmall.copyWith(fontSize: 13, color: context.theme.colors.mutedForeground);

  /// How wide [label] is on a button, uncut, at the reader's own text size.
  static double labelWidth(BuildContext context, String label) => _measure(context, label, _labelStyle(context));

  /// How wide a button with these parts comes out, so a row of them can be laid
  /// out without building them. The label is cut at [maxLabelWidth] as the
  /// button cuts it.
  static double widthFor(
    BuildContext context, {
    String? label,
    IconData? icon = FLucideIcons.fileText,
    String? note,
    double? maxLabelWidth,
  }) {
    final parts = [
      if (icon != null) _iconSize,
      if (label != null) min(labelWidth(context, label), maxLabelWidth ?? double.infinity),
      if (note != null) _measure(context, note, _noteStyle(context)),
    ];
    return _padding.horizontal + parts.fold(0, (sum, part) => sum + part) + _gap * (parts.length - 1);
  }

  static double _measure(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // Rounded up, because a box narrower than the text by a fraction of a
    // pixel is enough to cut it.
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final ink = context.appTheme.colors.neutralButton;
    final label = this.label;
    final maxLabelWidth = this.maxLabelWidth;

    Widget button = FTappable(
      onPress: onPress,
      semanticsButton: true,
      semanticsLabel: semanticsLabel,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          // The outlined button's hover, so the two read as one family.
          color: states.contains(FTappableVariant.hovered) || states.contains(FTappableVariant.focused)
              ? ink.withValues(alpha: 0.1)
              : theme.colors.background,
          shape: squircleOf(kChipCornerRadius, size: _height, side: BorderSide(color: ink, width: 1.5)),
        ),
        child: child,
      ),
      // The label above says all of it, so the name is not read out twice.
      child: ExcludeSemantics(
        child: Padding(
          padding: _padding,
          // Over an empty line in the label's style, the way `AppButton` does
          // it, so a button that is only its icon is as tall as one with a
          // name, and a line of them is one height.
          child: Stack(
            alignment: Alignment.center,
            children: [
              Text('', style: _labelStyle(context)),
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: _gap,
                children: [
                  if (icon case final IconData icon) Icon(icon, size: _iconSize, color: ink),
                  if (label != null)
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxLabelWidth ?? double.infinity),
                      child: Text(
                        label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: _labelStyle(context),
                      ),
                    ),
                  if (note case final String note) Text(note, style: _noteStyle(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (label != null && maxLabelWidth != null) button = ShortenedTip(message: label, child: button);
    if (tip case final String tip) button = HoverTip(message: tip, child: button);
    return button;
  }

}
