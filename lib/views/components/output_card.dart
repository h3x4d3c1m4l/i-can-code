import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A labelled block of monospace text on the page's own light card.
///
/// What a program printed, on a lesson step or on the Tkinter page, and on a
/// predict-output step what the student said it would. The last two are drawn
/// by one widget on purpose: the whole of that step is comparing them, and a
/// prediction set differently from the output would put a difference on the
/// screen that is not in the text.
class OutputCard extends StatelessWidget {

  /// Set small and upper-cased, so it names the block without competing with it.
  final String label;

  final String? text;

  /// Drawn in place of [text], for a card that holds something other than one
  /// block of it.
  final Widget? child;

  /// A line under the text, in the warning colour, such as that the output was
  /// cut short.
  final String? note;

  const OutputCard({required String this.text, required this.label, this.note, super.key}) : child = null;

  const OutputCard.holding({required Widget this.child, required this.label, this.note, super.key}) : text = null;

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: theme.colors.card,
        shape: squircle(kCardCornerRadius, side: BorderSide(color: theme.colors.border)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: tokens.text.label.copyWith(fontSize: 12, color: theme.colors.mutedForeground),
            ),
            const SizedBox(height: 10),
            child ?? Text(text!, style: tokens.text.code.copyWith(fontSize: 15, height: 1.7)),
            if (note case final String note) ...[
              const SizedBox(height: 10),
              Text(note, style: tokens.text.bodySmall.copyWith(fontSize: 14, color: tokens.colors.warning)),
            ],
          ],
        ),
      ),
    );
  }

}
