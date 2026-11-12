import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/views/components/code_editor/preempting_focus_node.dart';

/// Builds the editor with [focusNode] as its own, and [focused] while it holds
/// the keyboard.
typedef EscapeThenTabBuilder = Widget Function(BuildContext context, PreemptingFocusNode focusNode, bool focused);

/// Gives a `code_forge` editor the way out the Tkinter page's display has:
/// Escape, then Tab or Shift+Tab, moves focus to the next or previous control.
/// Tab alone still indents.
///
/// Without it the editor is a keyboard trap (WCAG 2.1.2): `code_forge` indents
/// on Tab and outdents on Shift+Tab, on every platform, so the app's focus
/// traversal never sees either. The caller MUST state the way out while
/// `focused` is true.
///
/// What it leans on, read in code_forge 11.7.1 and Flutter 3.50.0:
///
/// - **The editor's own `Focus` is built on [focusNode]**, and its key handler
///   answers Tab, Shift+Tab and Escape as handled. The node is a
///   [PreemptingFocusNode], so the handler here runs before that one.
/// - **So leaving happens here**, through [FocusNode.nextFocus] and
///   [FocusNode.previousFocus], which is what the app's `NextFocusAction` and
///   `PreviousFocusAction` call, answered the way they answer. Ignoring the Tab
///   hands it on to the editor, which indents.
/// - **Escape is only noted.** The editor's own Escape, which closes its
///   popups and its extra cursors, still runs after it.
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

  late final PreemptingFocusNode _node = PreemptingFocusNode(debugLabel: 'CodeEditor', preempt: [_onKey]);

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
