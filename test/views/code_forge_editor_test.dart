import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';
import 'package:i_can_code/views/components/code_editor/code_forge_editor.dart';
import 'package:i_can_code/views/components/code_editor/escape_then_tab_exit.dart';

import '../support/code_editor.dart';

const CodeEditorLook _look = (
  code: TextStyle(fontSize: 16, height: 1.6, color: Color(0xFFFFFFFF)),
  lineNumbers: TextStyle(fontSize: 16, color: Color(0xFF888888)),
  activeLineNumber: Color(0xFFFFFFFF),
  background: Color(0xFF000000),
  cursor: Color(0xFFFFFFFF),
  selection: Color(0x55FFFFFF),
);

/// The editor in a box of its own, with the node and the focus
/// `EscapeThenTabExit` gives it in the app.
Widget _editor(CodeEditingController code, {CodeEditorLook look = _look}) => Directionality(
  textDirection: TextDirection.ltr,
  child: MediaQuery(
    data: const MediaQueryData(size: Size(800, 600)),
    child: FocusScope(
      autofocus: true,
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 400,
          height: 200,
          child: EscapeThenTabExit(
            builder: (context, focusNode, focused) => CodeForgeEditor(
              controller: code,
              focusNode: focusNode,
              focused: focused,
              look: look,
              padding: const EdgeInsets.all(8),
            ),
          ),
        ),
      ),
    ),
  ),
);

void main() {
  late CodeEditingController code;

  setUp(() => code = CodeEditingController(text: 'print(1)'));
  tearDown(() => code.dispose());

  /// The editor, with the keyboard in it.
  Future<void> focus(WidgetTester tester) async {
    await tester.pumpWidget(_editor(code));
    await tester.tap(find.byType(CodeForge));
    await tester.pump();
  }

  testWidgets('asks for frames only while it has the keyboard', (tester) async {
    // The VM pages hold that a running program leaves the page still, and a
    // caret that blinks on its own would not.
    CodeForgeEditor.debugCaretBlinks = true;
    addTearDown(() => CodeForgeEditor.debugCaretBlinks = false);

    await tester.pumpWidget(_editor(code));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'an editor nobody is typing in');

    await tester.tap(find.byType(CodeForge));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.binding.hasScheduledFrame, isTrue, reason: 'its caret blinks');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(codeForgeTimers);
    expect(tester.binding.hasScheduledFrame, isFalse, reason: 'and stops when the keyboard leaves');
  });

  testWidgets('leaves a character typed with AltGr to the browser', (tester) async {
    await focus(tester);

    // Windows reports AltGr as Ctrl and Alt, which the editor would swallow.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altRight);
    final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyQ, character: '@');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(handled, isFalse);
    await tester.pump(codeForgeTimers);
  });

  testWidgets('leaves the paste shortcut to the browser', (tester) async {
    await focus(tester);

    for (final modifier in [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft]) {
      await tester.sendKeyDownEvent(modifier);
      final handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(modifier);

      expect(handled, isFalse, reason: '$modifier: the browser pastes without asking for the clipboard');
    }
    expect(code.text, 'print(1)');
    await tester.pump(codeForgeTimers);
  });

  testWidgets('closes a bracket that is typed, and not a quote', (tester) async {
    code.text = '';
    await focus(tester);

    typeInto(code, 'print("zo\'n auto")');
    await tester.pump(codeForgeTimers);

    // The ( was closed for the student, and typing ) stepped over it.
    expect(code.text, 'print("zo\'n auto")');
  });

  testWidgets('forgets what could be undone when its text is set', (tester) async {
    await focus(tester);
    typeInto(code, 'x');
    await tester.pump(codeForgeTimers);
    expect(code.undo.canUndo, isTrue);

    code.text = 'print("start")';

    expect(code.undo.canUndo, isFalse, reason: 'its offsets belong to text that is gone');
    await tester.pump(codeForgeTimers);
  });

  testWidgets('builds a new editor for a new look, and keeps it for the same one', (tester) async {
    await tester.pumpWidget(_editor(code));
    final first = tester.state(find.byType(CodeForge));

    // An equal look, built anew, as every rebuild of the card does.
    await tester.pumpWidget(_editor(code, look: (
      code: _look.code.copyWith(),
      lineNumbers: _look.lineNumbers,
      activeLineNumber: _look.activeLineNumber,
      background: _look.background,
      cursor: _look.cursor,
      selection: _look.selection,
    )));
    expect(tester.state(find.byType(CodeForge)), same(first));

    const cursor = Color(0xFFFFCC00);
    await tester.pumpWidget(_editor(code, look: (
      code: _look.code,
      lineNumbers: _look.lineNumbers,
      activeLineNumber: _look.activeLineNumber,
      background: _look.background,
      cursor: cursor,
      selection: _look.selection,
    )));
    expect(tester.state(find.byType(CodeForge)), isNot(same(first)), reason: 'it reads its styles once');
    expect(tester.widget<CodeForge>(find.byType(CodeForge)).selectionStyle!.cursorColor, cursor);
  });
}
