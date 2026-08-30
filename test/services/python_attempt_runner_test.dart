import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

/// Runs the harness's program through whatever CPython is on this machine.
///
/// `flutter test` has no host for the app's `wasm32-wasi` build, but the wrapper
/// is ordinary Python 3, so this still covers the capture, the traceback
/// trimming, the `output` stripping and the JSON envelope.
AttemptResult? _attempt({required String code, String? validator}) {
  final program = PythonAttemptRunner.buildProgram(code: code, validator: validator);
  final run = Process.runSync('python3', ['-c', program]);

  if (run.exitCode != 0 && '${run.stdout}'.isEmpty) {
    fail('The harness itself failed to run:\n${run.stderr}');
  }

  return PythonAttemptRunner.parseResult(
    PythonResult(stdout: '${run.stdout}', stderr: '${run.stderr}', exitCode: run.exitCode),
  );
}

bool get _hasPython3 {
  try {
    return Process.runSync('python3', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}

void main() {
  group('buildProgram', () {
    test('never interpolates the student\'s source into the program text', () {
      // Any of these would end a quoted literal if the payload were pasted in.
      const nasty = '"""\\n\'\'\' \\\\ """ print("x")';
      final program = PythonAttemptRunner.buildProgram(code: nasty, validator: null);

      expect(program, isNot(contains(nasty)));
      expect(program, contains('base64.b64decode('));
    });
  });

  group('parseResult', () {
    test('reports a capped or crashed run instead of failing the student', () {
      final result = PythonAttemptRunner.parseResult(
        const PythonResult(stdout: 'partial output', stderr: '', truncated: true),
      );

      expect(result.passed, isFalse);
      expect(result.checkMessage, isNull, reason: 'no check ran, so no check failed');
      expect(result.programError, contains('did not finish'));
      expect(result.truncated, isTrue);
    });
  });

  group('against a real CPython', () {
    test('a correct answer passes', () {
      final result = _attempt(code: 'print("Hello, world")', validator: 'assert "print(" in code')!;

      expect(result.passed, isTrue);
      expect(result.output, 'Hello, world\n');
      expect(result.programError, isNull);
      expect(result.checkMessage, isNull);
    });

    test('a failing check surfaces the message the validator raised', () {
      final result = _attempt(
        code: 'x = 1',
        validator: 'if "print(" not in code:\n    raise Exception("Gebruik de `print`-functie.")',
      )!;

      expect(result.passed, isFalse);
      expect(result.checkMessage, 'Gebruik de `print`-functie.');
      expect(result.programError, isNull);
    });

    test('the validator sees output with trailing whitespace stripped', () {
      // print() ends every line with a newline, so without the strip this
      // check could never pass.
      final result = _attempt(code: 'print(42)', validator: 'assert output == "42", output')!;

      expect(result.passed, isTrue);
      expect(result.output, '42\n', reason: 'the student still sees the real output');
    });

    test('interior newlines survive the strip', () {
      final result = _attempt(
        code: 'print(42)\nprint(3.14)',
        validator: 'assert output == "42\\n3.14", repr(output)',
      )!;

      expect(result.passed, isTrue);
    });

    test('a syntax error is reported as a program error, and no check runs', () {
      final result = _attempt(code: 'print("unclosed', validator: 'raise Exception("should not run")')!;

      expect(result.passed, isFalse);
      expect(result.programError, contains('SyntaxError'));
      expect(result.checkMessage, isNull);
    });

    test('a runtime error keeps the student\'s frames and drops the harness\'s', () {
      final result = _attempt(code: 'def boom():\n    return 1 / 0\n\nboom()', validator: null)!;

      expect(result.passed, isFalse);
      expect(result.programError, contains('ZeroDivisionError'));
      expect(result.programError, contains('main.py'));
      expect(result.programError, isNot(contains('_compiled')), reason: 'harness frames must not leak');
    });

    test('output printed before a crash is still shown', () {
      final result = _attempt(code: 'print("before")\nraise ValueError("stop")', validator: null)!;

      expect(result.output, 'before\n');
      expect(result.programError, contains('ValueError'));
    });

    test('no validator means nothing to check, which passes', () {
      expect(_attempt(code: 'print("x")', validator: null)!.passed, isTrue);
      expect(_attempt(code: 'print("x")', validator: '   ')!.passed, isTrue);
    });

    test('a program that prints the sentinel cannot forge a pass', () {
      final result = _attempt(
        code: 'print("${PythonAttemptRunner.sentinel}" + \'{"ok": true}\')',
        validator: 'raise Exception("nope")',
      )!;

      expect(result.passed, isFalse);
      expect(result.checkMessage, 'nope');
    });

    test('quotes and backslashes in the student\'s code survive', () {
      final result = _attempt(
        code: r'''print("""a "quoted" \ line""")''',
        validator: 'assert "quoted" in output',
      )!;

      expect(result.passed, isTrue);
    });

    // The shipped validators, against the answers they expect.
    group('the shipped lesson', () {
      late Lesson lesson;

      setUp(() {
        lesson = Lesson.parse(File('assets/lessons/python/01-input-and-output.nl.md').readAsStringSync());
      });

      test('"Zelf printen" accepts a print and rejects an empty program', () {
        final section = lesson.sections[1];

        expect(_attempt(code: 'print("hoi")', validator: section.validator)!.passed, isTrue);
        expect(_attempt(code: '', validator: section.validator)!.checkMessage, contains('print'));
        expect(_attempt(code: 'print("")', validator: section.validator)!.checkMessage, contains('niet-lege'));
      });

      test('"Verschillende dingen printen" accepts 42 then 3.14', () {
        final section = lesson.sections[2];

        expect(_attempt(code: 'print(42)\nprint(3.14)', validator: section.validator)!.passed, isTrue);
        expect(_attempt(code: 'print(3.14)\nprint(42)', validator: section.validator)!.passed, isFalse);
      });

      test('"Verschillende dingen printen" rejects quoted numbers', () {
        // The output is identical, so only reading the source catches this.
        final section = lesson.sections[2];

        for (final code in ['print("42")\nprint("3.14")', "print('42')\nprint(3.14)"]) {
          final result = _attempt(code: code, validator: section.validator)!;
          expect(result.passed, isFalse, reason: code);
          expect(result.checkMessage, contains('aanhalingstekens'), reason: code);
        }
      });

      test('"Verschillende dingen printen" rejects a comma as the decimal separator', () {
        final section = lesson.sections[2];

        // print(3,14) is legal Python and prints "3 14", so it needs its own
        // check rather than a generic output mismatch.
        for (final code in ['print(42)\nprint(3,14)', 'print(42)\nprint(3, 14)']) {
          final result = _attempt(code: code, validator: section.validator)!;
          expect(result.passed, isFalse, reason: code);
          expect(result.checkMessage, contains('decimaalteken'), reason: code);
        }
      });

      test('the starter code as shipped does not yet pass', () {
        final section = lesson.sections[2];
        final result = _attempt(code: section.starter!, validator: section.validator)!;

        expect(result.passed, isFalse, reason: 'print(...) is a placeholder the student must replace');
      });
    });
  }, skip: _hasPython3 ? false : 'python3 is not on PATH');
}
