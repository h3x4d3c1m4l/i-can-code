import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:i_can_code/views/components/code_editor_card.dart';
import 'package:i_can_code/views/components/code_strip_button.dart';
import 'package:i_can_code/views/components/guttered_scroll_view.dart';
import 'package:i_can_code/views/components/lesson/selectable_code.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/re_highlight.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// Code the student **reads**: the editor's dark card, syntax-highlighted, with
/// a word in the corner naming what it is and a button beside it that copies
/// the lot.
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
  /// the interpreter that will run it the way the editor's strip does.
  final String? label;

  /// Whether the code can be taken away: copied by the button, or selected.
  ///
  /// False where that would answer what the sample asks, which is the program
  /// of a [SectionKind.predictOutput] step before its output is showing. The
  /// button's place is kept either way, so nothing moves when it arrives.
  final bool copyable;

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
    this.copyable = true,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final corner = label ?? (language == null ? null : subjectLabel(language!));
    // What is shown is what is copied, and the block's own last newline is not.
    final shown = source.trimRight();
    final code = Text.rich(
      _highlighted(shown),
      selectionColor: CodeEditorCard.selectionColor(context.appTheme.colors),
    );

    return SizedBox(
      // Full width, so a one-line sample is not shrink-wrapped around its text.
      width: double.infinity,
      child: DecoratedBox(
        decoration: ShapeDecoration(color: surface, shape: squircle(kCardCornerRadius)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: CodeEditorCard.headerPadding,
              child: Row(
                children: [
                  Expanded(
                    child: corner == null
                        ? const SizedBox.shrink()
                        : Align(alignment: Alignment.centerRight, child: Text(corner, style: labelStyle)),
                  ),
                  const SizedBox(width: 12),
                  // Not `Visibility.maintain`, which would leave a hidden
                  // button in the tab order and in the semantics tree.
                  Visibility(
                    visible: copyable,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: _CopyButton(source: shown),
                  ),
                ],
              ),
            ),
            Padding(
              // The scroll view's gutter is the rest of the bottom padding, so
              // the card is as tall as the editor's.
              padding: CodeEditorCard.codePadding.copyWith(
                bottom: CodeEditorCard.codePadding.bottom - AppScrollbar.gutter,
              ),
              child: SelectableCode(
                child: ScrollConfiguration(
                  behavior: const AppScrollBehavior(surface: ScrollSurface.code),
                  // A long line scrolls rather than wrapping, which would read
                  // as two statements.
                  child: GutteredScrollView(
                    scrollDirection: Axis.horizontal,
                    // Switched off at the text and not above the scroll view,
                    // so a program scrolled sideways stays there when it turns on.
                    child: copyable ? code : SelectionContainer.disabled(child: code),
                  ),
                ),
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

/// The icon in the corner that puts the whole sample on the clipboard.
///
/// A tick stands in for it for a moment afterwards, because a copy changes
/// nothing else the reader can see.
class _CopyButton extends StatefulWidget {

  final String source;

  const _CopyButton({required this.source});

  @override
  State<_CopyButton> createState() => _CopyButtonState();

}

class _CopyButtonState extends State<_CopyButton> {

  static const Duration _confirmation = Duration(seconds: 2);

  Timer? _revert;
  bool _copied = false;

  @override
  void dispose() {
    _revert?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final view = View.of(context);
    final announcement = context.localizations.codeSample_copied;
    final direction = Directionality.of(context);

    try {
      await Clipboard.setData(ClipboardData(text: widget.source));
    } on PlatformException {
      // A browser MAY refuse the clipboard, and then there is nothing to confirm.
      return;
    }
    if (!mounted) return;

    setState(() => _copied = true);
    // The tick is a glyph, so a screen reader is told in words.
    unawaited(SemanticsService.sendAnnouncement(view, announcement, direction));
    _revert?.cancel();
    _revert = Timer(_confirmation, () => setState(() => _copied = false));
  }

  @override
  Widget build(BuildContext context) => CodeStripButton(
    icon: _copied ? FLucideIcons.check : FLucideIcons.copy,
    semanticsLabel: context.localizations.codeSample_copy,
    onPress: () => unawaited(_copy()),
  );

}
