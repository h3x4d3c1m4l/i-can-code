import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/guttered_scroll_view.dart';

/// Two columns of even width side by side, centred in a page no wider than
/// [maxWidth], each with room at its end for a scrollbar of its own.
///
/// Each column is [AppScrollbar.gutter] wider than its content. That room is
/// taken out of the [gap] and the page's right padding, so the content lands
/// where it would without it and each bar stands in whitespace rather than
/// over a column's edge. A column MUST keep its content out of that room: a
/// [GutteredScrollView] does, and a column that does not scroll pads it.
///
/// Both columns take the full height they are given, which is what gives each
/// one a viewport to scroll inside.
class SplitPage extends StatelessWidget {

  final double maxWidth;

  /// Either side of the columns. Its right MUST be at least
  /// [AppScrollbar.gutter], and it MUST have no top or bottom: a column's
  /// vertical padding belongs inside its scroll view, so that what is scrolled
  /// past still passes under the bar.
  final EdgeInsets padding;

  /// Between the columns' content. MUST be at least [AppScrollbar.gutter].
  final double gap;

  final Widget left;
  final Widget right;

  const SplitPage({
    required this.maxWidth,
    required this.padding,
    required this.gap,
    required this.left,
    required this.right,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    const gutter = AppScrollbar.gutter;
    assert(padding.top == 0 && padding.bottom == 0, 'A column pads its own top and bottom.');
    assert(padding.right >= gutter && gap >= gutter, 'No room to take the gutter from.');

    // The page grows to the right by one gutter and its right padding shrinks
    // by as much, so the page is centred as before and its left edge stays put.
    return Padding(
      padding: padding.copyWith(right: padding.right - gutter),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + gutter),
          // Even halves. `Expanded.flex` is an integer ratio against a default
          // of 1, so `flex: 11` would be an 11:1 split, not 1:1.1.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: left),
              SizedBox(width: gap - gutter),
              Expanded(child: right),
            ],
          ),
        ),
      ),
    );
  }

}
