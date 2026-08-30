import 'package:flutter/widgets.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/lesson_screen/components/code_editor_card.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// A section's prose, rendered in the app's type scale.
///
/// `flutter_markdown_plus` cannot read `context.appTheme`, so the tokens are
/// handed to a [MarkdownStyleSheet] piece by piece.
class LessonProse extends StatelessWidget {

  final String markdown;

  /// The body size. The design uses 21px on a full-width text step and 19px in
  /// the narrower column of a task.
  final double fontSize;

  /// Space under each paragraph. Zero for a single-paragraph message, where the
  /// gap would read as padding.
  final double paragraphSpacing;

  const LessonProse({
    required this.markdown,
    this.fontSize = 21,
    this.paragraphSpacing = 18,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.theme;
    final tokens = context.appTheme;
    final body = tokens.text.body.copyWith(fontSize: fontSize, height: 1.6);

    return MarkdownBody(
      data: markdown,
      styleSheet: MarkdownStyleSheet(
        p: body,
        pPadding: EdgeInsets.only(bottom: paragraphSpacing),
        h1: tokens.text.h2,
        h2: tokens.text.h3,
        h3: tokens.text.h3.copyWith(fontSize: 20),
        listBullet: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        a: body.copyWith(color: theme.colors.primary),
        // A touch smaller than the prose around it, or the line height jumps.
        code: tokens.text.code.copyWith(fontSize: fontSize - 4, color: theme.colors.foreground),
        // The card is drawn by [_CodeBlockBuilder], not here: a decoration set
        // on the sheet lands *inside* the package's own container, leaving no
        // way to put space beneath it.
        codeblockPadding: EdgeInsets.zero,
        blockquoteDecoration: ShapeDecoration(
          color: theme.colors.secondary,
          shape: squircle(kChipCornerRadius),
        ),
      ),
      // A worked example, drawn on the same dark surface as the editor.
      //
      // MUST be keyed on `pre`, not `code`: `styleSheet.code` is shared by
      // inline code, which sits on the page's light surface, and a builder keyed
      // on `code` silently never fires.
      builders: {
        'pre': _CodeBlockBuilder(
          style: tokens.text.code.copyWith(color: tokens.colors.codeForeground),
          labelStyle: tokens.text.codeSmall.copyWith(color: tokens.colors.codeMuted),
          surface: tokens.colors.codeBackground,
          trailingSpace: paragraphSpacing,
        ),
      },
    );
  }

}

class _CodeBlockBuilder extends MarkdownElementBuilder {

  /// The languages a worked example may be written in. The same registry and
  /// theme the editor uses, so a sample and the student's code match.
  static final Highlight _highlight = Highlight()..registerLanguage('python', langPython);

  /// Extra space *outside* the card, on top of the sheet's own rhythm.
  static const double _extra = 8;

  /// Without a language there is no header, so the code takes its top inset
  /// instead and the card keeps the same shape.
  static EdgeInsets get _unlabelled =>
      CodeEditorCard.codePadding.copyWith(top: CodeEditorCard.headerPadding.top);

  final TextStyle style;

  /// The language name in the card's top corner.
  final TextStyle labelStyle;

  /// The card's fill.
  final Color surface;

  /// Space left under the card.
  ///
  /// A paragraph carries its spacing *below itself* (`pPadding`), so the gap
  /// above a block is that plus the sheet's 8px `blockSpacing` while the gap
  /// below is the 8px alone. Repeating it here makes the two sides match.
  final double trailingSpace;

  /// Read in [visitElementBefore], because [visitText] is handed the code
  /// without its fence.
  String? _language;

  _CodeBlockBuilder({
    required this.style,
    required this.labelStyle,
    required this.surface,
    required this.trailingSpace,
  });

  @override
  void visitElementBefore(md.Element element) {
    // `pre > code`, with the fence's language as a class on the inner element.
    final code = element.children?.whereType<md.Element>().firstOrNull;
    final declared = code?.attributes['class'] ?? '';
    _language = declared.startsWith('language-') ? declared.substring('language-'.length) : null;
  }

  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    // Full width, so a one-line example is not shrink-wrapped around its text.
    return Padding(
      // Top is bare [_extra] because the paragraph above already contributes
      // its spacing; the bottom has to supply that itself.
      padding: EdgeInsets.only(top: _extra, bottom: trailingSpace + _extra),
      child: SizedBox(
        width: double.infinity,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: surface, shape: squircle(kCardCornerRadius)),
          // The editor card's own metrics, so an example and the box the
          // student types into look like one object.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // The corner the editor names its runtime in.
              if (_language case final String language)
                Padding(
                  padding: CodeEditorCard.headerPadding,
                  child: Align(alignment: Alignment.centerRight, child: Text(language, style: labelStyle)),
                ),
              Padding(
                padding: _language == null ? _unlabelled : CodeEditorCard.codePadding,
                // A long line scrolls rather than wrapping, which would read
                // as two statements.
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text.rich(_highlighted(text.text.trimRight())),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [source], coloured — or plain when the fence names no language, or one
  /// with no grammar registered. An unknown language is not an error.
  TextSpan _highlighted(String source) {
    if (_language == null || !_highlight.listLanguages().contains(_language)) {
      return TextSpan(text: source, style: style);
    }

    final renderer = TextSpanRenderer(style, atomOneDarkTheme);
    _highlight.highlight(code: source, language: _language!).render(renderer);
    return renderer.span ?? TextSpan(text: source, style: style);
  }

}
