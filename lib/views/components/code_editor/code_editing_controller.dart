import 'package:code_forge/code_forge.dart';
import 'package:flutter/services.dart';

/// The program in a [CodeEditorCard]: its text, its undo history and how far
/// a Tab indents it.
///
/// Changes two things about `code_forge`'s controller, read in 11.7.1:
///
/// - **A typed quote is not paired.** `_handleInsertion` pairs `'` and `"` the
///   way it pairs brackets, inside a word too, so `zo'n` came out as `zo'n'`.
///   A one-quote insertion is put in through `replaceRange` instead, which
///   inserts what it is given. Brackets are still paired.
/// - **Setting [text] clears the undo history.** `code_forge` neither records
///   that change nor forgets what came before it, so an undo after a reset
///   applied old offsets to the new text.
class CodeEditingController extends CodeForgeController {

  /// Spaces per indent step. A caller passes `subjectIndentSize`; the default
  /// is the 2 the editor used before it was told anything.
  final int indentSize;

  /// The history the editor undoes from. [CodeEditorCard] hands it to the
  /// editor, so it outlives a rebuilt editor the way the text does.
  final UndoRedoController undo = UndoRedoController();

  static const Set<String> _quotes = {"'", '"'};

  CodeEditingController({String text = '', this.indentSize = 2}) {
    if (text.isNotEmpty) this.text = text;
  }

  @override
  set text(String value) {
    super.text = value;
    undo.clear();
  }

  @override
  void updateEditingValueWithDeltas(List<TextEditingDelta> textEditingDeltas) {
    var from = 0;
    for (final (index, delta) in textEditingDeltas.indexed) {
      if (!_isTypedQuote(delta)) continue;
      if (index > from) super.updateEditingValueWithDeltas(textEditingDeltas.sublist(from, index));
      _type((delta as TextEditingDeltaInsertion).textInserted);
      from = index + 1;
    }
    if (from < textEditingDeltas.length) super.updateEditingValueWithDeltas(textEditingDeltas.sublist(from));
  }

  /// One quote typed outside an IME composition, which goes another way in
  /// `code_forge` and is left to it.
  bool _isTypedQuote(TextEditingDelta delta) =>
      delta is TextEditingDeltaInsertion &&
      _quotes.contains(delta.textInserted) &&
      !(delta.composing.isValid && !delta.composing.isCollapsed) &&
      !isComposingActive;

  /// Puts [text] in place of the selection, at `code_forge`'s own caret. Its
  /// insertion places a typed character there too, and not at the offset the
  /// engine names, which can lag behind its auto-indent.
  void _type(String text) {
    if (readOnly) return;
    replaceRange(selection.start, selection.end, text);
  }

}
