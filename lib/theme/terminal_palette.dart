import 'package:flutter/widgets.dart';
import 'package:i_can_code/theme/app_theme.dart';
import 'package:xterm/xterm.dart';

/// The sixteen ANSI colours a terminal draws with, plus the four slots xterm
/// needs around them.
///
/// Deliberately not in [AppSemanticColors]. That names roles this app has —
/// `warning`, `link`, the progress bar — and a caller picks one by meaning. These
/// are not roles: they are slots numbered 30 to 37 that whatever is running gets
/// to choose from, and CPython's colourised tracebacks are the only thing
/// choosing today. Putting them in the semantic set would invite a widget to
/// reach for `ansiRed` when it means `warning`.
///
/// One palette, not one per preset. Every preset's code surface is dark in both
/// brightnesses — `#171717` unbranded, THUAS's corporate grey and deep grey — so
/// a palette tuned for a dark background is right in all four schemes, and
/// `test/theme/terminal_palette_test.dart` holds that to WCAG AA against each of
/// them.
abstract final class AnsiPalette {

  /// Colour 0. A terminal's black cannot be black on a dark screen and still be
  /// read, so this is the darkest grey that clears AA against every code
  /// surface. Nothing in a Python session prints in it; it exists because the
  /// slot does.
  static const Color black = Color(0xFF909AA6);

  static const Color red = Color(0xFFFF6B6B);
  static const Color green = Color(0xFF5FD68A);
  static const Color yellow = Color(0xFFE9C46A);
  static const Color blue = Color(0xFF8AB4F8);
  static const Color magenta = Color(0xFFE29BE2);
  static const Color cyan = Color(0xFF6FD8D8);
  static const Color white = Color(0xFFE5E7EB);

  static const Color brightBlack = Color(0xFF9CA3AF);
  static const Color brightRed = Color(0xFFFF9A9A);
  static const Color brightGreen = Color(0xFF8FE6AE);
  static const Color brightYellow = Color(0xFFF2D98A);
  static const Color brightBlue = Color(0xFFAFCBFF);
  static const Color brightMagenta = Color(0xFFF0BCF0);
  static const Color brightCyan = Color(0xFF9DE8E8);
  static const Color brightWhite = Color(0xFFFFFFFF);

  /// Every colour, in the order a test wants to walk them.
  static const List<Color> all = <Color>[
    black, red, green, yellow, blue, magenta, cyan, white,
    brightBlack, brightRed, brightGreen, brightYellow, brightBlue, brightMagenta, brightCyan, brightWhite,
  ];

}

/// Builds xterm's theme from the app's own code surface, so the terminal is the
/// same shade of dark as a code block in a lesson.
TerminalTheme buildTerminalTheme(AppSemanticColors colors, {required Color cursor}) {
  return TerminalTheme(
    cursor: cursor,
    // Alpha rather than a flat colour: a selection has to stay readable over
    // whatever ANSI colour it happens to cover.
    selection: cursor.withValues(alpha: 0.35),
    foreground: colors.codeForeground,
    background: colors.codeBackground,
    black: AnsiPalette.black,
    red: AnsiPalette.red,
    green: AnsiPalette.green,
    yellow: AnsiPalette.yellow,
    blue: AnsiPalette.blue,
    magenta: AnsiPalette.magenta,
    cyan: AnsiPalette.cyan,
    white: AnsiPalette.white,
    brightBlack: AnsiPalette.brightBlack,
    brightRed: AnsiPalette.brightRed,
    brightGreen: AnsiPalette.brightGreen,
    brightYellow: AnsiPalette.brightYellow,
    brightBlue: AnsiPalette.brightBlue,
    brightMagenta: AnsiPalette.brightMagenta,
    brightCyan: AnsiPalette.brightCyan,
    brightWhite: AnsiPalette.brightWhite,
    searchHitBackground: AnsiPalette.yellow,
    searchHitBackgroundCurrent: AnsiPalette.brightYellow,
    searchHitForeground: colors.codeBackground,
  );
}
