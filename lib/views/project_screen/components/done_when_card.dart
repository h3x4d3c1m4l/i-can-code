import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/lesson/lesson_prose.dart';

/// What a task looks like once it works, and the button that says it does.
///
/// One card for both, so the last thing read before claiming a task is what
/// claiming it means. The card is drawn wherever the `done-when` block sat in
/// the file: always at the end of the task.
class DoneWhenCard extends StatelessWidget {

  /// The task's `done-when` block. Inline markdown.
  final String text;

  /// The row under the text. Null for a task already finished, which is read
  /// back and not claimed again.
  final Widget? action;

  const DoneWhenCard({required this.text, this.action, super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final action = this.action;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.successSurface,
        shape: squircle(kCardCornerRadius, side: BorderSide(color: colors.success, width: 2)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(FLucideIcons.circleCheckBig, size: 20, color: colors.success),
                const SizedBox(width: 10),
                Text(context.localizations.projectScreen_doneWhen, style: context.appTheme.text.h3),
              ],
            ),
            const SizedBox(height: 10),
            LessonProse(markdown: text, fontSize: 18, paragraphSpacing: 10),
            if (action != null) ...[const SizedBox(height: 18), action],
          ],
        ),
      ),
    );
  }

}
