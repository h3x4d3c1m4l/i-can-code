import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/app_dialog.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';
import 'package:i_can_code/views/components/code_editor/code_forge_editor.dart';
import 'package:i_can_code/views/components/code_editor/escape_then_tab_exit.dart';
import 'package:i_can_code/views/components/code_editor/preempting_focus_node.dart';
import 'package:i_can_code/views/components/code_strip_button.dart';

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

  final CodeEditingController controller;

  /// Shown at the top right — "Python klaar", a run in progress, and so on.
  final String status;

  /// How many lines the answer may run to. Null for no limit.
  ///
  /// Enforced on the controller, not by blocking Enter: a plain Enter arrives
  /// through the text-input connection rather than as a key, so no key handler
  /// sees it. A newline past the limit is undone instead.
  ///
  /// It caps the answer; it does not size the card. [height] does that, and a
  /// caller MUST keep the two in step or the last line it allows is one the
  /// student has to scroll to.
  final int? maxLines;

  /// How tall the editing area is. The design's is 276px.
  ///
  /// A fixed number, because `code_forge` scrolls in two directions and its
  /// viewport asserts on an unbounded height. Longer code scrolls inside.
  ///
  /// Null fills what the card is given, in whole lines, which is how a dialog
  /// gives way to a short window. The card MUST then be given a bounded height.
  final double? height;

  /// Whether the code is coloured as Python. Off for a file that is not a
  /// program, such as a CSV, where Python's colours mark nothing.
  final bool highlight;

  /// Whether the editor takes the keyboard when it is first built.
  final bool autofocus;

  /// The name in the strip.
  final String fileName;

  /// What the student's code started as. Shows a reset button in the strip
  /// that asks, then restores it. Null hides the button — the micro:bit and
  /// Tkinter pages share this card but have no lesson section to reset from.
  final String? starterCode;

  static const double _fontSize = 16;

  /// The code face's own line height, its ascent and descent together. MUST
  /// stay that: `code_forge` draws a line number at the top of its row with no
  /// line height of its own, so any other value sets the code above or below
  /// its number.
  static const double _lineHeight = 1.32;

  /// `code_forge` centres a line number in a gutter one font size wider than
  /// it, so 8px of that gutter lies on either side of the number. These put
  /// the number 22px from the card's edge and the code 14px after it.
  static const double _gutterInset = 14;
  static const double _codeAfterGutter = 6;
  /// The strip naming the file and the runtime. Public because a worked example
  /// in the prose is drawn to the same metrics — see `LessonProse`.
  static const EdgeInsets headerPadding = EdgeInsets.fromLTRB(22, 16, 22, 0);

  /// The code itself, below the header.
  static const EdgeInsets codePadding = EdgeInsets.fromLTRB(22, 14, 22, 24);

  /// The tint over selected code. Public because a sample's selection is drawn
  /// in the same one.
  static Color selectionColor(AppSemanticColors colors) => colors.codeForeground.withValues(alpha: 0.3);

  /// The height that fits [lines] of code exactly. Stated in lines so it does
  /// not have to be re-derived when the code font changes.
  ///
  /// A line is rounded **up** to whole pixels before it is multiplied: `16 ×
  /// 1.32` is 21.12, counted as 22. The editor keeps the fraction, so [lines]
  /// of code fit with room to spare and do not scroll.
  static double heightForLines(int lines) =>
      lines * (_fontSize * _lineHeight).ceilToDouble() + codePadding.vertical;

  const CodeEditorCard({
    required this.controller,
    required this.status,
    this.height = 276,
    this.maxLines,
    this.autofocus = true,
    this.starterCode,
    this.fileName = 'main.py',
    this.highlight = true,
    super.key,
  });

  /// The most whole lines an editing area of [height] holds, and the height
  /// that holds them. [height] itself where not even one line fits.
  static double _snappedHeight(double height) {
    final lines = ((height - codePadding.vertical) / (_fontSize * _lineHeight).ceilToDouble()).floor();
    return lines >= 1 ? heightForLines(lines) : height;
  }

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

  /// Each removal notifies, which calls [_capLines] again.
  bool _capping = false;

  /// Rejoins whatever ran past the limit. Removes the newline rather than
  /// replacing it, so pressing Enter mid-word is a true no-op.
  ///
  /// Through `replaceRange`, which keeps the caret where it was. Setting the
  /// text moves it to the end and forgets the undo history.
  void _capLines() {
    final limit = widget.maxLines;
    if (limit == null || _capping) return;

    final code = widget.controller.text;
    final extra = <int>[];
    var breaks = 0;
    for (var i = 0; i < code.length; i++) {
      if (code[i] == '\n' && ++breaks >= limit) extra.add(i);
    }
    if (extra.isEmpty) return;

    _capping = true;
    try {
      // Last first, so the offsets before it still hold.
      for (final offset in extra.reversed) {
        widget.controller.replaceRange(offset, offset + 1, '', preserveOldCursor: true);
      }
    } finally {
      _capping = false;
    }
  }

  @override
  Widget build(BuildContext context) => EscapeThenTabExit(builder: _buildCard);

  Widget _buildCard(BuildContext context, PreemptingFocusNode focusNode, bool focused) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    final muted = text.codeSmall.copyWith(color: colors.codeMuted);
    final shape = squircle(kCardCornerRadius);

    // Clipped rather than decorated, because the editor paints its own opaque
    // background to the card's edge and would square its bottom corners off.
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      clipBehavior: Clip.antiAlias,
      child: ColoredBox(
        color: colors.codeBackground,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: CodeEditorCard.headerPadding,
              child: Row(
                children: [
                  Text(widget.fileName, style: muted),
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
            if (widget.height case final double height)
              _buildEditor(context, focusNode, focused, height)
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => Align(
                    alignment: Alignment.topCenter,
                    child: _buildEditor(
                      context,
                      focusNode,
                      focused,
                      CodeEditorCard._snappedHeight(constraints.maxHeight),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(BuildContext context, PreemptingFocusNode focusNode, bool focused, double height) {
    final colors = context.appTheme.colors;
    final text = context.appTheme.text;
    // Line numbers, quieter than the code, so a traceback's "line 3" can be
    // found. A capped answer is short enough to count by eye, where a column
    // of numbers beside it is only clutter.
    final lineNumbers = widget.maxLines == null;

    return SizedBox(
      width: double.infinity,
      height: height,
      child: Padding(
        // The editor's gutter starts at its own edge. This puts the line
        // numbers where the code starts in a card without them.
        padding: EdgeInsets.only(left: lineNumbers ? CodeEditorCard._gutterInset : 0),
        child: CodeForgeEditor(
          controller: widget.controller,
          focusNode: focusNode,
          focused: focused,
          autofocus: widget.autofocus,
          lineNumbers: lineNumbers,
          highlight: widget.highlight,
          padding: CodeEditorCard.codePadding.copyWith(
            left: lineNumbers ? CodeEditorCard._codeAfterGutter : CodeEditorCard.codePadding.left,
          ),
          look: (
            code: text.code.copyWith(
              fontSize: CodeEditorCard._fontSize,
              height: CodeEditorCard._lineHeight,
              color: colors.codeForeground,
            ),
            lineNumbers: text.code.copyWith(fontSize: CodeEditorCard._fontSize, color: colors.codeMuted),
            activeLineNumber: colors.codeForeground,
            background: colors.codeBackground,
            // Both MUST come from the *code* palette: `colors.primary` is
            // near-black in the neutral preset, which on this near-black
            // surface is an invisible caret.
            cursor: colors.codeForeground,
            selection: CodeEditorCard.selectionColor(colors),
          ),
        ),
      ),
    );
  }

}

/// The icon in the strip that puts the editor back the way the exercise
/// started. Asks first: there is no undo once the student's own code is gone.
class _ResetButton extends StatelessWidget {

  final CodeEditingController controller;
  final String starterCode;

  const _ResetButton({required this.controller, required this.starterCode});

  @override
  Widget build(BuildContext context) => CodeStripButton(
    icon: FLucideIcons.rotateCcw,
    semanticsLabel: context.localizations.codeEditorCard_reset,
    onPress: () => unawaited(_confirmReset(context)),
  );

  /// Irreversible, the same reason the settings menu's "reset progress" asks
  /// first.
  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (context) => AppDialog(
        title: Text(context.localizations.resetCode_title),
        body: Text(context.localizations.resetCode_body),
        actions: [
          AppButton(
            tone: AppButtonTone.neutral,
            onPress: () => Navigator.of(context).pop(false),
            child: Text(context.localizations.common_cancel),
          ),
          AppButton(
            onPress: () => Navigator.of(context).pop(true),
            child: Text(context.localizations.resetCode_confirm),
          ),
        ],
      ),
    );

    if (confirmed ?? false) controller.text = starterCode;
  }

}
