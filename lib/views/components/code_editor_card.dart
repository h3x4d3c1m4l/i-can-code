import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/escape_then_tab_exit.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';

/// The dark card the student writes in: a filename strip, the runtime's status,
/// and the editor itself.
///
/// Shared by a lesson's exercises, the micro:bit screen and the Tkinter page.
/// Only the status line differs between them.
///
/// Tab indents, so the keyboard leaves with Escape then Tab, or Shift+Tab
/// backwards ([EscapeThenTabExit]), and the strip says so while the editor has
/// focus.
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

  /// Whether the editor takes the keyboard when it is first built. `re_editor`
  /// does by default.
  final bool autofocus;

  /// What the student's code started as. Shows a reset button in the strip
  /// that asks, then restores it. Null hides the button — the micro:bit and
  /// Tkinter pages share this card but have no lesson section to reset from.
  final String? starterCode;

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
    this.autofocus = true,
    this.starterCode,
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
  Widget build(BuildContext context) => EscapeThenTabExit(builder: _buildCard);

  Widget _buildCard(BuildContext context, FocusNode focusNode, bool focused) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    final muted = text.codeSmall.copyWith(color: colors.codeMuted);

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
              children: [
                Text('main.py', style: muted),
                // The way out, which WCAG 2.1.2 wants stated, the way the
                // Tkinter page's window frame states its own. Centred, so it
                // does not run into the status as one line.
                Expanded(
                  child: focused
                      ? Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            context.localizations.codeEditorCard_leaveHint,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: muted,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                Text(widget.status, style: muted),
                if (widget.starterCode case final String starterCode) ...[
                  const SizedBox(width: 12),
                  _ResetButton(controller: widget.controller, starterCode: starterCode),
                ],
              ],
            ),
          ),
          SizedBox(
            height: widget.height,
            child: CodeEditor(
              controller: widget.controller,
              focusNode: focusNode,
              autofocus: widget.autofocus,
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

/// The icon in the strip that puts the editor back the way the exercise
/// started. Asks first: there is no undo once the student's own code is gone.
class _ResetButton extends StatelessWidget {

  static const double _size = 18;

  final CodeLineEditingController controller;
  final String starterCode;

  const _ResetButton({required this.controller, required this.starterCode});

  @override
  Widget build(BuildContext context) {
    final colors = context.appTheme.colors;

    return FTappable(
      onPress: () => unawaited(_confirmReset(context)),
      semanticsButton: true,
      semanticsLabel: context.localizations.codeEditorCard_reset,
      builder: (context, states, child) => DecoratedBox(
        decoration: ShapeDecoration(
          color: states.contains(FTappableVariant.hovered)
              ? colors.codeForeground.withValues(alpha: 0.12)
              : const Color(0x00000000),
          shape: squircleOf(kChipCornerRadius, size: _size + 8),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      ),
      child: Icon(FLucideIcons.rotateCcw, size: _size, color: colors.codeMuted),
    );
  }

  /// Irreversible, the same reason the settings menu's "reset progress" asks
  /// first.
  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showFDialog<bool>(
      context: context,
      builder: (context, style, animation) => FDialog(
        animation: animation,
        builder: (context, style) => Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.localizations.resetCode_title, style: context.appTheme.text.h3),
              const SizedBox(height: 12),
              Text(
                context.localizations.resetCode_body,
                style: context.appTheme.text.bodySmall.copyWith(fontSize: 17),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppButton(
                    tone: AppButtonTone.neutral,
                    onPress: () => Navigator.of(context).pop(false),
                    child: Text(context.localizations.common_cancel),
                  ),
                  const SizedBox(width: 12),
                  AppButton(
                    onPress: () => Navigator.of(context).pop(true),
                    child: Text(context.localizations.resetCode_confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed ?? false) controller.text = starterCode;
  }

}
