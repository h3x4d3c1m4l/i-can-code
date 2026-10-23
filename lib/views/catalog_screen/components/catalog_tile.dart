import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/bevelled_card.dart';
import 'package:i_can_code/views/components/completed_badge.dart';
import 'package:i_can_code/views/components/duotone_icon.dart';
import 'package:i_can_code/views/components/shortened_tip.dart';

/// One thing to open on the catalog: a picture over a title, a subtitle and
/// how far in the student is.
///
/// It MUST be given its size, which [heightFor] answers for a width. The text
/// never gives way: its block is as tall as two lines of title and three of
/// subtitle at the reader's own text size, and the picture takes what the 3:4
/// shape leaves. Text that runs longer is cut with an ellipsis, and a hover or
/// the keyboard on the tile then says it in full.
class CatalogTile extends StatelessWidget {

  static const int _titleLines = 2;
  static const int _subtitleLines = 3;

  /// Measured from the outer edge, so the bevel's edge is inside it.
  static const EdgeInsets _padding = EdgeInsets.fromLTRB(12.5, 12.5, 12.5, 16.5);
  static const EdgeInsets _textPadding = EdgeInsets.fromLTRB(6, 12, 6, 0);
  static const double _subtitleGap = 6;
  static const double _footerGap = 8;

  /// The least the picture is given when the text is scaled up. The tile grows
  /// taller than 3:4 below it, rather than shrinking the picture away.
  static const double _panelMinHeight = 120;

  static const double _iconSize = 92;

  /// One line of a tip across a 265px tile still reads as one sentence.
  static const double _tipMaxWidth = 320;

  /// The lesson's picture. Null shows [label] in its place.
  final CourseIcon? icon;

  /// Short: the order number, or a glyph for what is not a lesson.
  final String label;

  final String title;

  /// Null when the file does not give one.
  final String? subtitle;

  /// How many steps, or how far in.
  final String meta;

  /// Everything here is done, which a badge beside [meta] says.
  final bool finished;

  /// Null while the tile cannot be opened.
  final VoidCallback? onTap;

  const CatalogTile({
    required this.label,
    required this.title,
    required this.meta,
    this.icon,
    this.subtitle,
    this.finished = false,
    this.onTap,
    super.key,
  });

  /// How tall a tile [width] wide is: 3:4, unless its text needs more.
  static double heightFor(BuildContext context, double width) =>
      math.max(width * 4 / 3, _padding.vertical + _panelMinHeight + _textBlockHeight(context));

  static TextStyle _titleStyle(BuildContext context) =>
      context.appTheme.text.h3.copyWith(fontSize: 19, height: 1.2);

  static TextStyle _subtitleStyle(BuildContext context) => context.appTheme.text.bodySmall.copyWith(
    fontSize: 13.5,
    height: 1.45,
    color: context.theme.colors.mutedForeground,
  );

  static TextStyle _metaStyle(BuildContext context) =>
      context.appTheme.text.bodySmall.copyWith(fontSize: 14, color: context.theme.colors.mutedForeground);

  /// Room for every line the tile may show, asked of the fonts at the reader's
  /// text size rather than added up from the styles' numbers.
  static double _textBlockHeight(BuildContext context) =>
      _textPadding.vertical +
      _linesHeight(context, _titleStyle(context), _titleLines) +
      _subtitleGap +
      _linesHeight(context, _subtitleStyle(context), _subtitleLines) +
      _footerGap +
      _footerHeight(context);

  static double _footerHeight(BuildContext context) =>
      math.max(CompletedBadge.size, _linesHeight(context, _metaStyle(context), 1));

  static double _linesHeight(BuildContext context, TextStyle style, int lines) {
    final painter = TextPainter(
      text: TextSpan(text: List.filled(lines, 'X').join('\n'), style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();

    return height;
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = this.subtitle;

    return ShortenedTip(
      message: [title, ?subtitle].join('\n'),
      maxWidth: _tipMaxWidth,
      child: BevelledCard(
        onPress: onTap,
        child: Padding(
          padding: _padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _buildPanel(context)),
              SizedBox(
                height: _textBlockHeight(context),
                child: Padding(
                  padding: _textPadding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: _titleLines,
                        overflow: TextOverflow.ellipsis,
                        style: _titleStyle(context),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: _subtitleGap),
                        Text(
                          subtitle,
                          maxLines: _subtitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: _subtitleStyle(context),
                        ),
                      ],
                      const Spacer(),
                      SizedBox(
                        height: _footerHeight(context),
                        child: Row(
                          children: [
                            Expanded(child: Text(meta, style: _metaStyle(context))),
                            if (finished) const CompletedBadge(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// A window onto the page, which is what an icon stands on: its outline may
  /// be the accent, so it never stands on `primary`.
  Widget _buildPanel(BuildContext context) {
    final theme = context.theme;

    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: theme.colors.background,
          shape: squircle(concentricRadius(kCardCornerRadius, inset: _padding.top)),
        ),
        child: Center(
          child: switch (icon) {
            final CourseIcon icon => DuotoneIcon(icon, size: _iconSize),
            null => Text(
              label,
              style: context.appTheme.text.code.copyWith(fontSize: 34, height: 1, color: theme.colors.foreground),
            ),
          },
        ),
      ),
    );
  }

}
