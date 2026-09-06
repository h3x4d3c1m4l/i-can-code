import 'package:flutter/widgets.dart';

/// A row of buttons that **wraps rather than overflows**.
///
/// A step's controls are the back chevron, Run and Volgende, and three of them
/// do not fit the narrower of the lesson's two columns: at the `lg` breakpoint
/// that column is 462px against a row that wants ~490. The row used to be a
/// [Row], which reports an overflow and paints the yellow bars over whatever
/// was last in it.
///
/// [Wrap] can do that because every [AppButton] is already the same height
/// whatever is in it — an icon-only one carries an empty [Text] in the label's
/// own style, so the font settles the height rather than any number stated here.
/// A [Wrap] gives its children no shared height, so that has to be true of the
/// buttons themselves; it was an [IntrinsicHeight] around a [Row] that made it
/// true before, and that could only ever equalise one line.
class AppButtonRow extends StatelessWidget {

  /// The design's gap between two buttons, and between two lines of them.
  static const double gap = 16;

  final List<Widget> children;

  const AppButtonRow({required this.children, super.key});

  @override
  Widget build(BuildContext context) => Wrap(spacing: gap, runSpacing: gap, children: children);

}
