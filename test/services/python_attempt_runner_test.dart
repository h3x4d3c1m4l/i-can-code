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

    // `program` reads the source as a tree. See docs/lesson-format.md.
    group('the check library', () {
      test('finds a call anywhere, and is not fooled by the name in a string', () {
        expect(
          _attempt(
            code: 'def groet():\n    print("hoi")\n\ngroet()',
            validator: 'assert program.calls("print")',
          )!.passed,
          isTrue,
          reason: 'a call in a function body is still a call',
        );
        expect(
          _attempt(
            code: 's = "print(42)"',
            validator: 'assert program.calls("print"), "geen print"',
          )!.checkMessage,
          'geen print',
          reason: 'the substring check the library replaces would have passed this',
        );
      });

      test('with_args is exact, so it separates 42 from "42" and from 42.0', () {
        const validator = 'assert program.calls("print").with_args(42), "print 42"';

        expect(_attempt(code: 'print(42)', validator: validator)!.passed, isTrue);
        expect(_attempt(code: 'print("42")', validator: validator)!.checkMessage, 'print 42');
        expect(_attempt(code: 'print(42.0)', validator: validator)!.checkMessage, 'print 42');
      });

      test('with_args(anything) counts arguments, it does not count arguments seen', () {
        // The trap in every pattern language that matches one argument at a
        // time: `print("a", b)` must not read as a call with one thing.
        const validator = 'assert program.calls("print").with_args(anything).times(1), "een ding"';

        expect(_attempt(code: 'print("a")', validator: validator)!.passed, isTrue);
        expect(_attempt(code: 'print("a", "b")', validator: validator)!.checkMessage, 'een ding');
      });

      test('the matchers cover text, numbers, names and nested calls', () {
        const validator = 'assert program.calls("print").with_args(a_string, a_variable("naam")), "groet"\n'
            'assert program.calls("print").with_args(a_string, a_call(".upper")), "in hoofdletters"\n'
            'assert program.calls("print").with_args(a_call("round")), "rond af"\n'
            'assert program.calls("round").with_args(a_number, 2), "twee decimalen"\n'
            'assert program.assigns("naam").to(a_string), "bewaar een naam"\n'
            'assert not program.uses("for"), "geen lus nodig"\n';
        final result = _attempt(
          code: 'naam = "sander"\n'
              'print("Hallo", naam)\n'
              'print("Hallo", naam.upper())\n'
              'print(round(3.14159, 2))',
          validator: validator,
        )!;

        expect(result.passed, isTrue, reason: result.checkMessage ?? result.programError ?? '');
      });

      test('a negative literal is a number, not a unary minus over one', () {
        final result = _attempt(
          code: 'print(-1)',
          validator: 'assert program.calls("print").with_args(-1)',
        )!;

        expect(result.passed, isTrue);
      });

      test('the tree sees a branch the run never took', () {
        // The whole reason this is not another check on `output`. `input()`
        // stands in a branch that never runs because attempt() feeds no stdin,
        // which is exactly the kind of code only the tree can reach.
        final result = _attempt(
          code: 'if False:\n    naam = input("Naam? ")\nprint("wel")',
          validator: 'assert program.calls("print").times(1), "een print"\n'
              'assert program.calls("input").with_args(a_string), "vraag iets"\n',
        )!;

        expect(result.passed, isTrue, reason: result.checkMessage ?? result.programError ?? '');
      });

      test('an unknown construct names itself instead of quietly failing', () {
        final result = _attempt(code: 'x = 1', validator: 'program.uses("forr")')!;

        expect(result.checkMessage, contains("No such construct 'forr'"));
        expect(result.checkMessage, contains('Known:'));
      });

      test('allow_only refuses everything the step has not taught', () {
        // What an early print step wants: calls, and nothing else.
        const validator = 'program.allow_only("call")';

        expect(_attempt(code: 'print(42)\nprint(3.14)', validator: validator)!.passed, isTrue);
        expect(
          _attempt(code: '"""Mijn programma."""\nprint(42)', validator: validator)!.passed,
          isTrue,
          reason: 'a docstring is not a construct a lesson teaches',
        );

        for (final entry in {
          'if True:\n    print(1)': '`if` is not allowed',
          'while False:\n    print(1)': '`while` is not allowed',
          'for i in range(3):\n    print(i)': '`for` is not allowed',
          'def f():\n    print(1)\n\nf()': '`def` is not allowed',
          'import math\nprint(1)': '`import` is not allowed',
          'x = 1\nprint(x)': 'an assignment is not allowed',
          'print(1 if True else 2)': '`if` is not allowed',
        }.entries) {
          expect(
            _attempt(code: entry.key, validator: validator)!.checkMessage,
            contains(entry.value),
            reason: entry.key,
          );
        }
      });

      test('allow_only widens by naming more, and a nested call stays a detail', () {
        const validator = 'program.allow_only("call", "assignment")';

        expect(_attempt(code: 'x = round(3.14159, 2)\nprint(x)', validator: validator)!.passed, isTrue);
        expect(
          _attempt(code: 'x = 1\nif x:\n    print(x)', validator: validator)!.checkMessage,
          contains('`if` is not allowed'),
        );
      });

      test('disallow bans a group, and names the earliest one written', () {
        expect(
          _attempt(
            code: 'while False:\n    pass\nif True:\n    pass',
            validator: 'program.disallow("control-flow")',
          )!.checkMessage,
          contains('`while` is not allowed'),
          reason: 'ast.walk is breadth-first, so the message must sort by position',
        );
        expect(_attempt(code: 'print(1)', validator: 'program.disallow("loops")')!.passed, isTrue);
      });

      test('a construct is found however deep it is buried', () {
        // ast.walk is iterative, so depth costs nothing and hides nothing.
        const depth = 20;
        final buried = StringBuffer('def f():\n');
        for (var i = 0; i < depth; i++) {
          buried.write('${'    ' * (i + 1)}if True:\n');
        }
        buried.write('${'    ' * (depth + 1)}while True:\n${'    ' * (depth + 2)}pass\n');

        final result = _attempt(
          code: '${buried}print(1)',
          validator: 'program.disallow("loops")',
        )!;

        expect(result.checkMessage, contains('`while` is not allowed'));
      });

      test('the author\'s own message replaces the English placeholder', () {
        final result = _attempt(
          code: 'for i in range(3):\n    print(i)',
          validator: 'program.allow_only("call", message="Los dit op zonder lus.")',
        )!;

        expect(result.checkMessage, 'Los dit op zonder lus.');
        expect(
          result.disallowedConstruct,
          isNull,
          reason: 'an authored message is already in the lesson\'s language',
        );
      });

      test('an unmessaged refusal travels as a name for Dart to say', () {
        final refused = _attempt(code: 'x = 1', validator: 'program.allow_only("call")')!;

        expect(refused.disallowedConstruct, 'assignment');
        expect(
          refused.checkMessage,
          contains('an assignment is not allowed'),
          reason: 'the English sentence stays, for try_lesson and any other '
              'reader with no localizations',
        );

        expect(
          _attempt(code: 'if 1:\n    print(1)', validator: 'program.disallow("if")')!
              .disallowedConstruct,
          'if',
        );
      });

      test('an ordinary failed check carries no construct', () {
        final result = _attempt(code: 'print(1)', validator: 'raise Exception("nee")')!;

        expect(result.checkMessage, 'nee');
        expect(result.disallowedConstruct, isNull);
      });

      test('the library binds nothing beyond its own __all__', () {
        // `ast` is the library's business, not a name lesson authors may lean on.
        final result = _attempt(code: 'x = 1', validator: 'ast.parse("x")')!;

        expect(result.checkMessage, contains('ast'));
      });
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

      test('"Zelf printen" fences the step off at function calls', () {
        final section = lesson.sections[1];

        // The substring check this replaced passed on the first of these and
        // could not see the second at all.
        for (final code in ['s = "print(42)"', 'naam = "Sander"\nprint(naam)']) {
          final result = _attempt(code: code, validator: section.validator)!;
          expect(result.passed, isFalse, reason: code);
          expect(
            result.disallowedConstruct,
            'assignment',
            reason: 'travels as a name so the app says it in the reader\'s language',
          );
        }

        expect(
          _attempt(code: 'if True:\n    print("hoi")', validator: section.validator)!
              .disallowedConstruct,
          'if',
        );
      });

      test('"Zelf printen" asks for text, which a number is not', () {
        final section = lesson.sections[1];

        expect(_attempt(code: 'print("hoi")', validator: section.validator)!.passed, isTrue);
        expect(
          _attempt(code: 'print(42)', validator: section.validator)!.checkMessage,
          contains('aanhalingstekens'),
        );
      });

      test('"Verschillende dingen printen" reads the quotes as a tree, not a substring', () {
        final section = lesson.sections[2];

        // A number in a comment, or a string that merely mentions one, is not a
        // quoted number. The old `'"42"' in code` check called both mistakes.
        expect(
          _attempt(code: 'print(42)  # niet "42"\nprint(3.14)', validator: section.validator)!.passed,
          isTrue,
        );
        expect(
          _attempt(code: 'print(42)\nprint(round(3.14159, 2))', validator: section.validator)!.passed,
          isTrue,
          reason: 'the value is what is asked for; how it was reached is not',
        );
      });

      test('both translations reach the same verdict on the same code', () {
        // A validator is translated alongside its prose, so the two can drift
        // into disagreeing about what passes. The messages differ; the verdict
        // must not.
        final english = Lesson.parse(
          File('assets/lessons/python/01-input-and-output.en.md').readAsStringSync(),
        );

        const answers = [
          'print("hoi")',
          'print(42)',
          '',
          'naam = "x"\nprint(naam)',
          'print(42)\nprint(3.14)',
          'print("42")\nprint("3.14")',
          'print(42)\nprint(3, 14)',
          'print(42, 3.14)',
          'print(3.14)\nprint(42)',
        ];

        for (var i = 0; i < lesson.sections.length; i++) {
          final validator = lesson.sections[i].validator;
          if (validator == null) continue;

          for (final code in answers) {
            final dutch = _attempt(code: code, validator: validator)!;
            final other = _attempt(code: code, validator: english.sections[i].validator)!;

            expect(other.passed, dutch.passed, reason: 'section $i, $code');
            expect(other.disallowedConstruct, dutch.disallowedConstruct, reason: 'section $i, $code');
          }
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
