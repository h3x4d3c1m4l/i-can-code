import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

import '../support/host_python.dart';

/// The rules every lesson that ships must keep, run over whatever lessons are
/// there to check.
///
/// The course itself lives outside this repository, so nothing here names a
/// lesson or assumes one exists. Point it at a checkout of the course with
/// `LESSONS_DIR`, laid out the way `assets/lessons/` is:
///
///     LESSONS_DIR=../course/lessons fvm flutter test test/content/
///
/// Without it, it reads `assets/lessons/`, and with no lesson files there it
/// skips rather than passing on nothing: a green run that checked nothing reads
/// exactly like a green run that checked everything.
void main() {
  final root = Platform.environment['LESSONS_DIR'] ?? 'assets/lessons';
  final lessons = _lessonsUnder(root);
  final skip = lessons.isEmpty ? 'no lesson files under $root; set LESSONS_DIR to check a course' : null;

  group('every lesson under $root', () {
    for (final entry in lessons) {
      for (final path in entry.paths.values) {
        test('${entry.language}/${File(path).uri.pathSegments.last}', () {
          _holdsTheRules(Lesson.parse(File(path).readAsStringSync()));
        });
      }
    }

    test('every translation of a lesson describes the same lesson', () {
      for (final entry in lessons.where((entry) => entry.locales.length > 1)) {
        final translations = {
          for (final MapEntry(key: locale, value: path) in entry.paths.entries)
            locale: Lesson.parse(File(path).readAsStringSync()),
        };
        final first = translations.values.first;

        for (final MapEntry(key: locale, value: lesson) in translations.entries) {
          _describesTheSameLesson(lesson, first, why: '${entry.slug}.$locale');
        }
      }
    });

    test(
      'every translation reaches the same verdict on the same code',
      () async {
        // A validator is translated alongside its prose, so the two can drift
        // into disagreeing about what passes. The messages differ; the verdict
        // must not.
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

        for (final entry in lessons.where((entry) => entry.locales.length > 1)) {
          final translations = [for (final path in entry.paths.values) Lesson.parse(File(path).readAsStringSync())];

          for (var i = 0; i < translations.first.sections.length; i++) {
            final validator = translations.first.sections[i].validator;
            if (validator == null) continue;

            for (final code in answers) {
              final first = await attempt(code: code, validator: validator);

              for (final other in translations.skip(1)) {
                final verdict = await attempt(code: code, validator: other.sections[i].validator);
                final why = '${entry.slug} section $i, $code';

                expect(verdict.passed, first.passed, reason: why);
                expect(verdict.disallowedConstruct, first.disallowedConstruct, reason: why);
              }
            }
          }
        }
      },
      skip: hasPython3 ? null : 'python3 is not on PATH',
    );
  }, skip: skip);
}

