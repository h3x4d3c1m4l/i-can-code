import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/lesson_screen/components/optional_step_banner.dart';

/// The title every step opens with, over its badge when it has one. One size
/// for all three kinds, so the steps read as one lesson.
class SectionHeading extends StatelessWidget {

  /// Every step's title, whatever kind it is.
  static const double titleSize = 34;

  final LessonSection section;

  /// Skips this step. MUST be non-null exactly when [LessonSection.optional]
  /// is set — it is what puts the "Verdieping" banner under the title.
  final VoidCallback? onSkip;

  const SectionHeading({required this.section, this.onSkip, super.key});

  @override
  Widget build(BuildContext context) {
    final style = context.appTheme.text.h2.copyWith(fontSize: titleSize);
    final title = Text.rich(
      TextSpan(
        children: [
          if (section.emoji case final String emoji)
            TextSpan(text: '$emoji ', style: TextStyle(letterSpacing: titleSize * 0.12)),
          TextSpan(text: section.title),
        ],
      ),
      style: style,
    );
    if (onSkip case final VoidCallback skip) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          title,
          // Closer to the title than the prose below is, so the badge and the
          // way past the step read as part of the heading rather than as the
          // first thing the step says.
          const SizedBox(height: 18),
          OptionalStepBanner(onSkip: skip),
        ],
      );
    }
    return title;
  }

}
