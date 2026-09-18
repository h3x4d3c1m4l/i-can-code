import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

void main() {
  group('Course.entriesFrom', () {
    test('groups a lesson\'s locales and orders by the filename prefix', () {
      final entries = Course.entriesFrom([
        'assets/lessons/python/02-variables.en.md',
        'assets/lessons/python/01-hello.nl.md',
        'assets/lessons/python/01-hello.en.md',
        'assets/lessons/python/02-variables.nl.md',
      ]);

      expect(entries.map((e) => e.slug), ['hello', 'variables']);
      expect(entries.first.locales, unorderedEquals(['nl', 'en']));
      expect(entries.first.order, 1);
      expect(entries.first.language, 'python');
    });

    test('ignores anything that is not a lesson file', () {
      final entries = Course.entriesFrom([
        'assets/lessons/python/01-ok.nl.md',
        'assets/lessons/python/notes.txt',
        'assets/lessons/python/no-order-prefix.nl.md',
        'assets/lessons/README.md',
        'assets/fonts/Inter-400.ttf',
      ]);

      expect(entries.map((e) => e.slug), ['ok']);
    });
  });

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
          expect(lesson.emoji, isNotNull);
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

    test('reads the lesson\'s own `emoji` off the document metadata', () {
      final lesson = Lesson.parse(
        '# T\n\n```metadata\nid: x\nemoji: "\u{2328}\u{FE0F}"\n```\n\n'
        '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );

      expect(lesson.emoji, '\u{2328}\u{FE0F}');
      // The document's emoji is the card's, not the first step's.
      expect(lesson.sections.single.emoji, isNull);
    });

    test('rejects a lesson `emoji` that is not text', () {
      expect(
        () => Lesson.parse('# T\n\n```metadata\nid: x\nemoji: 3\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n'),
        throwsA(isA<FormatException>()),
      );
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

    test('reads the lesson\'s `group`, which sets it under a heading', () {
      final grouped = Lesson.parse(
        '# T\n\n```metadata\nid: x\ngroup: "Week 1 · De basis"\n```\n\n'
        '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );
      final loose = Lesson.parse(
        '# T\n\n```metadata\nid: x\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
      );

      expect(grouped.group, 'Week 1 · De basis');
      expect(loose.group, isNull, reason: 'a lesson belongs to no group unless it says so');
    });

    test('rejects a `group` that is not a line of text', () {
      for (final value in ['3', '""', '"   "', '[a, b]']) {
        expect(
          () => Lesson.parse(
            '# T\n\n```metadata\nid: x\ngroup: $value\n```\n\n'
            '## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n',
          ),
          throwsA(isA<FormatException>()),
          reason: value,
        );
      }
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
  });
}
