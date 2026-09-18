import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

import '../support/host_python.dart';

void main() {
  group('buildProgram', () {
    test('never interpolates the student\'s source into the program text', () async {
      // Any of these would end a quoted literal if the payload were pasted in.
      const nasty = '"""\\n\'\'\' \\\\ """ print("x")';
      final program = PythonAttemptRunner.buildProgram(code: nasty, validator: null);

      expect(program, isNot(contains(nasty)));
      expect(program, contains('base64.b64decode('));
    });
  });

  group('parseResult', () {
    test('reports a capped or crashed run instead of failing the student', () async {
      final result = PythonAttemptRunner.parseResult(
        const PythonResult(stdout: 'partial output', stderr: '', truncated: true),
      );

      expect(result.passed, isFalse);
      expect(result.checkMessage, isNull, reason: 'no check ran, so no check failed');
      expect(result.programError, contains('did not finish'));
      expect(result.truncated, isTrue);
    });

    test('survives a verdict the output cap cut in half', () async {
      // The cap counts bytes, so it can land inside the envelope and leave a
      // line that opens with the sentinel and holds an unterminated JSON
      // document. Decoding that used to throw past the caller, leaving the run
      // with no result and the student with a button that spins forever.
      final result = PythonAttemptRunner.parseResult(
        PythonResult(
          stdout: 'lots of output\n${PythonAttemptRunner.sentinel}{"ok": true, "output": "aaa',
          stderr: '',
          truncated: true,
        ),
      );

      expect(result.passed, isFalse);
      expect(result.checkMessage, isNull, reason: 'a cut-off envelope is not a wrong answer');
      expect(result.programError, contains('did not finish'));
      expect(result.truncated, isTrue);
    });

    test('survives a verdict that is valid JSON but not an object', () async {
      final result = PythonAttemptRunner.parseResult(
        PythonResult(stdout: '${PythonAttemptRunner.sentinel}"cut"', stderr: '', truncated: true),
      );

      expect(result.passed, isFalse);
      expect(result.programError, contains('did not finish'));
    });
  });

  group('against a real CPython', () {
    test('a correct answer passes', () async {
      final result = await attempt(code: 'print("Hello, world")', validator: 'assert "print(" in code');

      expect(result.passed, isTrue);
      expect(result.output, 'Hello, world\n');
      expect(result.programError, isNull);
      expect(result.checkMessage, isNull);
    });

    test('a failing check surfaces the message the validator raised', () async {
      final result = await attempt(
        code: 'x = 1',
        validator: 'if "print(" not in code:\n    raise Exception("Gebruik de `print`-functie.")',
      );

      expect(result.passed, isFalse);
      expect(result.checkMessage, 'Gebruik de `print`-functie.');
      expect(result.programError, isNull);
    });

    test('the validator sees output with trailing whitespace stripped', () async {
      // print() ends every line with a newline, so without the strip this
      // check could never pass.
      final result = await attempt(code: 'print(42)', validator: 'assert output == "42", output');

      expect(result.passed, isTrue);
      expect(result.output, '42\n', reason: 'the student still sees the real output');
    });

    test('interior newlines survive the strip', () async {
      final result = await attempt(
        code: 'print(42)\nprint(3.14)',
        validator: 'assert output == "42\\n3.14", repr(output)',
      );

      expect(result.passed, isTrue);
    });

    test('a syntax error is reported as a program error, and no check runs', () async {
      final result = await attempt(code: 'print("unclosed', validator: 'raise Exception("should not run")');

      expect(result.passed, isFalse);
      expect(result.programError, contains('SyntaxError'));
      expect(result.checkMessage, isNull);
    });

    test('a runtime error keeps the student\'s frames and drops the harness\'s', () async {
      final result = await attempt(code: 'def boom():\n    return 1 / 0\n\nboom()', validator: null);

      expect(result.passed, isFalse);
      expect(result.programError, contains('ZeroDivisionError'));
      expect(result.programError, contains('main.py'));
      expect(result.programError, isNot(contains('_compiled')), reason: 'harness frames must not leak');
    });

    test('output printed before a crash is still shown', () async {
      final result = await attempt(code: 'print("before")\nraise ValueError("stop")', validator: null);

      expect(result.output, 'before\n');
      expect(result.programError, contains('ValueError'));
    });

    test('no validator means nothing to check, which passes', () async {
      expect((await attempt(code: 'print("x")', validator: null)).passed, isTrue);
      expect((await attempt(code: 'print("x")', validator: '   ')).passed, isTrue);
    });

    test('a program that prints the sentinel cannot forge a pass', () async {
      final result = await attempt(
        code: 'print("${PythonAttemptRunner.sentinel}" + \'{"ok": true}\')',
        validator: 'raise Exception("nope")',
      );

      expect(result.passed, isFalse);
      expect(result.checkMessage, 'nope');
    });

    test('quotes and backslashes in the student\'s code survive', () async {
      final result = await attempt(
        code: r'''print("""a "quoted" \ line""")''',
        validator: 'assert "quoted" in output',
      );

      expect(result.passed, isTrue);
    });

    // A section's `stdin` block. It travels on the real file descriptor rather
    // than inside the program, so this covers what a student's `input()` sees.
    group('scripted standard input', () {
      test('input() reads the line the section scripted', () async {
        final result = await attempt(code: 'print(input())', stdin: 'Sander\n');

        expect(result.output, 'Sander\n');
        expect(result.programError, isNull);
      });

      test('two reads take two lines, in order', () async {
        final result = await attempt(code: 'a = input()\nb = input()\nprint(b, a)', stdin: '1\n2\n');

        expect(result.output, '2 1\n');
      });

      test('the prompt lands in the output and the typed value does not', () async {
        // Nothing echoes it back: the input never went through a terminal. This
        // is what every validator on a step with input has to be written around,
        // so it is pinned rather than left to be rediscovered.
        final result = await attempt(code: 'naam = input("Naam? ")\nprint("Hallo", naam)', stdin: 'Sander\n');

        expect(result.output, 'Naam? Hallo Sander\n');
      });

      test('a validator sees that same output, prompt included', () async {
        final result = await attempt(
          code: 'print("Hallo", input("Naam? "))',
          validator: 'assert output == "Naam? Hallo Sander", repr(output)',
          stdin: 'Sander\n',
        );

        expect(result.passed, isTrue);
      });

      test('reading past the end of the script is the student\'s own crash', () async {
        // Not a failed check: the program stopped. An author who scripts one
        // line for an answer that reads two gets this in front of a student.
        final result = await attempt(
          code: 'a = input()\nb = input()',
          validator: 'raise Exception("should not run")',
          stdin: 'alleen een regel\n',
        );

        expect(result.passed, isFalse);
        expect(result.programError, contains('EOFError'));
        expect(result.checkMessage, isNull);
      });

      test('a section with no script gives a program that reads nothing', () async {
        final result = await attempt(code: 'print(input())');

        expect(result.programError, contains('EOFError'));
      });
    });

    // `program` reads the source as a tree. See docs/lesson-format.md.
    group('the check library', () {
      test('finds a call anywhere, and is not fooled by the name in a string', () async {
        expect(
          (await attempt(
            code: 'def groet():\n    print("hoi")\n\ngroet()',
            validator: 'assert program.calls("print")',
          )).passed,
          isTrue,
          reason: 'a call in a function body is still a call',
        );
        expect(
          (await attempt(
            code: 's = "print(42)"',
            validator: 'assert program.calls("print"), "geen print"',
          )).checkMessage,
          'geen print',
          reason: 'the substring check the library replaces would have passed this',
        );
      });

      test('with_args is exact, so it separates 42 from "42" and from 42.0', () async {
        const validator = 'assert program.calls("print").with_args(42), "print 42"';

        expect((await attempt(code: 'print(42)', validator: validator)).passed, isTrue);
        expect((await attempt(code: 'print("42")', validator: validator)).checkMessage, 'print 42');
        expect((await attempt(code: 'print(42.0)', validator: validator)).checkMessage, 'print 42');
      });

      test('with_args(anything) counts arguments, it does not count arguments seen', () async {
        // The trap in every pattern language that matches one argument at a
        // time: `print("a", b)` must not read as a call with one thing.
        const validator = 'assert program.calls("print").with_args(anything).times(1), "een ding"';

        expect((await attempt(code: 'print("a")', validator: validator)).passed, isTrue);
        expect((await attempt(code: 'print("a", "b")', validator: validator)).checkMessage, 'een ding');
      });

      test('the matchers cover text, numbers, names and nested calls', () async {
        const validator = 'assert program.calls("print").with_args(a_string, a_variable("naam")), "groet"\n'
            'assert program.calls("print").with_args(a_string, a_call(".upper")), "in hoofdletters"\n'
            'assert program.calls("print").with_args(a_call("round")), "rond af"\n'
            'assert program.calls("round").with_args(a_number, 2), "twee decimalen"\n'
            'assert program.assigns("naam").to(a_string), "bewaar een naam"\n'
            'assert not program.uses("for"), "geen lus nodig"\n';
        final result = await attempt(
          code: 'naam = "sander"\n'
              'print("Hallo", naam)\n'
              'print("Hallo", naam.upper())\n'
              'print(round(3.14159, 2))',
          validator: validator,
        );

        expect(result.passed, isTrue, reason: result.checkMessage ?? result.programError ?? '');
      });

      test('a negative literal is a number, not a unary minus over one', () async {
        final result = await attempt(
          code: 'print(-1)',
          validator: 'assert program.calls("print").with_args(-1)',
        );

        expect(result.passed, isTrue);
      });

      test('the tree sees a branch the run never took', () async {
        // The whole reason this is not another check on `output`. `input()`
        // stands in a branch that never runs because attempt() feeds no stdin,
        // which is exactly the kind of code only the tree can reach.
        final result = await attempt(
          code: 'if False:\n    naam = input("Naam? ")\nprint("wel")',
          validator: 'assert program.calls("print").times(1), "een print"\n'
              'assert program.calls("input").with_args(a_string), "vraag iets"\n',
        );

        expect(result.passed, isTrue, reason: result.checkMessage ?? result.programError ?? '');
      });

      test('an unknown construct names itself instead of quietly failing', () async {
        final result = await attempt(code: 'x = 1', validator: 'program.uses("forr")');

        expect(result.checkMessage, contains("No such construct 'forr'"));
        expect(result.checkMessage, contains('Known:'));
      });

      test('allow_only refuses everything the step has not taught', () async {
        // What an early print step wants: calls, and nothing else.
        const validator = 'program.allow_only("call")';

        expect((await attempt(code: 'print(42)\nprint(3.14)', validator: validator)).passed, isTrue);
        expect(
          (await attempt(code: '"""Mijn programma."""\nprint(42)', validator: validator)).passed,
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
            (await attempt(code: entry.key, validator: validator)).checkMessage,
            contains(entry.value),
            reason: entry.key,
          );
        }
      });

      test('allow_only widens by naming more, and a nested call stays a detail', () async {
        const validator = 'program.allow_only("call", "assignment")';

        expect((await attempt(code: 'x = round(3.14159, 2)\nprint(x)', validator: validator)).passed, isTrue);
        expect(
          (await attempt(code: 'x = 1\nif x:\n    print(x)', validator: validator)).checkMessage,
          contains('`if` is not allowed'),
        );
      });

      test('disallow bans a group, and names the earliest one written', () async {
        expect(
          (await attempt(
            code: 'while False:\n    pass\nif True:\n    pass',
            validator: 'program.disallow("control-flow")',
          )).checkMessage,
          contains('`while` is not allowed'),
          reason: 'ast.walk is breadth-first, so the message must sort by position',
        );
        expect((await attempt(code: 'print(1)', validator: 'program.disallow("loops")')).passed, isTrue);
      });

      test('a construct is found however deep it is buried', () async {
        // ast.walk is iterative, so depth costs nothing and hides nothing.
        const depth = 20;
        final buried = StringBuffer('def f():\n');
        for (var i = 0; i < depth; i++) {
          buried.write('${'    ' * (i + 1)}if True:\n');
        }
        buried.write('${'    ' * (depth + 1)}while True:\n${'    ' * (depth + 2)}pass\n');

        final result = await attempt(
          code: '${buried}print(1)',
          validator: 'program.disallow("loops")',
        );

        expect(result.checkMessage, contains('`while` is not allowed'));
      });

      test('the author\'s own message replaces the English placeholder', () async {
        final result = await attempt(
          code: 'for i in range(3):\n    print(i)',
          validator: 'program.allow_only("call", message="Los dit op zonder lus.")',
        );

        expect(result.checkMessage, 'Los dit op zonder lus.');
        expect(
          result.disallowedConstruct,
          isNull,
          reason: 'an authored message is already in the lesson\'s language',
        );
      });

      test('an unmessaged refusal travels as a name for Dart to say', () async {
        final refused = await attempt(code: 'x = 1', validator: 'program.allow_only("call")');

        expect(refused.disallowedConstruct, 'assignment');
        expect(
          refused.checkMessage,
          contains('an assignment is not allowed'),
          reason: 'the English sentence stays, for try_lesson and any other '
              'reader with no localizations',
        );

        expect(
          (await attempt(code: 'if 1:\n    print(1)', validator: 'program.disallow("if")'))
              .disallowedConstruct,
          'if',
        );
      });

      test('an ordinary failed check carries no construct', () async {
        final result = await attempt(code: 'print(1)', validator: 'raise Exception("nee")');

        expect(result.checkMessage, 'nee');
        expect(result.disallowedConstruct, isNull);
      });

      test('the library binds nothing beyond its own __all__', () async {
        // `ast` is the library's business, not a name lesson authors may lean on.
        final result = await attempt(code: 'x = 1', validator: 'ast.parse("x")');

        expect(result.checkMessage, contains('ast'));
      });
    });

    // Real validators, written the way an author writes them, against the
    // answers they expect. The suite's own lesson rather than a shipped one, so
    // the course can change without this breaking.
    group('the fixture lesson', () {
      late Lesson lesson;

      setUp(() {
        lesson = Lesson.parse(File('test/fixtures/lesson.md').readAsStringSync());
      });

      test('"Print it yourself" accepts a print and rejects an empty program', () async {
        final section = lesson.sections[1];

        expect((await attempt(code: 'print("hoi")', validator: section.validator)).passed, isTrue);
        expect((await attempt(code: '', validator: section.validator)).checkMessage, contains('print'));
        expect((await attempt(code: 'print("")', validator: section.validator)).checkMessage, contains('non-empty'));
      });

      test('"Printing different values" accepts 42 then 3.14', () async {
        final section = lesson.sections[2];

        expect((await attempt(code: 'print(42)\nprint(3.14)', validator: section.validator)).passed, isTrue);
        expect((await attempt(code: 'print(3.14)\nprint(42)', validator: section.validator)).passed, isFalse);
      });

      test('"Printing different values" rejects quoted numbers', () async {
        // The output is identical, so only reading the source catches this.
        final section = lesson.sections[2];

        for (final code in ['print("42")\nprint("3.14")', "print('42')\nprint(3.14)"]) {
          final result = await attempt(code: code, validator: section.validator);
          expect(result.passed, isFalse, reason: code);
          expect(result.checkMessage, contains('quotes'), reason: code);
        }
      });

      test('"Printing different values" rejects a comma as the decimal separator', () async {
        final section = lesson.sections[2];

        // print(3,14) is legal Python and prints "3 14", so it needs its own
        // check rather than a generic output mismatch.
        for (final code in ['print(42)\nprint(3,14)', 'print(42)\nprint(3, 14)']) {
          final result = await attempt(code: code, validator: section.validator);
          expect(result.passed, isFalse, reason: code);
          expect(result.checkMessage, contains('decimal'), reason: code);
        }
      });

      test('"Print it yourself" fences the step off at function calls', () async {
        final section = lesson.sections[1];

        // The substring check this replaced passed on the first of these and
        // could not see the second at all.
        for (final code in ['s = "print(42)"', 'naam = "Sander"\nprint(naam)']) {
          final result = await attempt(code: code, validator: section.validator);
          expect(result.passed, isFalse, reason: code);
          expect(
            result.disallowedConstruct,
            'assignment',
            reason: 'travels as a name so the app says it in the reader\'s language',
          );
        }

        expect(
          (await attempt(code: 'if True:\n    print("hoi")', validator: section.validator))
              .disallowedConstruct,
          'if',
        );
      });

      test('"Print it yourself" asks for text, which a number is not', () async {
        final section = lesson.sections[1];

        expect((await attempt(code: 'print("hoi")', validator: section.validator)).passed, isTrue);
        expect(
          (await attempt(code: 'print(42)', validator: section.validator)).checkMessage,
          contains('quotes'),
        );
      });

      test('"Printing different values" reads the quotes as a tree, not a substring', () async {
        final section = lesson.sections[2];

        // A number in a comment, or a string that merely mentions one, is not a
        // quoted number. The old `'"42"' in code` check called both mistakes.
        expect(
          (await attempt(code: 'print(42)  # not "42"\nprint(3.14)', validator: section.validator)).passed,
          isTrue,
        );
        expect(
          (await attempt(code: 'print(42)\nprint(round(3.14159, 2))', validator: section.validator)).passed,
          isTrue,
          reason: 'the value is what is asked for; how it was reached is not',
        );
      });

      test('the fixture\'s starter code does not yet pass', () async {
        final section = lesson.sections[2];
        final result = await attempt(code: section.starter!, validator: section.validator);

        expect(result.passed, isFalse, reason: 'print(...) is a placeholder the student must replace');
      });
    });
  }, skip: hasPython3 ? false : 'python3 is not on PATH');
}
