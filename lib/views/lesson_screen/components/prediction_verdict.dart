import 'package:flutter/widgets.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/views/lesson_screen/components/lesson_prose.dart';
import 'package:i_can_code/views/lesson_screen/components/output_card.dart';
import 'package:i_can_code/views/lesson_screen/components/output_panel.dart';
import 'package:i_can_code/views/lesson_screen/components/verdict_banner.dart';

/// Whether [prediction] says the same thing the program printed.
///
/// Compared line by line, with trailing whitespace and surrounding blank lines
/// off both sides. Everything else counts: `print` separates its arguments with
/// a space and quotes nothing, so `a b` and `ab`, `42` and `"42"`, `Hallo` and
/// `hallo` are all different answers and this step is about noticing that.
///
/// The trimming is not politeness. A program's output ends in a newline the
/// student cannot deliberately type, and a text field hands back whatever the
/// keyboard left at the end of a line — neither is something they got wrong.
bool matchesPrediction(String prediction, String output) => _normalize(prediction) == _normalize(output);

/// [text] as one string again, so the comparison above is a real one: two
/// `List<String>`s are equal in Dart only when they are the same object.
String _normalize(String text) {
  final lines = text.replaceAll('\r\n', '\n').split('\n').map((line) => line.trimRight()).toList();
  while (lines.isNotEmpty && lines.first.isEmpty) {
    lines.removeAt(0);
  }
  while (lines.isNotEmpty && lines.last.isEmpty) {
    lines.removeLast();
  }
  return lines.join('\n');
}

/// The answer to a [SectionKind.predictOutput] step: whether the prediction was
/// right, and then the output itself.
///
/// **A wrong prediction still shows the output.** The surprise is the whole
/// lesson — hiding the answer to make the student guess again turns a moment of
/// "oh, that is why" into a lock, and there is nothing here being graded. The
/// prediction is read back beside it, exactly as it was written, because seeing
/// the two together is what makes the difference legible.
class PredictionVerdict extends StatelessWidget {

  /// The run that answered the question.
  final AttemptResult result;

  /// The prediction as it stood when the student asked. Held apart from the
  /// text field, so editing the box afterwards cannot rewrite a verdict that is
  /// already on the screen.
  final String prediction;

  /// Why the output is what it is, from the section's `explanation` block. Shown
  /// under the answer and to everyone, right or wrong: it is feedback, and
  /// feedback is what a practice test needs to beat re-reading. Null when the
  /// author wrote none.
  final String? explanation;

  const PredictionVerdict({
    required this.result,
    required this.prediction,
    this.explanation,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // A traceback here is the lesson's own program failing, or no runtime to
    // run it on. Neither is about the prediction, and both are already said
    // the way every other step says them.
    if (result.programError != null) return OutputPanel(result: result);

    final tokens = context.appTheme;
    final correct = matchesPrediction(prediction, result.output);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        VerdictBanner(
          background: correct ? tokens.colors.successSurface : tokens.colors.warningSurface,
          child: Text(
            correct
                ? context.localizations.lessonScreen_predictCorrect
                : context.localizations.lessonScreen_predictWrong,
            style: correct
                ? tokens.text.h3.copyWith(fontSize: 18)
                : tokens.text.body.copyWith(fontSize: 17, height: 1.5),
          ),
        ),
        // Only when they differ. Right, the two cards would hold the same text
        // twice and the second would read as a second answer.
        if (!correct) ...[
          const SizedBox(height: 16),
          OutputCard(label: context.localizations.lessonScreen_predictYours, text: prediction.trimRight()),
        ],
        const SizedBox(height: 16),
        OutputCard(
          label: context.localizations.lessonScreen_output,
          text: result.output.trimRight(),
          note: result.truncated ? context.localizations.lessonScreen_truncated : null,
        ),
        // Last, because it explains what is above it. Markdown, the way a
        // validator's message is: it is authored beside the prose and names
        // functions in the same `code` spans.
        if (explanation case final String explanation) ...[
          const SizedBox(height: 20),
          LessonProse(markdown: explanation, fontSize: 18, paragraphSpacing: 12),
        ],
      ],
    );
  }

}
