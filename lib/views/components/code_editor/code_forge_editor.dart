import 'dart:async';

import 'package:code_forge/code_forge.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/browser_menu_suppressor.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';
import 'package:i_can_code/views/components/code_editor/preempting_focus_node.dart';
import 'package:re_highlight/languages/python.dart';
import 'package:re_highlight/re_highlight.dart' show Mode;
import 'package:re_highlight/styles/atom-one-dark.dart';

/// What a [CodeForgeEditor] is drawn in. Two looks that are `==` draw the same.
typedef CodeEditorLook = ({
  TextStyle code,
  TextStyle lineNumbers,
  Color activeLineNumber,
  Color background,
  Color cursor,
  Color selection,
});

/// `code_forge`'s editor, with what it does by itself in a browser undone.
///
/// Every trick below is about `code_forge` 11.7.1, read in its source:
///
/// - **Two shortcuts reach the browser instead.** Its key handler answers every
///   key held with Ctrl (or Cmd) and Alt, for inlay hints, and on Windows that
///   is AltGr, which types `@`, `{` and `\` on many layouts. And it pastes from
///   `navigator.clipboard`, which Safari and Firefox answer with a button to
///   press on every paste. Both go to the browser, whose text arrives as input.
/// - **Cmd and an arrow move the caret the Mac's way**: to the start or end of
///   the line, or of the code. It reads Cmd as Ctrl, and its Ctrl bindings ask
///   for Ctrl itself, so Cmd+Left moved one character.
/// - **Its text input is closed while it is not focused.** It attaches one as
///   it is built, focused or not, which takes the input from whatever field
///   had it, and it never closes it. Left open, the web engine keeps the DOM
///   focus on its own input element, so keys meant for the VM's display after
///   Run were typed into the editor behind it. It attaches again on focus.
/// - **No ticker runs while it is not focused.** Its caret blinks from a
///   repeating `AnimationController` started at mount and never stopped, which
///   repaints on every frame. [TickerMode] mutes it, and its next edit sets the
///   caret back on.
/// - **It scrolls only as far as its code.** It lays its content out at least
///   as large as `MediaQuery.size`, the window, so a box of six lines could be
///   scrolled a screen down. The [MediaQuery] under it is given its own size.
/// - **Tab reaches it in the order of its box.** Its `Focus` is built inside
///   the scrolled code, so the node's rect is the whole program and reaches
///   over the controls below a box it overflows, which put Run before it in
///   reading order. A [FocusTraversalGroup] is ordered by its own box.
/// - **A new [look] or controller builds a new editor.** Its gutter and
///   selection styles are read once, at mount, and its text style and theme
///   are compared by identity, so each look's styles are built once here and a
///   change of look rebuilds it.
/// - **The browser's own menu is kept off it**, so a right click opens only its
///   own, which offers Cut, Copy and Paste in English.
///
/// Folding stays off: its fold scan is the one path into `dart:isolate`.
class CodeForgeEditor extends StatefulWidget {

  final CodeEditingController controller;

  /// MUST be the node its [focused] follows. `EscapeThenTabExit` makes both.
  final PreemptingFocusNode focusNode;

  final bool focused;

  final bool autofocus;

  final bool lineNumbers;

  /// Whether the code is coloured as Python.
  final bool highlight;

  /// Around the code. Its top scrolls away with the code, and its left is the
  /// gap between the line numbers and the code.
  final EdgeInsets padding;

  final CodeEditorLook look;

  /// Whether a focused editor's caret blinks.
  ///
  /// A blinking caret asks for a frame on every tick, so `pumpAndSettle` never
  /// returns while an editor has the keyboard. `test/flutter_test_config.dart`
  /// turns it off, as `EditableText.debugDeterministicCursor` does for a text
  /// field. Off, the editor's tickers stay muted, its caret included.
  static bool debugCaretBlinks = true;

  const CodeForgeEditor({
    required this.controller,
    required this.focusNode,
    required this.focused,
    required this.look,
    required this.padding,
    this.autofocus = false,
    this.lineNumbers = true,
    this.highlight = true,
    super.key,
  });

  /// A language with no rules, for code that is not coloured. One instance,
  /// because `code_forge` builds its highlighter again for a language that is
  /// not identical to the last, and falls back to a new one on every rebuild.
  static final Mode _plain = Mode();

  @override
  State<CodeForgeEditor> createState() => _CodeForgeEditorState();

}

class _CodeForgeEditorState extends State<CodeForgeEditor> {

  late _Styles _styles = _Styles(widget.look);

