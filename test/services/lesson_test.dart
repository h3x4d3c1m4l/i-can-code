import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course_icon.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

void main() {
  group('Lesson.parse', () {
    // The samples are documentation, so they are not bundled and no student ever
    // sees them — but a sample that no longer parses is worse than none, and
    // `docs/lesson-format.md` points authors straight at them.
    group('the samples in docs/samples', () {
      final files = Directory('docs/samples')
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.md') && !file.path.endsWith('README.md'))
          .toList();

      test('there are some', () => expect(files, isNotEmpty));

      for (final file in files) {
        test(file.uri.pathSegments.last, () {
          final lesson = Lesson.parse(file.readAsStringSync());

          expect(lesson.id, isNotEmpty);
          expect(lesson.title, isNotEmpty);
          expect(lesson.icon, isNotNull);
          expect(lesson.sections, isNotEmpty);
          for (final section in lesson.sections) {
            expect(section.id, isNotEmpty, reason: 'every section needs a stable id');
            expect(section.emoji, isNotNull, reason: '${section.title} shows what an authored step looks like');
          }
        });
      }

      test('one shows every section type there is', () {
        // What makes this more than a parse check: a new SectionKind with no
        // sample beside it fails here rather than going undocumented.
        final kinds = files
            .expand((file) => Lesson.parse(file.readAsStringSync()).sections)
            .map((section) => section.kind)
            .toSet();

        expect(kinds, unorderedEquals(SectionKind.values));
      });
    });

    test('code blocks come through unescaped, ready to run', () {
      final lesson = Lesson.parse(File('test/fixtures/lesson.md').readAsStringSync());
      final validators = lesson.sections.map((s) => s.validator).nonNulls;

      expect(validators, isNotEmpty);
      // What `encodeHtml: false` buys: the markdown package would otherwise hand
      // CPython `print(&quot;hi&quot;)`, which fails at runtime rather than here.
      // Both quote forms, because a validator uses whichever the message needs.
      expect(validators.every((v) => !v.contains('&quot;') && !v.contains('&#39;')), isTrue);
      expect(validators.first, contains('"'));
      expect(validators.first, contains("'"));
      expect(validators.any((v) => v.contains(r'\n')), isTrue, reason: 'nor is a backslash eaten');
    });

    group('a runtime this version cannot run', () {
      // What a course may already carry: a window step, which the lesson screen
      // cannot show and the harness cannot check yet. It is left out, and
      // nothing about it is read, so an unknown type and unknown blocks in it
      // are not a parse error.
      const windowStep =
          '## Een venster\n\n'
          '```metadata\n'
          'id: window\n'
          'runtime: tkinter\n'
          'type: window-exercise\n'
          '```\n\n'
          '```python-window\n'
          'root.mainloop()\n'
          '```\n';

      test('is left out of the lesson, with the steps around it kept', () {
        final lesson = Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n'
          '## Lezen\n\n```metadata\nid: read\ntype: info\n```\n\nprose\n\n'
          '$windowStep\n'
          '## Nog lezen\n\n```metadata\nid: more\ntype: info\n```\n\nprose\n',
        );

        expect(lesson.sections.map((section) => section.id), ['read', 'more']);
        expect(lesson.runtime, LessonRuntime.python);
      });

      test('declared by the whole lesson leaves it with no steps, and that is not an error', () {
        final lesson = Lesson.parse('# T\n\n```metadata\nid: x\nruntime: tkinter\n```\n\n$windowStep');

        expect(lesson.runtime, LessonRuntime.tkinter);
        expect(lesson.sections, isEmpty);
        expect(lesson.id, 'x', reason: 'the lesson still parses, so the course can leave it out');
      });

      test('a step may still opt back in to a runtime the app can run', () {
        final lesson = Lesson.parse(
          '# T\n\n```metadata\nid: x\nruntime: tkinter\n```\n\n'
          '## Lezen\n\n```metadata\nid: read\nruntime: python\ntype: info\n```\n\nprose\n',
        );

        expect(lesson.sections.map((section) => section.id), ['read']);
      });

      test('a lesson with no steps at all is still an error', () {
        expect(() => Lesson.parse('# T\n\n```metadata\nid: x\n```\n'), throwsA(isA<FormatException>()));
      });

      test('a runtime no version has is an author\'s mistake', () {
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\nruntime: basic\n```\n\n$windowStep'),
          throwsA(isA<FormatException>()),
        );
      });

      test('is the machine outside a project, and nothing else', () {
        expect(LessonRuntime.tkinter.readyIn(LessonLayout.steps), isFalse);
        expect(LessonRuntime.tkinter.readyIn(LessonLayout.project), isTrue, reason: 'a project runs windows');
        expect(LessonRuntime.python.readyIn(LessonLayout.steps), isTrue);
        expect(LessonRuntime.microbit.readyIn(LessonLayout.project), isTrue);
      });
    });

    group('a project', () {
      const head = '# T\n\n```metadata\nid: x\nlayout: project\nruntime: microbit\n```\n\n';
      const info = '## Lezen\n\n```metadata\nid: read\ntype: info\n```\n\nprose\n\n';
      String task(String id, {String extra = '', String blocks = ''}) =>
          '## $id\n\n```metadata\nid: $id\ntype: task\n$extra```\n\nprose\n\n'
          '```done-when\nHet lampje brandt.\n```\n\n$blocks';
      const starter = '```python-assignment\nfrom microbit import *\n```\n\n';

      test('reads its tasks, what each is done when and what each recommends', () {
        final lesson = Lesson.parse(
          '$head$info${task('first', extra: 'requires: [lijsten, keuzes-maken]\n', blocks: starter)}${task('second')}',
        );

        expect(lesson.isProject, isTrue);
        expect(lesson.runtime, LessonRuntime.microbit);
        expect(lesson.sections.map((s) => s.kind), [SectionKind.info, SectionKind.task, SectionKind.task]);
        expect(lesson.sections[1].doneWhen, 'Het lampje brandt.');
        expect(lesson.sections[1].requires, ['lijsten', 'keuzes-maken']);
        expect(lesson.sections[1].starter, 'from microbit import *');
        expect(lesson.sections[2].requires, isEmpty);
        expect(lesson.sections[1].prose, isNot(contains('done-when')), reason: 'the card is drawn apart');
      });

      test('may run on the machine, where its steps are kept rather than left out', () {
        final lesson = Lesson.parse(
          '# T\n\n```metadata\nid: x\nlayout: project\nruntime: tkinter\n```\n\n'
          '$info${task('first', blocks: '```python-assignment\nimport tkinter as tk\n```\n\n')}${task('second')}',
        );

        expect(lesson.isProject, isTrue);
        expect(lesson.runtime, LessonRuntime.tkinter);
        expect(lesson.sections.map((s) => s.id), ['read', 'first', 'second']);
        expect(lesson.sections[1].starter, 'import tkinter as tk');
      });

      test('runs on a micro:bit or on the machine, and on nothing else', () {
        // Python is the default, so a project that names no runtime is on it.
        for (final runtime in ['', 'runtime: python\n']) {
          expect(
            () => Lesson.parse('# T\n\n```metadata\nid: x\nlayout: project\n$runtime```\n\n${task('a')}'),
            throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('microbit or tkinter'))),
            reason: runtime,
          );
        }
      });

      test('is the only lesson that runs on a micro:bit', () {
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\nruntime: microbit\n```\n\n$info'),
          throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('only a project'))),
        );
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\n```\n\n## a\n\n```metadata\nid: a\ntype: info\nruntime: microbit\n```\n\nprose\n',
          ),
          throwsA(isA<FormatException>()),
          reason: 'nor does one step of a lesson that is not a project',
        );
      });

      test('runs all of its sections on its own runtime, so none may name one', () {
        for (final runtime in ['microbit', 'python', 'tkinter']) {
          expect(
            () => Lesson.parse(
              '$head## a\n\n```metadata\nid: a\ntype: info\nruntime: $runtime\n```\n\nprose\n\n${task('b')}',
            ),
            throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('declares a `runtime`'))),
            reason: runtime,
          );
        }
      });

      test('holds tasks and info, and a task belongs to a project only', () {
        expect(
          () => Lesson.parse('$head## E\n\n```metadata\nid: e\ntype: exercise\n```\n\n'
              '```python-assignment\n```\n\n```python-validator\npass\n```\n\n${task('a')}'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n${task('a')}'),
          throwsA(isA<FormatException>()),
        );
      });

      test('may end with info, which the student finishes by reading it', () {
        final lesson = Lesson.parse('$head${task('a')}$info');

        expect(lesson.sections.last.kind, SectionKind.info);
      });

      test('a task says when it is done', () {
        expect(
          () => Lesson.parse('$head## a\n\n```metadata\nid: a\ntype: task\n```\n\nprose\n'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Lesson.parse('$head## a\n\n```metadata\nid: a\ntype: task\n```\n\n```done-when\n\n```\n'),
          throwsA(isA<FormatException>()),
        );
      });

      test('only its first task carries the starter', () {
        expect(
          () => Lesson.parse('$head${task('a')}${task('b', blocks: starter)}'),
          throwsA(isA<FormatException>()),
        );
      });

      test('recommends lessons by id, as a list', () {
        expect(
          () => Lesson.parse('$head${task('a', extra: 'requires: lijsten\n')}'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## a\n\n```metadata\nid: a\ntype: info\n'
              'requires: [lijsten]\n```\n\nprose\n'),
          throwsA(isA<FormatException>()),
        );
      });

      test('recommends lessons per task and not as a whole', () {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\nlayout: project\nruntime: microbit\nrequires: [lijsten]\n```\n\n'
            '${task('a')}',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('a layout no version has is an author\'s mistake', () {
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\nlayout: slides\n```\n\n$info'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    test('rejects a section with no id', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\n```\n\nprose\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a section with no type', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\nprose\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an exercise with no starter block', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a type the app no longer knows', () {
      // The old names, so a lesson left behind by the rename fails the test run
      // rather than the initialization screen.
      for (final type in ['short-assignment', 'long-assignment']) {
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: $type\nid: s\n```\n'),
          throwsA(isA<FormatException>()),
          reason: type,
        );
      }
    });

    group('what a lesson recommends', () {
      String lesson(String meta) =>
          '# T\n\n```metadata\nid: x\n$meta```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n';

      test('is a list of lesson ids from its own metadata', () {
        expect(Lesson.parse(lesson('requires: [je-code-testen, " lijsten "]\n')).requires, ['je-code-testen', 'lijsten']);
      });

      test('is nothing when it names none', () {
        expect(Lesson.parse(lesson('')).requires, isEmpty);
      });

      test('is refused when it is not a list of ids', () {
        for (final meta in ['requires: je-code-testen\n', 'requires: [""]\n', 'requires: [3]\n']) {
          expect(() => Lesson.parse(lesson(meta)), throwsA(isA<FormatException>()), reason: meta);
        }
      });
    });

    group('a pytest step', () {
      const module = '```file rekenmachine.py\ndef deel(a, b):\n    return a / b\n```\n\n';
      const editor = '```python-assignment\nfrom rekenmachine import deel\n```\n';

      String lesson({
        String meta = 'run: pytest\nfile: test_rekenmachine.py',
        String blocks = '$module$editor',
        String type = 'exercise',
      }) =>
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: $type\nid: s\n$meta\n```\n\nprose\n\n$blocks';

      test('reads the run, the editor\'s file and the given module, and needs no validator', () {
        final section = Lesson.parse(lesson()).sections.single;

        expect(section.run, SectionRun.pytest);
        expect(section.fileName, 'test_rekenmachine.py');
        expect(section.files, {'rekenmachine.py': 'def deel(a, b):\n    return a / b\n'});
        expect(section.validator, isNull);
      });

      test('a step that says nothing runs as a script, as main.py', () {
        final section = Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: exercise\nid: s\n```\n\n'
          '```python-assignment\nprint(1)\n```\n\n```python-validator\n```\n',
        ).sections.single;

        expect(section.run, SectionRun.script);
        expect(section.fileName, 'main.py');
      });

      test('a data file may sit beside the modules', () {
        final section = Lesson.parse(
          lesson(blocks: '$module```file cijfers.csv\nnaam,cijfer\n```\n\n$editor'),
        ).sections.single;

        expect(section.files.keys, ['rekenmachine.py', 'cijfers.csv']);
      });

      test('rejects what does not fit together', () {
        final cases = {
          'an unknown run': lesson(meta: 'run: unittest\nfile: test_rekenmachine.py'),
          'a run off an assignment': lesson(type: 'info', blocks: ''),
          'no file for the editor': lesson(meta: 'run: pytest'),
          'a module without pytest': lesson(meta: 'file: test_rekenmachine.py'),
          'an editor file without pytest':
              lesson(meta: 'file: test_rekenmachine.py', blocks: '$editor\n```python-validator\n```\n'),
          'a module name that is no module': lesson(blocks: '```file reken_machine-2.py\nx = 1\n```\n\n$editor'),
          "a given file with the editor's name":
              lesson(blocks: '```file test_rekenmachine.py\nx = 1\n```\n\n$editor'),
          'a file that hides pytest': lesson(blocks: '```file pytest.py\nx = 1\n```\n\n$editor'),
          'nothing pytest would collect': lesson(meta: 'run: pytest\nfile: oplossing.py'),
          'scripted input, which pytest never reads': lesson(blocks: '$module$editor\n```stdin\n4\n```\n'),
        };
        for (final MapEntry(key: reason, value: source) in cases.entries) {
          expect(() => Lesson.parse(source), throwsA(isA<FormatException>()), reason: reason);
        }
      });
    });

    test('a section is required unless it says otherwise', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );

      expect(lesson.sections.single.optional, isFalse);
    });

    test('reads `optional: true` off a section', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## A\n\n```metadata\ntype: info\nid: a\noptional: true\n```\n\nprose\n\n'
        '## B\n\n```metadata\ntype: info\nid: b\n```\n\nprose\n',
      );

      expect(lesson.sections.map((section) => section.optional), [true, false]);
    });

    test('reads the lesson\'s own `icon` off the document metadata', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\nicon: bar-chart\n```\n\n'
        '## S\n\n```metadata\ntype: info\nid: s\nemoji: "\u{1F4A1}"\n```\n\nprose\n',
      );

      expect(lesson.icon, CourseIcon.barChart);
      // A step keeps its own emoji.
      expect(lesson.sections.single.emoji, '\u{1F4A1}');
    });

    test('rejects an `icon` the app does not have, or one that is not text', () {
      for (final icon in ['rocket', '3']) {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\nicon: $icon\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n',
          ),
          throwsA(isA<FormatException>()),
          reason: icon,
        );
      }
    });

    test('rejects a lesson `emoji`, pointing at `icon`', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\nemoji: "\u{1F4A1}"\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n',
        ),
        throwsA(isA<FormatException>().having((error) => error.message, 'message', contains('`icon`'))),
      );
    });

    test('rejects an `icon` on a section', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\nicon: loop\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('every icon is named by a key that parses back to it', () {
      for (final icon in CourseIcon.values) {
        expect(icon.key, matches(RegExp(r'^[a-z]+(-[a-z]+)*$')));
        expect(CourseIcon.parse(icon.key), icon);
      }
    });

    test('reads an `emoji` off a section', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## A\n\n```metadata\ntype: info\nid: a\nemoji: "\u{1F4A1}"\n```\n\nprose\n\n'
        '## B\n\n```metadata\ntype: info\nid: b\n```\n\nprose\n',
      );

      expect(lesson.sections.map((section) => section.emoji), ['\u{1F4A1}', null]);
    });

    test('rejects an empty `emoji`', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\nemoji: "  "\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an `emoji` that is not text', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\nemoji: 3\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads a `pairs` block, first line to second', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n\nprose\n\n'
        '```pairs\n`print()`\n… toont iets.\n\n`input()`\n… vraagt iets.\n```\n',
      );

      final pairs = lesson.sections.single.pairs;

      expect(lesson.sections.single.kind, SectionKind.matchPairs);
      expect(pairs.map((pair) => pair.cue), ['`print()`', '`input()`']);
      expect(pairs.map((pair) => pair.answer), ['… toont iets.', '… vraagt iets.']);
      // The block never reaches the reader as prose.
      expect(lesson.sections.single.prose, 'prose');
    });

    test('rejects a match-pairs section with no `pairs` block', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a board with only one pair, which is not a game', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n\n'
          '```pairs\neen\none\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a pair that is not two lines', () {
      // The trap the blank-line form exists to catch: pairs written without one.
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n\n'
          '```pairs\neen\none\ntwee\ntwo\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a `pairs` block on a section that is not a board', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\n'
          '```pairs\neen\none\n\ntwee\ntwo\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a board that also asks for code', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n\n'
          '```pairs\neen\none\n\ntwee\ntwo\n```\n\n```python-assignment\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('a board is not an assignment, so nothing demands an editor of it', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: match-pairs\nid: s\n```\n\n'
        '```pairs\neen\none\n\ntwee\ntwo\n```\n',
      );

      expect(lesson.sections.single.kind.isAssignment, isFalse);
      expect(lesson.sections.single.starter, isNull);
      expect(lesson.sections.single.validator, isNull);
    });

    test('reads a `<lang>-predict` block as the program to predict', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\nprose\n\n'
        '```python-predict\nprint("hi")\n```\n',
      );

      final section = lesson.sections.single;

      expect(section.kind, SectionKind.predictOutput);
      expect(section.program, 'print("hi")');
      // Nothing the student writes, so no editor and no checks are demanded of
      // it — the interpreter is the answer key.
      expect(section.kind.isAssignment, isFalse);
      expect(section.starter, isNull);
      expect(section.validator, isNull);
      // The block never reaches the reader as prose; it is drawn by the step.
      expect(section.prose, 'prose');
    });

    test('rejects a predict-output section with no predict block', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n```metadata\n```\n'
          '## S\n\n```metadata\ntype: predict-output\nid: s\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty program, which has no output to predict', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\n'
          '```python-predict\n\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a predict block on a section of another type', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\n'
          '```python-predict\nprint(1)\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads a `stdin` block, and ends it in a newline', () {
      // The terminating newline is what makes the last line a whole line, so a
      // program reading it gets a value rather than an EOFError.
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\nid: s\n```\n\nprose\n\n'
        '```python-assignment\n```\n\n```python-validator\npass\n```\n\n```stdin\n7\n3\n```\n',
      );

      expect(lesson.sections.single.stdin, '7\n3\n');
      expect(lesson.sections.single.prose, 'prose');
    });

    test('keeps the scripted lines verbatim, unlike an order block', () {
      // Leading spaces, trailing spaces and a blank line are all answers a
      // student could type at a prompt, so none of them may be tidied away.
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\nid: s\n```\n\n'
        '```python-assignment\n```\n\n```python-validator\npass\n```\n\n```stdin\n  ingesprongen\n\ntrailing  \n```\n',
      );

      expect(lesson.sections.single.stdin, '  ingesprongen\n\ntrailing  \n');
    });

    test('accepts a single empty line, which is one empty answer', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\nid: s\n```\n\n'
        '```python-assignment\n```\n\n```python-validator\npass\n```\n\n```stdin\n\n```\n',
      );

      expect(lesson.sections.single.stdin, '\n');
    });

    test('rejects an empty `stdin` block', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\nid: s\n```\n\n'
          '```python-assignment\n```\n\n```python-validator\npass\n```\n\n```stdin\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a `stdin` block on a step that runs nothing', () {
      for (final type in ['info', 'match-pairs']) {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: $type\nid: s\n```\n\nprose\n\n'
            '```pairs\na\nb\n\nc\nd\n```\n\n```stdin\n7\n```\n',
          ),
          throwsA(isA<FormatException>()),
          reason: type,
        );
      }
    });

    test('rejects a `stdin` block written above the first section', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n```stdin\n7\n```\n'),
        throwsA(isA<FormatException>()),
      );
    });

    test('does not leak one section\'s scripted input into the next', () {
      // The reset in flush() is the easiest line of the whole feature to miss,
      // and this is the only thing that catches it.
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## A\n\n```metadata\ntype: quick-exercise\nid: a\n```\n\n'
        '```python-assignment\n```\n\n```python-validator\npass\n```\n\n```stdin\n7\n```\n\n'
        '## B\n\n```metadata\ntype: quick-exercise\nid: b\n```\n\n'
        '```python-assignment\n```\n\n```python-validator\npass\n```\n',
      );

      expect(lesson.sections.map((section) => section.stdin), ['7\n', null]);
    });

    group('a `file` block', () {
      String exercise(String blocks) =>
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: quick-exercise\nid: s\n```\n\nprose\n\n'
          '```python-assignment\n```\n\n```python-validator\npass\n```\n\n$blocks';

      test('is read by its name, kept verbatim and ended in a newline', () {
        final lesson = Lesson.parse(exercise('```file cijfers.csv\nnaam,cijfer\n  Sanne ,7.5\n\nTim,6\n```\n'));

        expect(lesson.sections.single.files, {'cijfers.csv': 'naam,cijfer\n  Sanne ,7.5\n\nTim,6\n'});
        expect(lesson.sections.single.prose, 'prose', reason: 'the file is drawn by the step, not in the prose');
      });

      test('may come more than once, and keeps the order the author wrote', () {
        final lesson = Lesson.parse(exercise('```file b.txt\n2\n```\n\n```file a.txt\n1\n```\n'));

        expect(lesson.sections.single.files.keys, ['b.txt', 'a.txt']);
      });

      test('may be empty, which is an empty file', () {
        final lesson = Lesson.parse(exercise('```file leeg.txt\n```\n'));

        expect(lesson.sections.single.files, {'leeg.txt': ''});
      });

      test('may hold a fence when it is opened with a longer one', () {
        final lesson = Lesson.parse(exercise('````file notities.md\n```\ncode\n```\n````\n'));

        expect(lesson.sections.single.files, {'notities.md': '```\ncode\n```\n'});
      });

      test('is allowed on every step that runs code', () {
        final predict = Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\n'
          '```python-predict\nprint(open("a.txt").read())\n```\n\n```file a.txt\nhoi\n```\n',
        );
        final order = Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
          '```python-order\na = 1\nprint(a)\n```\n\n```python-validator\npass\n```\n\n```file a.txt\nhoi\n```\n',
        );

        expect(predict.sections.single.files, {'a.txt': 'hoi\n'});
        expect(order.sections.single.files, {'a.txt': 'hoi\n'});
      });

      test('rejects a name that is missing, has a folder or is not one word', () {
        for (final name in ['', 'data/cijfers.csv', '../cijfers.csv', 'twee namen.csv', '.verborgen']) {
          expect(
            () => Lesson.parse(exercise('```file $name\n1\n```\n')),
            throwsA(isA<FormatException>()),
            reason: '"$name"',
          );
        }
      });

      test('rejects the names the app uses itself, and Python modules', () {
        // A module in the working directory would be imported in place of the
        // standard library's, and the checks import `ast`.
        for (final name in ['main.py', 'tmp', 'ast.py']) {
          expect(
            () => Lesson.parse(exercise('```file $name\n1\n```\n')),
            throwsA(isA<FormatException>()),
            reason: name,
          );
        }
      });

      test('rejects the same name twice, whatever its case', () {
        expect(
          () => Lesson.parse(exercise('```file Data.csv\n1\n```\n\n```file data.csv\n2\n```\n')),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects a byte order mark, which `csv` would read as part of the first heading', () {
        expect(
          () => Lesson.parse(exercise('```file data.csv\n﻿naam,cijfer\n```\n')),
          throwsA(isA<FormatException>()),
        );
      });

      test('is rejected on a step that runs nothing', () {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n\n'
            '```file a.txt\n1\n```\n',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('is rejected above the first section', () {
        expect(
          () => Lesson.parse('# T\n\n```metadata\nid: x\n```\n\n```file a.txt\n1\n```\n'),
          throwsA(isA<FormatException>()),
        );
      });

      test('is not read on a step for a runtime that is not ready', () {
        // Such a step is left out whole, so a name this version would refuse
        // must not stop the lesson from loading.
        final lesson = Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n'
          '## Lezen\n\n```metadata\nid: read\ntype: info\n```\n\nprose\n\n'
          '## Venster\n\n```metadata\nid: window\nruntime: tkinter\ntype: window-exercise\n```\n\n'
          '```file plaatje.py\n1\n```\n',
        );

        expect(lesson.sections.map((section) => section.id), ['read']);
      });

      test('does not leak into the next section', () {
        final lesson = Lesson.parse(
          '${exercise('```file a.txt\n1\n```\n')}\n'
          '## B\n\n```metadata\ntype: quick-exercise\nid: b\n```\n\n'
          '```python-assignment\n```\n\n```python-validator\npass\n```\n',
        );

        expect(lesson.sections.map((section) => section.files), [
          {'a.txt': '1\n'},
          isEmpty,
        ]);
      });
    });

    test('reads `optional: true` off the lesson\'s own metadata', () {
      final deepDive = Lesson.parse(
        '# T\n\n```metadata\nid: x\noptional: true\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );
      final ordinary = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );

      expect(deepDive.optional, isTrue);
      expect(ordinary.optional, isFalse, reason: 'a lesson is part of the run unless it says otherwise');
    });

    test('rejects a `group`, which is a heading in the contents file now', () {
      // Read by nothing, the line would leave the lesson under no heading
      // without anyone being told.
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\ngroup: "Week 1 · De basis"\n```\n\n'
          '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
        ),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('contents file'))),
      );
    });

    test('reads a `feature` toggle off the lesson\'s own metadata', () {
      final hidden = Lesson.parse(
        '# T\n\n```metadata\nid: x\nfeature: files\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );
      final ordinary = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );

      expect(hidden.feature, 'files');
      expect(ordinary.feature, isNull, reason: 'a lesson is shown unless it names a toggle');
    });

    test('rejects a `feature` that is not spelled like a group id', () {
      for (final feature in ['Files', 'two words', '42', '[files]']) {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\nfeature: $feature\n```\n\n'
            '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
          ),
          throwsA(isA<FormatException>()),
          reason: feature,
        );
      }
    });

    test('rejects a `feature` on a step, which nothing would read', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n'
          '## S\n\n```metadata\ntype: info\nid: s\nfeature: files\n```\n\nprose\n',
        ),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('Only a lesson or the group'))),
      );
    });

    test('rejects a lesson `optional` that is not a boolean', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\noptional: misschien\n```\n\n'
          '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads an `explanation` block, which is optional', () {
      final withOne = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\nprose\n\n'
        '```python-predict\nprint(1)\n```\n\n```explanation\nOmdat `print` het zo doet.\n```\n',
      );
      final without = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\n'
        '```python-predict\nprint(1)\n```\n',
      );

      expect(withOne.sections.single.explanation, 'Omdat `print` het zo doet.');
      expect(withOne.sections.single.prose, 'prose');
      expect(without.sections.single.explanation, isNull);
    });

    test('rejects an `explanation` on a section with no answer to explain', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\n'
          '```explanation\nOmdat het zo is.\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an empty `explanation` block', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: predict-output\nid: s\n```\n\n'
          '```python-predict\nprint(1)\n```\n\n```explanation\n\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads an `<lang>-order` block, and its distractors', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n'
        '## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\nprose\n\n'
        '```python-order\nfor i in range(2):\n    print(i)\n```\n\n'
        '```python-distractors\nprint("nope")\n```\n\n'
        '```python-validator\npass\n```\n',
      );

      final section = lesson.sections.single;

      expect(section.kind, SectionKind.orderLines);
      // Leading whitespace is kept: the indentation belongs to the line and
      // travels with it, so the student arranges rather than also indenting.
      expect(section.lines, ['for i in range(2):', '    print(i)']);
      expect(section.distractors, ['print("nope")']);
      // Checked by running what was built, so it has a validator — but nothing
      // to type in, so no editor and no starter block.
      expect(section.kind.usesValidator, isTrue);
      expect(section.kind.isAssignment, isFalse);
      expect(section.starter, isNull);
      expect(section.validator, 'pass');
      // Neither block reaches the reader as prose.
      expect(section.prose, 'prose');
    });

    test('drops the blank lines between the code, which are not tiles', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
        '```python-order\nprint(1)\n\n\nprint(2)\n```\n\n```python-validator\npass\n```\n',
      );

      expect(lesson.sections.single.lines, ['print(1)', 'print(2)']);
    });

    test('rejects an order-lines step with no order block', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
          '```python-validator\npass\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an order-lines step with no validator, which nothing could check', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
          '```python-order\nprint(1)\nprint(2)\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a single line to order, which is already in order', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
          '```python-order\nprint(1)\n```\n\n```python-validator\npass\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an order block on a section of another type', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\n'
          '```python-order\nprint(1)\nprint(2)\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an ordering step that also asks for typed code', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: order-lines\nid: s\n```\n\n'
          '```python-order\nprint(1)\nprint(2)\n```\n\n```python-assignment\n```\n'
          '```python-validator\npass\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a validator on a step with nothing to check', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\n'
          '```python-validator\npass\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects an `optional` that is not a boolean', () {
      expect(
        () => Lesson.parse(
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\noptional: yes please\n```\n',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    group('the lines a quick exercise allows', () {
      String step(String starter, {String type = 'quick-exercise', String meta = ''}) =>
          '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: $type\nid: s\n$meta```\n\n'
          '```python-assignment\n$starter```\n\n```python-validator\npass\n```\n';

      test('are one past the starter, and at least two', () {
        for (final (starter, lines) in [('', 2), ('print(2.5)\n', 2), ('def f():\n    pass\n', 3)]) {
          expect(Lesson.parse(step(starter)).sections.single.maxLines, lines, reason: starter);
        }
      });

      test('are what `lines` says, when it says so', () {
        expect(Lesson.parse(step('x = 1\n', meta: 'lines: 3\n')).sections.single.maxLines, 3);
      });

      test('are no concern of an exercise, which is not held to a length', () {
        expect(Lesson.parse(step('x = 1\n', type: 'exercise')).sections.single.maxLines, isNull);
        expect(
          () => Lesson.parse(step('x = 1\n', type: 'exercise', meta: 'lines: 3\n')),
          throwsA(isA<FormatException>()),
        );
      });

      test('reject a `lines` that is not a whole number above 0', () {
        for (final lines in ['0', '-1', '2.5', 'three']) {
          expect(
            () => Lesson.parse(step('', meta: 'lines: $lines\n')),
            throwsA(isA<FormatException>()),
            reason: lines,
          );
        }
      });

      test('reject a `lines` the starter does not fit in', () {
        expect(
          () => Lesson.parse(step('a = 1\nb = 2\nprint(a + b)\n', meta: 'lines: 2\n')),
          throwsA(isA<FormatException>()),
        );
      });
    });
  });
}
