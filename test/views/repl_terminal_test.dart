import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:i_can_code/l10n/generated/app_localizations.dart';
import 'package:i_can_code/theme/theme.dart';
import 'package:i_can_code/views/components/app_button.dart';
import 'package:i_can_code/views/components/repl_terminal.dart';
import 'package:xterm/xterm.dart';

const String _leaveHint = 'Esc, dan Tab: verlaten';

/// A terminal between two buttons, under the Tab traversal `WidgetsApp` binds,
/// and everything the terminal sends to its program.
class _Harness {

  final Terminal terminal = Terminal();
  final StringBuffer sent = StringBuffer();

  _Harness() {
    terminal.onOutput = sent.write;
  }

  Widget build({bool passesCtrlA = false, TextScaler textScaler = TextScaler.noScaling}) => FTheme(
    data: buildAppTheme(),
    child: Localizations(
      locale: const Locale('nl'),
      delegates: AppLocalizations.localizationsDelegates,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: MediaQueryData(size: const Size(1000, 800), textScaler: textScaler),
          child: Shortcuts(
            shortcuts: WidgetsApp.defaultShortcuts,
            child: Actions(
              actions: WidgetsApp.defaultActions,
              child: FocusScope(
                autofocus: true,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => Column(
                        children: [
                          AppButton(onPress: () {}, child: const Text('Voor')),
                          Expanded(child: ReplTerminal(terminal: terminal, passesCtrlA: passesCtrlA)),
                          AppButton(onPress: () {}, child: const Text('Na')),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

}

/// Whether the keyboard is on something inside [finder]'s widget.
bool _focusIn(Finder finder) {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;

  final targets = finder.evaluate().toSet();
  var inside = targets.contains(focused);
  focused.visitAncestorElements((ancestor) {
    inside = targets.contains(ancestor);
    return !inside;
  });
  return inside;
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key, {bool shift = false}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.pump();
}

void main() {
  testWidgets('Tab goes to the program and the keyboard stays', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.tab);

    expect(harness.sent.toString(), '\t');
    expect(_focusIn(find.byType(TerminalView)), isTrue);
  });

  testWidgets('Escape, then Tab, moves on and sends neither', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.escape);
    await _press(tester, LogicalKeyboardKey.tab);

    expect(harness.sent.toString(), isEmpty);
    expect(_focusIn(find.widgetWithText(AppButton, 'Na')), isTrue);
  });

  testWidgets('Escape, then Shift+Tab, moves back', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.escape);
    await _press(tester, LogicalKeyboardKey.tab, shift: true);

    expect(_focusIn(find.widgetWithText(AppButton, 'Voor')), isTrue);
  });

  testWidgets('an Escape followed by any other key reaches the program ahead of it', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pump();

    await _press(tester, LogicalKeyboardKey.escape);
    expect(harness.sent.toString(), isEmpty);

    await _press(tester, LogicalKeyboardKey.arrowLeft);

    expect(harness.sent.toString(), '\x1b\x1b[D');
    expect(_focusIn(find.byType(TerminalView)), isTrue);
  });

  testWidgets('the way out is stated only while the terminal has the keyboard', (tester) async {
    final harness = _Harness();
    await tester.pumpWidget(harness.build());
    await tester.pump();

    expect(find.text(_leaveHint), findsOneWidget);

    await _press(tester, LogicalKeyboardKey.escape);
    await _press(tester, LogicalKeyboardKey.tab);

    expect(find.text(_leaveHint), findsNothing);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('the first line starts below the way out at ${scale}x text', (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(textScaler: TextScaler.linear(scale)));
      await tester.pump();

      final view = find.byType(TerminalView);
      final firstLine = tester.getTopLeft(view).dy + tester.widget<TerminalView>(view).padding!.top;
      final hint = find.ancestor(of: find.text(_leaveHint), matching: find.byType(ColoredBox)).first;

      expect(tester.getRect(hint).bottom, lessThanOrEqualTo(firstLine));
    });
  }

  group('Ctrl+A on Windows', () {
    Future<void> pressCtrlA(WidgetTester tester, {bool shift = false}) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
    }

    final windows = TargetPlatformVariant.only(TargetPlatform.windows);

    testWidgets('reaches the program when the terminal passes it on', variant: windows, (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build(passesCtrlA: true));
      await tester.pump();

      await pressCtrlA(tester);
      expect(harness.sent.toString(), '\x01');

      // Select all moves to Ctrl+Shift+A, and sends nothing.
      await pressCtrlA(tester, shift: true);
      expect(harness.sent.toString(), '\x01');
    });

    testWidgets('selects all otherwise, as xterm has it', variant: windows, (tester) async {
      final harness = _Harness();
      await tester.pumpWidget(harness.build());
      await tester.pump();

      await pressCtrlA(tester);
      expect(harness.sent.toString(), isEmpty);
    });
  });
}
