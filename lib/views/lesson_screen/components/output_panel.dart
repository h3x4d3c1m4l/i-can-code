import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/app_localizations_extension.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/verdict_banner.dart';

/// What the last run produced: its verdict, then the program's output. The
/// three outcomes are drawn differently — a traceback in the code face, a failed
/// check as a sentence, a pass as a single word.
///
/// **The verdict comes first**, because it is the answer to what the student
/// pressed the button to ask, and the output below it is the evidence. A long or
/// runaway output would otherwise push the answer off the screen — and the
/// output is capped at 256 KB, so it can be very long indeed.
///
/// All three outcomes share that one slot. Moving only the failures up would put
/// the banner in a different place depending on the answer, which makes a reader
/// hunt for the one thing they are looking for.
class OutputPanel extends StatelessWidget {

  final AttemptResult result;

  const OutputPanel({required this.result, super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasVerdict) _buildVerdict(context),
        if (_hasVerdict && _hasOutput) const SizedBox(height: 16),
        if (_hasOutput) _buildOutput(context),
      ],
    );
  }

  bool get _hasVerdict => result.passed || result.programError != null || result.checkMessage != null;

  bool get _hasOutput => result.output.trim().isNotEmpty;

  Widget _buildOutput(BuildContext context) {
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
              context.localizations.lessonScreen_output.toUpperCase(),
              style: tokens.text.label.copyWith(fontSize: 12, color: theme.colors.mutedForeground),
            ),
            const SizedBox(height: 10),
            Text(
              result.output.trimRight(),
              style: tokens.text.code.copyWith(fontSize: 15, height: 1.7),
            ),
            if (result.truncated) ...[
              const SizedBox(height: 10),
              Text(
                context.localizations.lessonScreen_truncated,
                style: tokens.text.bodySmall.copyWith(fontSize: 14, color: tokens.colors.warning),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVerdict(BuildContext context) {
    final tokens = context.appTheme;

    if (result.programError case final String error) {
      // A raw traceback alone reads as the app breaking, so it is introduced
      // as a message about the student's code.
      return VerdictBanner(
        background: tokens.colors.errorSurface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.localizations.lessonScreen_crashed,
              style: tokens.text.h3.copyWith(fontSize: 17),
            ),
            const SizedBox(height: 12),
            Text(
              error.trimRight(),
              style: tokens.text.code.copyWith(fontSize: 14, height: 1.6, color: context.theme.colors.foreground),
            ),
          ],
        ),
      );
    }

    if (result.checkMessage case final String message) {
      // Markdown, not text: a validator's message is authored alongside the
      // prose and uses the same `code` spans to name a function.
      //
      // A construct a step refused arrives as a name rather than as the English
      // sentence the check library also built, so it can be said here in the
      // reader's own language. An author who wrote their own message has already
      // written it in the lesson's language, and it is used as it stands.
      final text = switch (result.disallowedConstruct) {
        final String construct => context.localizations.checkNotAllowed(construct),
        null => message,
      };

      return VerdictBanner(
        background: tokens.colors.warningSurface,
        child: LessonProse(markdown: text, fontSize: 17, paragraphSpacing: 0),
      );
    }

    return VerdictBanner(
      background: tokens.colors.successSurface,
      child: Text(
        context.localizations.lessonScreen_passed,
        style: tokens.text.h3.copyWith(fontSize: 18),
      ),
    );
  }

}
