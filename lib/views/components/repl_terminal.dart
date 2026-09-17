import 'package:flutter/widgets.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:i_can_code/theme/shape_metrics.dart';
import 'package:i_can_code/theme/terminal_palette.dart';
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
class ReplTerminal extends StatelessWidget {

  final Terminal terminal;

  /// Lets the console take the keyboard as soon as the screen opens, which is
  /// the only thing anyone wants to do here.
  final bool autofocus;

  const ReplTerminal({required this.terminal, this.autofocus = true, super.key});

  @override
  Widget build(BuildContext context) {
    final appTheme = context.appTheme;
    final shape = squircle(kCardCornerRadius);

    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: appTheme.colors.codeBackground, shape: shape),
        child: TerminalView(
          terminal,
          autofocus: autofocus,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          theme: buildTerminalTheme(appTheme.colors, cursor: context.theme.colors.primary),
          // Straight from the app's code style, so a line here and a line in a
          // lesson's code block are the same type at the same size. Carries the
          // bundled emoji fallback with it.
          textStyle: TerminalStyle.fromTextStyle(appTheme.text.code),
        ),
      ),
    );
  }

}
