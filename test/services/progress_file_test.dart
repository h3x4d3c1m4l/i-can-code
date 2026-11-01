import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_file.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

LessonSection _step(String id, {SectionKind kind = SectionKind.info, bool optional = false}) =>
    LessonSection(id: id, title: id, kind: kind, prose: '', optional: optional);

CourseLesson _lesson({
  required String id,
  List<String> sectionIds = const [],
  List<LessonSection>? sections,
  String subject = 'python',
  LessonGroup? group,
  String? feature,
  bool optional = false,
}) => CourseLesson(
  entry: LessonEntry(subject: subject, group: group, order: 1, paths: const {'nl': 'x'}),
  translations: {
    'nl': Lesson(
      id: id,
      title: 'T',
      optional: optional,
      feature: feature,
      sections: sections ?? [for (final sectionId in sectionIds) _step(sectionId)],
    ),
  },
);

/// The ids of the lessons [text] lists, in its order.
List<Object?> _lessonIds(String text) => [
  for (final lesson in (jsonDecode(text) as Map<String, Object?>)['lessons']! as List<Object?>)
    (lesson! as Map<String, Object?>)['id'],
];

/// A file of version 1 holding [lessons], with whatever else [extra] adds.
String _file(List<Object?> lessons, {Map<String, Object?> extra = const {}}) =>
    jsonEncode({'format': ProgressFile.format, 'version': 1, 'lessons': lessons, ...extra});

Matcher _refused(ProgressFileProblem problem) =>
    throwsA(isA<ProgressFileException>().having((error) => error.problem, 'problem', problem));

