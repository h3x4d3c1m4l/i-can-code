import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';

/// A labelled block of monospace text on the page's own light card.
///
/// What a program printed, and — on a [SectionKind.predictOutput] step — what
/// the student said it would. The two are drawn by one widget on purpose: the
/// whole of that step is comparing them, and a prediction set differently from
/// the output would put a difference on the screen that is not in the text.
class OutputCard extends StatelessWidget {

  /// Set small and upper-cased, so it names the block without competing with it.
  final String label;

  final String text;

  /// A line under the text, in the warning colour — that the output was cut
  /// short, and nothing else so far.
  final String? note;

  const OutputCard({required this.label, required this.text, this.note, super.key});

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
            Text(text, style: tokens.text.code.copyWith(fontSize: 15, height: 1.7)),
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
