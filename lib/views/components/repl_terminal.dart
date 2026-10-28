import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/extensions/build_context_extension.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/theme/terminal_palette.dart';
import 'package:i_can_code/views/components/app_scrollbar.dart';
import 'package:xterm/xterm.dart';

/// The terminal, dressed as one of this app's surfaces.
///
/// Only the frame is ours. Everything inside — the VT sequences CPython emits,
/// selection, scrollback, the cursor — is xterm's, because a console that only
/// understood the escape codes we happened to think of would be a console right
/// up until a lesson printed something in colour.
///
/// Shared by the browser console and the micro:bit screen. Only what is wired to
/// it differs: the micro:bit needs no line discipline, because MicroPython
/// echoes for itself.
///
/// The rounded corners have to be *clipped* rather than drawn: the terminal
/// paints its own background edge to edge, so a squircle behind it would never
/// be seen.
///
/// **Escape, then Tab or Shift+Tab, moves to the next or previous control**, and
/// the frame says so while the terminal has the keyboard. xterm sends Tab and
/// Shift+Tab to the program and reports them handled, so without it the terminal
/// is a keyboard trap (WCAG 2.1.2). What it leans on, read in xterm 4.0.0:
///
/// - **`TerminalView.onKeyEvent` runs before anything else** sees a key: its
///   shortcuts, its keytab and the text input after them.
/// - **So the Escape is held back here** until the next key, rather than only
///   noted as `EscapeThenTabExit` does. Sent on, it would reach the program as
///   the start of a sequence and take the first key typed on return with it.
///   Any key but Tab sends it after all, through `Terminal.keyInput`, which is
///   the keytab's own path, so the program still sees Escape and that key in
///   order.
class ReplTerminal extends StatefulWidget {

  final Terminal terminal;

  /// Lets the console take the keyboard as soon as the screen opens, which is
  /// the only thing anyone wants to do here.
  final bool autofocus;

  /// Hands Ctrl+A to the program on every platform, as a terminal does. xterm
  /// makes it select all on Windows, Linux and ChromeOS, so select all moves to
  /// Ctrl+Shift+A there, as in their own terminals.
  final bool passesCtrlA;

  const ReplTerminal({required this.terminal, this.autofocus = true, this.passesCtrlA = false, super.key});

  @override
  State<ReplTerminal> createState() => _ReplTerminalState();

}

class _ReplTerminalState extends State<ReplTerminal> {

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

  /// The hint's distance from the top edge, and from the first line under it.
  static const double _hintInset = 6;

  static const EdgeInsets _hintPadding = EdgeInsets.symmetric(horizontal: 6, vertical: 2);

  late final FocusNode _node = FocusNode(debugLabel: 'ReplTerminal');

  /// Escape was the last key pressed and has not been sent yet.
  bool _escapeHeld = false;

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
    _escapeHeld = false;
    if (_node.hasFocus == _focused) return;
    setState(() => _focused = _node.hasFocus);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      if (event is KeyDownEvent) _escapeHeld = true;
      return event is KeyUpEvent ? KeyEventResult.ignored : KeyEventResult.handled;
    }
    if (event is! KeyDownEvent || !_escapeHeld || _modifiers.contains(key)) return KeyEventResult.ignored;

    _escapeHeld = false;
    if (key == LogicalKeyboardKey.tab) {
      final moved = HardwareKeyboard.instance.isShiftPressed ? node.previousFocus() : node.nextFocus();
      // As NextFocusAction answers: at the end of the page the browser takes
      // the Tab, and focus goes on to its own UI.
      return moved ? KeyEventResult.handled : KeyEventResult.skipRemainingHandlers;
    }
    widget.terminal.keyInput(TerminalKey.escape);
    return KeyEventResult.ignored;
  }

  /// Room above the first line for the hint, asked of the font at the reader's
  /// text size.
  double _hintBand(TextStyle hintStyle) {
    final painter = TextPainter(
      text: TextSpan(text: 'X', style: hintStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final lineHeight = painter.height;
    painter.dispose();

    return _hintInset + _hintPadding.vertical + lineHeight + _hintInset;
  }

  Map<ShortcutActivator, Intent>? get _shortcuts {
    if (!widget.passesCtrlA) return null;
    // On a Mac select all is Cmd+A already, and nothing here matches.
    return {
      for (final MapEntry(:key, :value) in defaultTerminalShortcuts.entries)
        if (key case SingleActivator(trigger: LogicalKeyboardKey.keyA, control: true, shift: false))
          const SingleActivator(LogicalKeyboardKey.keyA, control: true, shift: true): value
        else
          key: value,
    };
  }

  @override
  Widget build(BuildContext context) {
    final appTheme = context.appTheme;
    final shape = squircle(kCardCornerRadius);
    final hintStyle = appTheme.text.codeSmall.copyWith(color: appTheme.colors.codeMuted);

    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: appTheme.colors.codeBackground, shape: shape),
        child: Stack(
          children: [
            Positioned.fill(
              // No gutter: xterm fits as many columns as its whole width holds,
              // so its scrollbar is drawn over the last one whatever it is
              // padded with.
              child: ScrollConfiguration(
                behavior: const AppScrollBehavior(surface: ScrollSurface.code),
                child: TerminalView(
                  widget.terminal,
                  focusNode: _node,
                  autofocus: widget.autofocus,
                  shortcuts: _shortcuts,
                  onKeyEvent: _onKey,
                  // The band is kept while the hint is hidden too, or every line
                  // would move when the terminal gains the keyboard. Only a band
                  // above works, because the columns ignore the side padding.
                  padding: EdgeInsets.fromLTRB(20, _hintBand(hintStyle), 20, 16),
                  theme: buildTerminalTheme(appTheme.colors, cursor: context.theme.colors.primary),
                  // Straight from the app's code style, so a line here and a
                  // line in a lesson's code block are the same type at the same
                  // size. Carries the bundled emoji fallback with it.
                  textStyle: TerminalStyle.fromTextStyle(appTheme.text.code),
                ),
              ),
            ),
            // In the band above the first line, which only output that has
            // scrolled past passes through, and clear of the scrollbar at the edge.
            if (_focused)
              Positioned(
                top: _hintInset,
                right: 24,
                child: IgnorePointer(
                  child: ColoredBox(
                    color: appTheme.colors.codeBackground,
                    child: Padding(
                      padding: _hintPadding,
                      child: Text(context.localizations.replTerminal_leaveHint, style: hintStyle),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

}