/// Every lesson file under [root], grouped by lesson with one path per locale.
///
/// Goes through [Course.entriesFrom] rather than a pattern of its own, so a file
/// the app would not pick up is not checked either. That method keys on the
/// bundle's own prefix, so each file is named to it and mapped back.
List<LessonEntry> _lessonsUnder(String root) {
  final directory = Directory(root);
  if (!directory.existsSync()) return const [];

  final onDisk = <String, String>{};
  for (final file in directory.listSync(recursive: true).whereType<File>()) {
    final relative = file.path.substring(directory.path.length).replaceAll(r'\', '/').replaceFirst(RegExp('^/'), '');
    onDisk['${Course.root}$relative'] = file.path;
  }

  return [
    for (final entry in Course.entriesFrom(onDisk.keys))
      LessonEntry(
        language: entry.language,
        order: entry.order,
        slug: entry.slug,
        paths: {for (final MapEntry(key: locale, value: asset) in entry.paths.entries) locale: onDisk[asset]!},
      ),
  ];
}

/// What [Lesson.parse] does not refuse but no lesson that ships may do.
void _holdsTheRules(Lesson lesson) {
  expect(lesson.id, isNotEmpty);
  expect(lesson.title, isNotEmpty);
  expect(lesson.emoji, isNotNull, reason: 'every lesson that ships carries an `emoji` for its card');
  expect(lesson.sections, isNotEmpty);

  expect(
    lesson.sections.map((s) => s.id),
    isNot(contains(resumeSection)),
    reason: '"$resumeSection" is the address that means "wherever I left off"',
  );
  for (final reserved in [replLesson, microbitLesson, microbitReplLesson]) {
    expect(lesson.id, isNot(reserved), reason: '"$reserved" is an address of its own, where a lesson id goes');
  }
  expect(
    lesson.sections.map((s) => s.id).toSet(),
    hasLength(lesson.sections.length),
    reason: 'saved progress keys on section ids, so they must be unique within a lesson',
  );

  for (final section in lesson.sections) {
    expect(section.title, isNotEmpty, reason: 'every section needs a heading');
    expect(section.id, isNotEmpty, reason: 'every section needs a stable id');
    expect(section.emoji, isNotNull, reason: '${section.title} has no `emoji`; every step that ships carries one');

    if (section.kind.isAssignment) {
      expect(section.starter, isNotNull, reason: '${section.title} needs an assignment block');
      expect(section.validator, isNotNull, reason: '${section.title} needs a validator');
    }
    if (section.kind == SectionKind.matchPairs) {
      expect(section.pairs.length, greaterThanOrEqualTo(2), reason: '${section.title} is a board with nothing to match');
      for (final pair in section.pairs) {
        expect(pair.cue, isNotEmpty, reason: '${section.title} has a half-empty pair');
        expect(pair.answer, isNotEmpty, reason: '${section.title} has a half-empty pair');
      }
    } else {
      expect(section.pairs, isEmpty, reason: '${section.title} is not a board');
    }
    if (section.kind == SectionKind.orderLines) {
      expect(section.lines.length, greaterThanOrEqualTo(2), reason: '${section.title} has nothing to arrange');
      expect(section.validator, isNotNull, reason: '${section.title} is checked by running what was built');
    } else {
      expect(section.lines, isEmpty, reason: '${section.title} is not an ordering step');
      expect(section.distractors, isEmpty, reason: '${section.title} is not an ordering step');
    }
    if (section.kind == SectionKind.predictOutput) {
      expect(section.program?.trim(), isNotEmpty, reason: '${section.title} asks for a prediction of nothing');
    } else {
      expect(section.program, isNull, reason: '${section.title} is not a predict-output step');
      expect(section.explanation, isNull, reason: '${section.title} has no answer to explain');
    }

    expect(section.prose, isNot(contains('&quot;')), reason: 'prose must not be HTML-escaped');
    expect(section.prose, isNot(contains('```metadata')), reason: 'metadata must not reach the reader');
    expect(section.prose, isNot(contains('-validator')), reason: 'validators must never be rendered');
  }
}

/// Holds one translation to another. Progress, starters and emoji are shared
/// across languages; only what a reader reads may differ.
void _describesTheSameLesson(Lesson lesson, Lesson first, {required String why}) {
  expect(lesson.id, first.id, reason: why);
  expect(lesson.emoji, first.emoji, reason: why);
  expect(lesson.stepCount, first.stepCount, reason: why);
  expect(lesson.sections.map((s) => s.kind), first.sections.map((s) => s.kind), reason: why);
  // Progress is keyed on ids, so a tick earned in Dutch has to count in
  // English too.
  expect(lesson.sections.map((s) => s.id), first.sections.map((s) => s.id), reason: why);
  // Code is deliberately not translated, so the starters must match exactly.
  expect(lesson.sections.map((s) => s.starter), first.sections.map((s) => s.starter), reason: why);
  // Nor is the emoji: it marks the step, not the language it is written in.
  expect(lesson.sections.map((s) => s.emoji), first.sections.map((s) => s.emoji), reason: why);
  // A board's tiles *are* translated, but a translation that dropped one
  // would be a different game.
  expect(lesson.sections.map((s) => s.pairs.length), first.sections.map((s) => s.pairs.length), reason: why);
  // A predict-output step is a step in both languages or in neither. The
  // program itself may differ — the strings in it are read by the student — so
  // only its presence is held. Scripted input the same way: a step that reads
  // in one language reads in every other, because it is the same program.
  expect(lesson.sections.map((s) => s.program == null), first.sections.map((s) => s.program == null), reason: why);
  expect(lesson.sections.map((s) => s.stdin == null), first.sections.map((s) => s.stdin == null), reason: why);
  // The heading's words are translated, but a lesson in a group in one
  // language and loose in another would stand under a different heading.
  expect(lesson.group == null, first.group == null, reason: why);
}
