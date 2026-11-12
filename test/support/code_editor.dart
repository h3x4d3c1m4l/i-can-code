import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/views/components/code_editor/code_editing_controller.dart';

/// How long the one-shot timers code_forge leaves behind an edit or a hover
/// take to run out, the longest of them 600 ms. A test that edits pumps this
/// before it ends.
const Duration codeForgeTimers = Duration(milliseconds: 650);

/// The controller of the one editor on screen.
CodeEditingController editorIn(WidgetTester tester) =>
    tester.widget<CodeForge>(find.byType(CodeForge)).controller! as CodeEditingController;

/// Types [text] at the caret a character at a time, the way the browser's text
/// input hands it to code_forge: one insertion per character. A key event
/// types nothing, Enter included.
///
/// The browser is taken to have code_forge's text, as it has once code_forge
/// has sent it. Its offsets count from the start of a window of a few lines
/// round the caret, so the code MUST be at most three lines, which that window
/// holds whole.
void typeInto(CodeForgeController controller, String text) {
  for (final character in text.characters) {
    final value = TextEditingValue(text: controller.text, selection: controller.selection);
    final offset = value.selection.baseOffset;
    // What the engine calls, and this stands in for the engine.
    // ignore: invalid_use_of_protected_member
    controller.updateEditingValueWithDeltas([
      TextEditingDeltaInsertion(
        oldText: value.text,
        textInserted: character,
        insertionOffset: offset,
        selection: TextSelection.collapsed(offset: offset + character.length),
        composing: TextRange.empty,
      ),
    ]);
  }
}
