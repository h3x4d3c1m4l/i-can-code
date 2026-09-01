import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

void main() {
  group('Course.entriesFrom', () {
    test('groups a lesson\'s locales and orders by the filename prefix', () {
      final entries = Course.entriesFrom([
        'assets/lessons/python/02-variables.en.md',
        'assets/lessons/python/01-input-and-output.nl.md',
        'assets/lessons/python/01-input-and-output.en.md',
        'assets/lessons/python/02-variables.nl.md',
      ]);

      expect(entries.map((e) => e.slug), ['input-and-output', 'variables']);
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
    // Parses what actually ships, so an authoring mistake fails here rather
    // than on the initialization screen.
    for (final file in Directory('assets/lessons/python').listSync().whereType<File>()) {
      test(file.uri.pathSegments.last, () {
        final lesson = Lesson.parse(file.readAsStringSync());

        expect(lesson.id, isNotEmpty);
        expect(lesson.title, isNotEmpty);
        expect(lesson.emoji, isNotNull, reason: 'every lesson that ships carries an `emoji` for its card');
        expect(lesson.sections, isNotEmpty);

        expect(
          lesson.sections.map((s) => s.id),
          isNot(contains(resumeSection)),
          reason: '"$resumeSection" is the address that means "wherever I left off"',
        );

        expect(
          lesson.sections.map((s) => s.id).toSet(),
          hasLength(lesson.sections.length),
          reason: 'saved progress keys on section ids, so they must be unique within a lesson',
        );

        for (final section in lesson.sections) {
          expect(section.title, isNotEmpty, reason: 'every section needs a heading');
          expect(section.id, isNotEmpty, reason: 'every section needs a stable id');
          expect(
            section.emoji,
            isNotNull,
            reason: '${section.title} has no `emoji`; every step that ships carries one',
          );
          if (section.kind.isAssignment) {
            expect(section.starter, isNotNull, reason: '${section.title} needs an assignment block');
            expect(section.validator, isNotNull, reason: '${section.title} needs a validator');
          }
          expect(section.prose, isNot(contains('&quot;')), reason: 'prose must not be HTML-escaped');
          expect(section.prose, isNot(contains('```metadata')), reason: 'metadata must not reach the reader');
          expect(section.prose, isNot(contains('-validator')), reason: 'validators must never be rendered');
        }
      });
    }

    test('both translations describe the same lesson', () {
      final nl = Lesson.parse(File('assets/lessons/python/01-input-and-output.nl.md').readAsStringSync());
      final en = Lesson.parse(File('assets/lessons/python/01-input-and-output.en.md').readAsStringSync());

      expect(en.id, nl.id);
      expect(en.emoji, nl.emoji);
      expect(en.stepCount, nl.stepCount);
      expect(en.sections.map((s) => s.kind), nl.sections.map((s) => s.kind));
      // Progress is keyed on ids, so a tick earned in Dutch has to count in
      // English too.
      expect(en.sections.map((s) => s.id), nl.sections.map((s) => s.id));
      // Code is deliberately not translated, so the starters must match exactly.
      expect(en.sections.map((s) => s.starter), nl.sections.map((s) => s.starter));
      // Nor is the emoji: it marks the step, not the language it is written in.
      expect(en.sections.map((s) => s.emoji), nl.sections.map((s) => s.emoji));
    });

    test('code blocks come through unescaped, ready to run', () {
      final lesson = Lesson.parse(File('assets/lessons/python/01-input-and-output.en.md').readAsStringSync());
      final validators = lesson.sections.map((s) => s.validator).nonNulls;

      expect(validators, isNotEmpty);
      expect(validators.every((v) => !v.contains('&quot;')), isTrue);
      expect(validators.first, contains('"print("'));
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
