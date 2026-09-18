import 'package:flutter/widgets.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// The dark card the student writes in: a filename strip, the runtime's status,
/// and the editor itself.
///
/// Shared by a lesson's exercises and the micro:bit screen. Only the status
/// line differs between them.
class CodeEditorCard extends StatefulWidget {

  final CodeLineEditingController controller;

  /// Shown at the top right — "Python klaar", a run in progress, and so on.
  final String status;

  /// How many lines the answer may run to. Null for no limit.
  ///
  /// Enforced on the controller, not by blocking Enter: a plain Enter arrives
  /// through the text-input connection rather than `shortcutOverrideActions`, so
  /// overriding [CodeShortcutNewLineIntent] does nothing. A newline past the
  /// limit is undone instead.
  ///
  /// It caps the answer; it does not size the card. [height] does that, and a
  /// caller MUST keep the two in step or the last line it allows is one the
  /// student has to scroll to.
  final int? maxLines;

  /// How tall the editing area is. The design's is 276px.
  ///
  /// MUST be a fixed number: `re_editor` asserts on an unbounded height
  /// (`_code_field.dart:933`), and sizing it to the code with a
  /// [ValueListenableBuilder] trips `'!_dirty'` because the editor notifies its
  /// controller while building. Longer code scrolls inside.
  final double height;

  static const double _fontSize = 16;
  static const double _lineHeight = 1.6;
  /// The strip naming the file and the runtime. Public because a worked example
  /// in the prose is drawn to the same metrics — see `LessonProse`.
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(22, 16, 22, 0);

  /// The code itself, below the header.
  static const EdgeInsets codePadding = EdgeInsets.fromLTRB(22, 14, 22, 24);

  /// The height that fits [lines] of code exactly. Stated in lines so it does
  /// not have to be re-derived when the code font changes.
  ///
  /// A line is rounded **up** to whole pixels before it is multiplied, because
  /// that is what the text is laid out at: `16 × 1.6` is 25.6, drawn as 26. Two
  /// lines were 0.8px taller than the box the exact arithmetic asked for, which
  /// is invisible and is still enough for the editor to decide it can scroll and
  /// draw a scrollbar over the code.
  static double heightForLines(int lines) =>
      lines * (_fontSize * _lineHeight).ceilToDouble() + codePadding.vertical;

  const CodeEditorCard({
    required this.controller,
    required this.status,
    this.height = 276,
    this.maxLines,
    super.key,
  });

  @override
  State<CodeEditorCard> createState() => _CodeEditorCardState();

}

class _CodeEditorCardState extends State<CodeEditorCard> {

  @override
  void initState() {
    super.initState();
    if (widget.maxLines != null) widget.controller.addListener(_capLines);
  }

  @override
  void didUpdateWidget(CodeEditorCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller && oldWidget.maxLines == widget.maxLines) return;
    oldWidget.controller.removeListener(_capLines);
    if (widget.maxLines != null) widget.controller.addListener(_capLines);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_capLines);
    super.dispose();
  }

  /// Rejoins whatever ran past the limit. Removes the newline rather than
  /// replacing it, so pressing Enter mid-word is a true no-op.
  void _capLines() {
    final limit = widget.maxLines;
    if (limit == null) return;

    final lines = widget.controller.text.split('\n');
    if (lines.length <= limit) return;

    widget.controller.text = [...lines.take(limit - 1), lines.skip(limit - 1).join()].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;

    return DecoratedBox(
      decoration: ShapeDecoration(
        color: colors.codeBackground,
        shape: squircle(kCardCornerRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: CodeEditorCard.headerPadding,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('main.py', style: text.codeSmall.copyWith(color: colors.codeMuted)),
                Text(widget.status, style: text.codeSmall.copyWith(color: colors.codeMuted)),
              ],
            ),
          ),
          SizedBox(
            height: widget.height,
            child: CodeEditor(
              controller: widget.controller,
              wordWrap: false,
              padding: CodeEditorCard.codePadding,
              // Line numbers, quieter than the code, so a traceback's "line 3"
              // can be found. A capped answer is short enough to count by eye,
              // where a column of numbers beside it is only clutter.
              indicatorBuilder: widget.maxLines != null
                  ? null
                  : (context, editingController, chunkController, notifier) => Padding(
                      padding: const EdgeInsets.only(right: 14),
                      child: DefaultCodeLineNumber(
                        controller: editingController,
                        notifier: notifier,
                        textStyle: text.code.copyWith(
                          fontSize: CodeEditorCard._fontSize,
                          height: CodeEditorCard._lineHeight,
                          color: colors.codeMuted,
                        ),
                        focusedTextStyle: text.code.copyWith(
                          fontSize: CodeEditorCard._fontSize,
                          height: CodeEditorCard._lineHeight,
                          color: colors.codeForeground,
                        ),
                      ),
                    ),
              style: CodeEditorStyle(
                fontSize: CodeEditorCard._fontSize,
                fontHeight: CodeEditorCard._lineHeight,
                fontFamily: kCodeFontFamily,
                textColor: colors.codeForeground,
                backgroundColor: const Color(0x00000000),
                // Both MUST come from the *code* palette: `colors.primary` is
                // near-black in the neutral preset, which on this near-black
                // surface is an invisible caret.
                cursorColor: colors.codeForeground,
                selectionColor: colors.codeForeground.withValues(alpha: 0.3),
                codeTheme: CodeHighlightTheme(
                  languages: {'python': CodeHighlightThemeMode(mode: langPython)},
                  theme: atomOneDarkTheme,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

}
