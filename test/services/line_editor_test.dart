import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/terminal/line_editor.dart';

/// Drives a [LineEditor] and records everything it did.
class _Harness {

  final StringBuffer echoed = StringBuffer();
  final List<String> submitted = <String>[];
  int endedInput = 0;
  int interrupted = 0;
  bool canDiscard = true;

  late final LineEditor editor = LineEditor(
    echo: echoed.write,
    submit: submitted.add,
    endOfInput: () => endedInput++,
    interrupt: () => interrupted++,
    canDiscardLine: () => canDiscard,
  );

  void type(String data) => editor.write(data);

}

void main() {
  group('typing', () {
    test('a line is submitted with the newline the interpreter waits for', () {
      final harness = _Harness()..type('x = 1\r');

      expect(harness.submitted, ['x = 1\n']);
      expect(harness.editor.line, isEmpty);
    });

    test('nothing is submitted until Enter', () {
      final harness = _Harness()..type('x = 1');

      expect(harness.submitted, isEmpty);
      expect(harness.editor.line, 'x = 1');
    });

    test('what is typed is echoed, because the interpreter does not echo it', () {
      final harness = _Harness()..type('hi');

      expect(harness.echoed.toString(), contains('hi'));
    });

    test('a pasted block submits every line it holds', () {
      final harness = _Harness()..type('a = 1\nb = 2\n');

      expect(harness.submitted, ['a = 1\n', 'b = 2\n']);
    });

    test('control characters are not typed into the line', () {
      // \x00 is not printable and must not end up in the buffer.
      final harness = _Harness()..type('a\x00b');

      expect(harness.editor.line, 'ab');
    });
  });

  group('editing', () {
    test('backspace removes the character before the cursor', () {
      final harness = _Harness()..type('cat\x7f');

      expect(harness.editor.line, 'ca');
    });

    test('backspace on an empty line does nothing', () {
      final harness = _Harness()..type('\x7f');

      expect(harness.editor.line, isEmpty);
    });

    test('the cursor moves left and text is inserted where it is', () {
      final harness = _Harness()
        ..type('ac')
        ..type('\x1b[D')
        ..type('b');

      expect(harness.editor.line, 'abc');
    });

    test('Delete removes the character under the cursor', () {
      final harness = _Harness()
        ..type('abc')
        ..type('\x1b[D')
        ..type('\x1b[3~');

      expect(harness.editor.line, 'ab');
    });

    test('Ctrl-U clears the line', () {
      final harness = _Harness()..type('nonsense\x15');

      expect(harness.editor.line, isEmpty);
    });

    test('Ctrl-W deletes the word before the cursor', () {
      final harness = _Harness()..type('print hello\x17');

      expect(harness.editor.line, 'print ');
    });

    test('Home and End move to the ends of the line', () {
      final harness = _Harness()
        ..type('bc')
        ..type('\x1b[H')
        ..type('a')
        ..type('\x1b[F')
        ..type('d');

      expect(harness.editor.line, 'abcd');
    });

    test('an escape sequence split across two writes is not typed as text', () {
      final harness = _Harness()
        ..type('ab')
        ..type('\x1b')
        ..type('[D');

      // The half-sequence is held rather than printed. What matters is that no
      // stray bracket reaches the line.
      expect(harness.editor.line, 'ab');
    });
  });

  group('history', () {
    test('the previous line comes back on arrow up', () {
      final harness = _Harness()
        ..type('first\r')
        ..type('\x1b[A');

      expect(harness.editor.line, 'first');
    });

    test('arrow down returns what was being typed', () {
      final harness = _Harness()
        ..type('first\r')
        ..type('half typed')
        ..type('\x1b[A')
        ..type('\x1b[B');

      expect(harness.editor.line, 'half typed');
    });

    test('a repeated line is only remembered once', () {
      final harness = _Harness()
        ..type('same\r')
        ..type('same\r')
        ..type('\x1b[A')
        ..type('\x1b[A');

      // Two steps back over a one-entry history stays on that entry.
      expect(harness.editor.line, 'same');
    });

    test('a blank line is not remembered', () {
      final harness = _Harness()
        ..type('kept\r')
        ..type('\r')
        ..type('\x1b[A');

      expect(harness.editor.line, 'kept');
    });
  });

  group('Ctrl-C', () {
    test('at a prompt it throws away the line without submitting it', () {
      final harness = _Harness()..type('oops\x03');

      expect(harness.editor.line, isEmpty);
      expect(harness.submitted, isEmpty);
      expect(harness.interrupted, 0);
    });

    test('it does not claim a KeyboardInterrupt the interpreter never raised', () {
      final harness = _Harness()..type('oops\x03');

      expect(harness.echoed.toString(), isNot(contains('KeyboardInterrupt')));
    });

    test('while the interpreter is busy it is the caller\'s problem', () {
      final harness = _Harness()
        ..canDiscard = false
        ..type('\x03');

      expect(harness.interrupted, 1);
    });

    test('part way through a block it is the caller\'s problem too', () {
      // Clearing the line would leave `for ...:` open with no way out.
      final harness = _Harness()
        ..canDiscard = false
        ..type('    print(i)\x03');

      expect(harness.interrupted, 1);
      expect(harness.editor.line, '    print(i)');
    });
  });

  group('Ctrl-D', () {
    test('on an empty line it ends input', () {
      final harness = _Harness()..type('\x04');

      expect(harness.endedInput, 1);
    });

    test('with something typed it does nothing, so a session is not lost by accident', () {
      final harness = _Harness()..type('x\x04');

      expect(harness.endedInput, 0);
      expect(harness.editor.line, 'x');
    });
  });

  group('cookOutput', () {
    test('a bare newline gets the carriage return a terminal needs', () {
      expect(cookOutput('a\nb'), 'a\r\nb');
    });

    test('an existing carriage return is not doubled', () {
      expect(cookOutput('a\r\nb'), 'a\r\nb');
    });

    test('text without newlines is untouched', () {
      expect(cookOutput('>>> '), '>>> ');
    });
  });
}
