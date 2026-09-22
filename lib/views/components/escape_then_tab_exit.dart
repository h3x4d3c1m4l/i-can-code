import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Builds the editor with [focusNode] as its own, and [focused] while it holds
/// the keyboard.
typedef EscapeThenTabBuilder = Widget Function(BuildContext context, FocusNode focusNode, bool focused);

/// Gives a `re_editor` `CodeEditor` the way out the Tkinter page's display has:
/// Escape, then Tab or Shift+Tab, moves focus to the next or previous control.
/// Tab alone still indents.
///
/// Without it the editor is a keyboard trap (WCAG 2.1.2): `re_editor` binds Tab
/// and Shift+Tab to indent and outdent, so the app's focus traversal never sees
/// either. The caller MUST state the way out while `focused` is true.
///
/// What it leans on, read in re_editor 0.10.0 and Flutter 3.47.4:
///
/// - **`CodeEditor.focusNode` is the node its own `Focus` attaches.** That
///   `Focus` passes no `onKeyEvent`, and `FocusNode.attach` keeps the handler a
///   node already has when it is given none, so the handler here survives.
/// - **The focused node's handler runs before any ancestor's.** The editor's
///   `Shortcuts`, which turn Tab into `CodeShortcutIndentIntent` and report it
///   handled, sit above its `Focus`. Returning ignored hands a key on to them,
///   which is how Tab alone still indents.
/// - **So leaving happens here**, through [FocusNode.nextFocus] and
///   [FocusNode.previousFocus], which is what the app's `NextFocusAction` and
///   `PreviousFocusAction` call, answered the way they answer. Ignoring the Tab
///   would reach the editor's `Shortcuts` first, and they would indent.
/// - **Escape is only noted.** The editor's own Escape, which clears a
///   selection, still runs after it.
/// - **Only the desktop editor binds Tab.** On Android and iOS `re_editor` builds
///   no `Shortcuts`, and Tab reaches the app's traversal by itself.
class EscapeThenTabExit extends StatefulWidget {

  final EscapeThenTabBuilder builder;

  const EscapeThenTabExit({required this.builder, super.key});

  @override
  State<EscapeThenTabExit> createState() => _EscapeThenTabExitState();

}

class _EscapeThenTabExitState extends State<EscapeThenTabExit> {

  /// Keys that do not end an Escape: Shift is part of Shift+Tab.
  static final Set<LogicalKeyboardKey> _modifiers = {
    LogicalKeyboardKey.shiftLeft,
    LogicalKeyboardKey.shiftRight,
    LogicalKeyboardKey.controlLeft,
    LogicalKeyboardKey.controlRight,
    LogicalKeyboardKey.altLeft,
    LogicalKeyboardKey.altRight,
    LogicalKeyboardKey.metaLeft,
    LogicalKeyboardKey.metaRight,
  };

  late final FocusNode _node = FocusNode(debugLabel: 'CodeEditor', onKeyEvent: _onKey);

  /// Escape was the last key pressed, so a Tab now leaves.
  bool _escapeArmed = false;

  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _node.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _node
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  void _onFocusChange() {
    _escapeArmed = false;
    if (_node.hasFocus == _focused) return;
    setState(() => _focused = _node.hasFocus);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.tab && _escapeArmed) {
      _escapeArmed = false;
      final moved = HardwareKeyboard.instance.isShiftPressed ? node.previousFocus() : node.nextFocus();
      // As NextFocusAction answers: at the end of the page the browser takes
      // the Tab, and focus goes on to its own UI.
      return moved ? KeyEventResult.handled : KeyEventResult.skipRemainingHandlers;
    }
    if (!_modifiers.contains(key)) _escapeArmed = key == LogicalKeyboardKey.escape;
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _node, _focused);

}
