import 'package:flutter/widgets.dart';

/// A row of buttons, every one of them the height of the tallest.
///
/// An icon-only [AppButton] would otherwise come out shorter than a labelled
/// one beside it: its content is a 20px glyph where the other's is a line of
/// text, and that line's height belongs to the font rather than to any number
/// this app states. Padding the glyph to match would be guessing at Inter's
/// metrics, and would drift the moment the type scale moved.
///
/// [IntrinsicHeight] measures the tallest child and
/// [CrossAxisAlignment.stretch] gives that height to the rest, so they agree
/// whatever the font does. It costs an extra layout pass over its children,
/// which is why this is a row of buttons and not something to reach for by
/// default.
class AppButtonRow extends StatelessWidget {

  /// The design's gap between two buttons.
  static const double gap = 16;

  final List<Widget> children;

  const AppButtonRow({required this.children, super.key});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, child) in children.indexed) ...[
            if (index > 0) const SizedBox(width: gap),
            child,
          ],
        ],
      ),
    );
  }

}
