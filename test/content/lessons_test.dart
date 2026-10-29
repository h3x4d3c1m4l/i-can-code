import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/includes.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

import '../../bin/bundle_lessons.dart';
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
///
/// A contents file that does not parse fails the whole file while it loads,
/// under the name of what is wrong with it: there is no list of lessons to
/// make tests of.
void main() {
  final root = Directory(Platform.environment['LESSONS_DIR'] ?? 'assets/lessons');
  // The bundle and the entries the app itself would make of the directory, so
  // a file the app would not pick up is not checked either.
  final files = bundleLessons(root, lessonFiles(root));
  final lessons = Course.entriesFrom(files);
  final skip = lessons.isEmpty ? 'no lesson files under ${root.path}; set LESSONS_DIR to check a course' : null;

  Lesson parsed(String path) => Lesson.parse(files[path]!);
  String named(String path) => path.substring(Course.root.length);

  group('every lesson under ${root.path}', () {
    for (final path in {for (final entry in lessons) ...entry.paths.values}) {
      test(named(path), () => _holdsTheRules(parsed(path)));
    }

    test('the course loads the way the app loads it', () {
      // Beyond each file parsing: every locale lists the same lessons in the
      // same places.
      expect(() => Course.fromFiles(files), returnsNormally);
    });

    test('a lesson id is unique within its subject', () {
      // Progress and drafts key on the subject and the lesson id, so two
      // lessons sharing one would share a student's ticks and code.
      final seen = <String, String>{};
      for (final entry in lessons) {
        final path = entry.paths.values.first;
        final id = parsed(path).id;
        final key = '${entry.subject}/$id';
        expect(seen[key], isNull, reason: '"$id" is used by ${seen[key]} and ${named(path)}');
        seen[key] = named(path);
      }
    });

    test('a contents file calls every lesson by its own title', () {
      // The app shows the lesson's title, so a contents file that says
      // something else is one its author can no longer read the course off.
      for (final entry in lessons) {
        for (final MapEntry(key: locale, value: path) in entry.paths.entries) {
          expect(
            entry.listedTitles[locale],
            parsed(path).title,
            reason: '${entry.subject}/contents.$locale.md, on ${named(path)}',
          );
        }
      }
    });

    test('every markdown file is listed in a contents file, or included by one that is', () {
      // A lesson that was written and never listed is in no catalog, and
      // nothing else would say so.
      final reached = _reachedFrom(root, [
        for (final path in files.keys)
          if (Course.isContents(path)) named(path),
        for (final entry in lessons) ...entry.paths.values.map(named),
      ]);
      final unlisted = files.keys
          .where(Course.isInSubject)
          .map(named)
          .where((path) => !reached.contains(path) && !path.endsWith('/README.md'));

      expect(unlisted, isEmpty);
    });

    test('every lesson a lesson or a task recommends is a lesson of its own subject', () {
      final ids = <String, Set<String>>{};
      final all = [
        for (final entry in lessons)
          for (final path in entry.paths.values) (entry: entry, path: path, lesson: parsed(path)),
      ];
      for (final (:entry, path: _, :lesson) in all) {
        (ids[entry.subject] ??= {}).add(lesson.id);
      }

      for (final (:entry, :path, :lesson) in all) {
        for (final id in lesson.requires) {
          expect(ids[entry.subject], contains(id), reason: '${named(path)} recommends "$id"');
          expect(id, isNot(lesson.id), reason: '${named(path)} recommends itself');
        }
        for (final section in lesson.sections) {
          for (final id in section.requires) {
            expect(ids[entry.subject], contains(id), reason: '${named(path)}: "${section.title}" recommends "$id"');
          }
        }
      }
    });

    test('every translation of a lesson describes the same lesson', () {
      for (final entry in lessons.where((entry) => entry.locales.length > 1)) {
        final first = parsed(entry.paths.values.first);

        for (final path in entry.paths.values) {
          _describesTheSameLesson(parsed(path), first, why: named(path));
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
          final translations = [for (final path in entry.paths.values) parsed(path)];

          for (var i = 0; i < translations.first.sections.length; i++) {
            final section = translations.first.sections[i];
            if (section.validator == null) continue;
            if (section.run == SectionRun.pytest && !hasPytest) continue;

            for (final code in answers) {
              // Each with its own input and files: without them a validator
              // that reads either fails the same way in every language.
              final first = await attemptSection(section, code);

              for (final other in translations.skip(1)) {
                final verdict = await attemptSection(other.sections[i], code);
                final why = '${named(entry.paths.values.first)} section $i, $code';

                expect(verdict.passed, first.passed, reason: why);
                expect(verdict.disallowedConstruct, first.disallowedConstruct, reason: why);
                expect(verdict.aaaTest, first.aaaTest, reason: why);
              }
            }
          }
        }
      },
      skip: hasPython3 ? null : 'python3 is not on PATH',
    );
  }, skip: skip);
}

/// Every file under [root] that [starts] lead to: themselves, and whatever
/// any of them includes. Paths are relative to [root].
Set<String> _reachedFrom(Directory root, Iterable<String> starts) {
  final reached = <String>{};

  String? read(String path) {
    final file = File('${root.path}/$path');
    if (!file.existsSync()) return null;

    reached.add(path);
    return file.readAsStringSync();
  }

  for (final start in starts) {
    resolveIncludes(read(start)!, path: start, read: read);
  }

  return reached;
}

/// What [Lesson.parse] does not refuse but no lesson that ships may do.
void _holdsTheRules(Lesson lesson) {
  expect(lesson.id, isNotEmpty);
  expect(lesson.title, isNotEmpty);
  expect(lesson.icon, isNotNull, reason: 'every lesson that ships carries an `icon` for its tile');
  // A lesson for a runtime this version cannot run in its layout parses to no
  // steps, and `Course.load` leaves it out of the catalog.
  if (lesson.runtime.readyIn(lesson.layout)) expect(lesson.sections, isNotEmpty);

  expect(
    lesson.sections.map((s) => s.id),
    isNot(contains(resumeSection)),
    reason: '"$resumeSection" is the address that means "wherever I left off"',
  );
  for (final reserved in [replLesson, microbitLesson, microbitReplLesson, tkinterLesson]) {
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
      // Under pytest the tests check the answer, so a validator is optional.
      if (section.run == SectionRun.script) {
        expect(section.validator, isNotNull, reason: '${section.title} needs a validator');
      }
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

    if (section.kind == SectionKind.task) {
      expect(section.doneWhen?.trim(), isNotEmpty, reason: '${section.title} does not say when it is done');
    } else {
      expect(section.doneWhen, isNull, reason: '${section.title} is not a task');
      expect(section.requires, isEmpty, reason: '${section.title} is not a task');
    }

    for (final MapEntry(key: name, value: text) in section.files.entries) {
      // Carried in the course bundle once per locale, and in every run's program.
      expect(
        utf8.encode(text).length,
        lessThanOrEqualTo(32 * 1024),
        reason: '${section.title} gives a file "$name" larger than 32 KB',
      );
    }

    expect(section.prose, isNot(contains('&quot;')), reason: 'prose must not be HTML-escaped');
    expect(section.prose, isNot(contains('```metadata')), reason: 'metadata must not reach the reader');
    expect(section.prose, isNot(contains('-validator')), reason: 'validators must never be rendered');
  }
}

/// Holds one translation to another. Progress, starters, icons and emoji are
/// shared across languages; only what a reader reads may differ.
void _describesTheSameLesson(Lesson lesson, Lesson first, {required String why}) {
  expect(lesson.id, first.id, reason: why);
  expect(lesson.icon, first.icon, reason: why);
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
  // The files by name only: the starters name them and are the same in every
  // language, while the data in them may be translated.
  expect(
    lesson.sections.map((s) => s.files.keys.toList()),
    first.sections.map((s) => s.files.keys.toList()),
    reason: why,
  );
  // A project in one language is a project in all of them, on the same runtime
  // (the project screen reads it off one), and recommends the same lessons:
  // those are ids, not words.
  expect(lesson.layout, first.layout, reason: why);
  expect(lesson.runtime, first.runtime, reason: why);
  expect(lesson.sections.map((s) => s.requires), first.sections.map((s) => s.requires), reason: why);
  expect(lesson.requires, first.requires, reason: why);
}
