import 'package:flutter/widgets.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// Code the student **reads**: the editor's dark card, syntax-highlighted, with
/// a word in the corner naming what it is.
///
/// A worked example in a section's prose is one, and so is the program a
/// [SectionKind.predictOutput] step asks about. A [CodeEditorCard] would be
/// wrong for either: it carries a caret and a text-input connection, so it
/// invites typing into something that cannot be changed.
///
/// Drawn to [CodeEditorCard]'s own metrics, so a sample and the box the student
/// types in read as one object.
class CodeSample extends StatelessWidget {

  /// The same registry and theme the editor uses, so a sample and the student's
  /// own code are coloured alike.
  static final Highlight _highlight = Highlight()..registerLanguage('python', langPython);

  final String source;

  /// Which grammar colours it. A language with none registered — or none
  /// declared at all — is set plain rather than being an error.
  final String? language;

  /// What the corner says. Defaults to [language]'s own reader-facing name.
  ///
  /// Overridden where the sample is about to be *run*, so the corner can name
  /// the interpreter that will run it the way the editor's strip does. Without
  /// a header the code takes the header's top inset instead, so the card keeps
  /// its shape.
  final String? label;

  final TextStyle style;
  final TextStyle labelStyle;
  final Color surface;

  const CodeSample({
    required this.source,
    required this.language,
    required this.style,
    required this.labelStyle,
    required this.surface,
    this.label,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final corner = label ?? (language == null ? null : languageLabel(language!));

    return SizedBox(
      // Full width, so a one-line sample is not shrink-wrapped around its text.
      width: double.infinity,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: surface, shape: squircle(kCardCornerRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (corner case final String corner)
              Padding(
                padding: CodeEditorCard.headerPadding,
                child: Align(alignment: Alignment.centerRight, child: Text(corner, style: labelStyle)),
              ),
            Padding(
              padding: corner == null
                  ? CodeEditorCard.codePadding.copyWith(top: CodeEditorCard.headerPadding.top)
                  : CodeEditorCard.codePadding,
              // A long line scrolls rather than wrapping, which would read as
              // two statements.
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Text.rich(_highlighted(source.trimRight())),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [source], coloured — or plain when there is no grammar to colour it with.
  TextSpan _highlighted(String source) {
    if (language == null || !_highlight.listLanguages().contains(language)) {
      return TextSpan(text: source, style: style);
    }

    final renderer = TextSpanRenderer(style, atomOneDarkTheme);
    _highlight.highlight(code: source, language: language!).render(renderer);
    return renderer.span ?? TextSpan(text: source, style: style);
  }

}