void main() {
  late ProgressStore store;
  final intro = _lesson(id: 'intro', sectionIds: ['a', 'b', 'c']);
  final loops = _lesson(id: 'loops', sectionIds: ['x', 'y']);
  final course = Course(lessons: [intro, loops]);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = ProgressStore();
  });

  group('writing', () {
    test('names a lesson by its subject and id, and each step with its type, whether it is optional and done', () async {
      final lesson = _lesson(
        id: 'intro',
        group: const LessonGroup(id: 'week-1', titles: {'nl': 'Week 1'}),
        sections: [
          _step('a'),
          _step('b', kind: SectionKind.exercise),
          _step('c', kind: SectionKind.matchPairs, optional: true),
        ],
      );
      await store.markFinished(lesson, 'b');

      final json = jsonDecode(
        ProgressFile.write(Course(lessons: [lesson]), store, exportedAt: DateTime.utc(2026, 10, 31, 14, 2)),
      );

      expect(json, {
        'format': 'i-can-code/progress',
        'version': 1,
        'exportedAt': '2026-10-31T14:02:00.000Z',
        'lessons': [
          {
            'id': 'python/intro',
            'group': 'week-1',
            'optional': false,
            'steps': [
              {'id': 'a', 'type': 'info', 'optional': false, 'done': false},
              {'id': 'b', 'type': 'exercise', 'optional': false, 'done': true},
              {'id': 'c', 'type': 'match-pairs', 'optional': true, 'done': false},
            ],
          },
        ],
      });
    });

    test('lists a lesson with nothing done, and no group for a lesson under none', () {
      final deeper = _lesson(id: 'deeper', sectionIds: ['a'], optional: true);

      final json = jsonDecode(ProgressFile.write(Course(lessons: [deeper]), store, exportedAt: DateTime.utc(2026)));

      expect(json, {
        'format': 'i-can-code/progress',
        'version': 1,
        'exportedAt': '2026-01-01T00:00:00.000Z',
        'lessons': [
          {
            'id': 'python/deeper',
            'optional': true,
            'steps': [
              {'id': 'a', 'type': 'info', 'optional': false, 'done': false},
            ],
          },
        ],
      });
    });

    test('leaves out a lesson a toggle hides, unless something in it is done', () async {
      final shown = _lesson(id: 'shown', sectionIds: ['a']);
      final hidden = _lesson(id: 'hidden', sectionIds: ['a'], feature: 'later');
      final started = _lesson(id: 'started', sectionIds: ['a'], feature: 'later');
      await store.markFinished(started, 'a');

      final text = ProgressFile.write(
        Course(lessons: [shown, hidden, started]),
        store,
        isOn: (_) => false,
        exportedAt: DateTime.utc(2026),
      );

      expect(_lessonIds(text), ['python/shown', 'python/started']);
    });

    test('names the app version when there is one', () {
      final json = jsonDecode(ProgressFile.write(course, store, exportedAt: DateTime.utc(2026), appVersion: '0.15.1'));

      expect(json, containsPair('appVersion', '0.15.1'));
    });

    test('reads back as what was written, a lesson with nothing done included', () async {
      await store.markFinished(intro, 'a');
      await store.markFinished(intro, 'c');

      final text = ProgressFile.write(course, store, exportedAt: DateTime.utc(2026));

      expect(_lessonIds(text), ['python/intro', 'python/loops']);
      expect(ProgressFile.parse(text).finished, {
        'python/intro': {'a', 'c'},
      });
    });
  });

  group('reading', () {
    test('keeps only the steps that are done', () {
      final read = ProgressFile.parse(
        _file([
          {
            'id': 'python/intro',
            'steps': [
              {'id': 'a', 'done': true},
              {'id': 'b', 'done': false},
            ],
          },
        ]),
      );

      expect(read.finished, {
        'python/intro': {'a'},
      });
    });

    test('leaves out a lesson with nothing done', () {
      final read = ProgressFile.parse(
        _file([
          {
            'id': 'python/intro',
            'steps': [
              {'id': 'a', 'done': false},
            ],
          },
          {'id': 'python/loops', 'steps': <Object?>[]},
        ]),
      );

      expect(read.finished, isEmpty);
    });

    test('ignores fields it does not know, so a later field needs no new version', () {
      final read = ProgressFile.parse(
        _file(
          [
            {
              'id': 'python/intro',
              'title': 'Intro',
              'steps': [
                {'id': 'a', 'done': true, 'code': 'print(1)'},
              ],
            },
          ],
          extra: {'device': 'chromebook'},
        ),
      );

      expect(read.finished, {
        'python/intro': {'a'},
      });
    });

    test('joins a lesson listed twice', () {
      final read = ProgressFile.parse(
        _file([
          {
            'id': 'python/intro',
            'steps': [
              {'id': 'a', 'done': true},
            ],
          },
          {
            'id': 'python/intro',
            'steps': [
              {'id': 'b', 'done': true},
            ],
          },
        ]),
      );

      expect(read.finished, {
        'python/intro': {'a', 'b'},
      });
    });

    test('refuses what is not JSON', () {
      expect(() => ProgressFile.parse('<html></html>'), _refused(ProgressFileProblem.notProgress));
    });

    test('refuses JSON that does not say it is a progress file', () {
      expect(() => ProgressFile.parse('{"lessons": []}'), _refused(ProgressFileProblem.notProgress));
      expect(() => ProgressFile.parse('[]'), _refused(ProgressFileProblem.notProgress));
    });

    test('refuses a newer version, whatever shape the rest has', () {
      expect(
        () => ProgressFile.parse(jsonEncode({'format': ProgressFile.format, 'version': 2, 'lessons': 'later'})),
        _refused(ProgressFileProblem.newer),
      );
    });

    test('refuses a file whose version is not a whole number from 1', () {
      for (final version in ['1', 0, 1.5, null]) {
        expect(
          () => ProgressFile.parse(jsonEncode({'format': ProgressFile.format, 'version': version, 'lessons': []})),
          _refused(ProgressFileProblem.damaged),
          reason: 'version $version',
        );
      }
    });

    test('refuses all of a file when one part does not hold', () {
      final broken = <Object?>[
        'python/intro',
        {'id': 'python/intro'},
        {'id': 3, 'steps': []},
        {
          'id': 'python/intro',
          'steps': [
            {'id': 'a'},
          ],
        },
        {
          'id': 'python/intro',
          'steps': [
            {'id': 'a', 'done': 'yes'},
          ],
        },
      ];

      for (final lesson in broken) {
        expect(
          () => ProgressFile.parse(
            _file([
              {
                'id': 'python/loops',
                'steps': [
                  {'id': 'x', 'done': true},
                ],
              },
              lesson,
            ]),
          ),
          _refused(ProgressFileProblem.damaged),
          reason: '$lesson',
        );
      }
      expect(
        () => ProgressFile.parse(jsonEncode({'format': ProgressFile.format, 'version': 1})),
        _refused(ProgressFileProblem.damaged),
      );
    });
  });

  group('matching to the course', () {
    test('places every step the course has, by its own lessons', () {
      final found = const ProgressFile({
        'python/intro': {'a', 'c'},
        'python/loops': {'x'},
      }).matchTo(course);

      expect(found.finished, {
        intro: {'a', 'c'},
        loops: {'x'},
      });
      expect(found.steps, 3);
      expect(found.skipped, 0);
    });

    test('counts what the course does not have, and leaves it out', () {
      final found = const ProgressFile({
        'python/intro': {'a', 'gone'},
        'python/renamed': {'p', 'q'},
      }).matchTo(course);

      expect(found.finished, {
        intro: {'a'},
      });
      expect(found.skipped, 3);
    });

    test('tells subjects apart, since a lesson id is only unique within one', () {
      final other = _lesson(id: 'intro', sectionIds: ['a'], subject: 'csharp');

      final found = const ProgressFile({
        'csharp/intro': {'a'},
      }).matchTo(Course(lessons: [intro, other]));

      expect(found.finished, {
        other: {'a'},
      });
    });
  });
}