  /// Bumped with [_styles], to build a new editor for them.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _attachTo(widget.focusNode);
    _closeInputAfterMount();
  }

  @override
  void didUpdateWidget(CodeForgeEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      _detachFrom(oldWidget.focusNode);
      _attachTo(widget.focusNode);
    }
    if (oldWidget.look != widget.look) {
      _styles = _Styles(widget.look);
      _generation++;
    }
    if (oldWidget.look != widget.look || oldWidget.controller != widget.controller) _closeInputAfterMount();
  }

  @override
  void dispose() {
    _detachFrom(widget.focusNode);
    super.dispose();
  }

  void _attachTo(PreemptingFocusNode node) => node
    ..addPreempting(_passToBrowser)
    ..addPreempting(_macCaretKeys)
    ..addListener(_closeInputUnlessFocused);

  void _detachFrom(PreemptingFocusNode node) => node
    ..removePreempting(_passToBrowser)
    ..removePreempting(_macCaretKeys)
    ..removeListener(_closeInputUnlessFocused);

  void _closeInputUnlessFocused() {
    if (!widget.focusNode.hasFocus) widget.controller.connection?.close();
  }

  /// `code_forge` attaches its input in a post-frame callback of its own,
  /// which is registered after this one, so the check waits for a microtask:
  /// those run once every post-frame callback has.
  void _closeInputAfterMount() {
    if (widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      scheduleMicrotask(() {
        if (mounted) _closeInputUnlessFocused();
      });
    });
  }

  KeyEventResult _passToBrowser(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    final shortcut = keyboard.isControlPressed || keyboard.isMetaPressed;
    if (!shortcut) return KeyEventResult.ignored;

    final altGr = keyboard.isAltPressed && event.character != null;
    final paste = event.logicalKey == LogicalKeyboardKey.keyV;
    // Not handled, so the engine leaves the key to the browser.
    return altGr || paste ? KeyEventResult.skipRemainingHandlers : KeyEventResult.ignored;
  }

  KeyEventResult _macCaretKeys(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || defaultTargetPlatform != TargetPlatform.macOS) return KeyEventResult.ignored;

    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isMetaPressed || keyboard.isControlPressed || keyboard.isAltPressed) return KeyEventResult.ignored;

    final select = keyboard.isShiftPressed;
    final code = widget.controller;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowLeft:
        code.pressHomeKey(isShiftPressed: select);
      case LogicalKeyboardKey.arrowRight:
        code.pressEndKey(isShiftPressed: select);
      case LogicalKeyboardKey.arrowUp:
        code.pressDocumentHomeKey(isShiftPressed: select);
      case LogicalKeyboardKey.arrowDown:
        code.pressDocumentEndKey(isShiftPressed: select);
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => BrowserMenuSuppressor(
    child: FocusTraversalGroup(
      child: TickerMode(
        enabled: widget.focused && CodeForgeEditor.debugCaretBlinks,
        child: LayoutBuilder(
          builder: (context, constraints) => MediaQuery(
            // Less the bottom and right padding, which it adds after taking the
            // larger of this and the code.
            data: MediaQuery.of(context).copyWith(
              size: Size(constraints.maxWidth - widget.padding.right, constraints.maxHeight - widget.padding.bottom),
            ),
            child: CodeForge(
              key: ValueKey((widget.controller, _generation)),
              controller: widget.controller,
              undoController: widget.controller.undo,
              focusNode: widget.focusNode,
              autoFocus: widget.autofocus,
              language: widget.highlight ? langPython : CodeForgeEditor._plain,
              editorTheme: _styles.theme,
              textStyle: _styles.text,
              innerPadding: widget.padding,
              tabSize: widget.controller.indentSize,
              useSpaceAsTab: true,
              enableFolding: false,
              enableMinimap: false,
              enableGuideLines: false,
              enableKeyboardSuggestions: false,
              enableGutter: widget.lineNumbers,
              gutterStyle: _styles.gutter,
              selectionStyle: _styles.selection,
              scrollbarDecoration: const ScrollbarDecoration(showLineNumberIndicator: false),
            ),
          ),
        ),
      ),
    ),
  );

}

/// One look as `code_forge` takes it, built once so each part stays identical.
class _Styles {

  final TextStyle text;
  final Map<String, TextStyle> theme;
  final GutterStyle gutter;
  final CodeSelectionStyle selection;

  _Styles(CodeEditorLook look)
    : text = look.code,
      // Opaque: `code_forge` fills its gutter and the cover over an IME
      // composition with this colour, and a clear one shows the code through.
      theme = {
        ...atomOneDarkTheme,
        'root': atomOneDarkTheme['root']!.copyWith(backgroundColor: look.background),
      },
      gutter = GutterStyle(
        lineNumberStyle: look.lineNumbers,
        backgroundColor: look.background,
        activeLineNumberColor: look.activeLineNumber,
        inactiveLineNumberColor: look.lineNumbers.color,
      ),
      selection = CodeSelectionStyle(
        cursorColor: look.cursor,
        selectionColor: look.selection,
        cursorBubbleColor: look.cursor,
      );

}
