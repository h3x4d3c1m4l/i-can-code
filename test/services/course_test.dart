import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/vm/vm_image.dart';

/// An asset bundle holding the course bundle and nothing else.
class _CourseBundle extends CachingAssetBundle {

  final Map<String, String> files;

  _CourseBundle(this.files);

  @override
  Future<ByteData> load(String key) async {
    if (key != Course.bundleAsset) throw StateError('Unable to load asset: "$key".');

    return ByteData.sublistView(utf8.encode(jsonEncode(files)));
  }

}

const String _root = 'assets/lessons/python';

/// A lesson that parses, with [id] as its only distinguishing mark.
String _lessonCalled(String id) =>
    '# $id\n\n```metadata\nid: $id\n```\n\n## S\n\n```metadata\ntype: info\nid: s\n```\n\nprose\n';

void main() {
  group('Course.load', () {
    final lesson = File('test/fixtures/lesson.md').readAsStringSync();

    test('reads every lesson out of the one bundle, in the order the contents give', () async {
      final course = await Course.load(
        bundle: _CourseBundle({
          '$_root/contents.en.md': '- [Second](b.en.md)\n- [First](a.en.md)\n',
          '$_root/contents.nl.md': '- [Tweede](b.nl.md)\n- [Eerste](a.nl.md)\n',
          '$_root/a.en.md': _lessonCalled('first'),
          '$_root/a.nl.md': _lessonCalled('first'),
          '$_root/b.en.md': _lessonCalled('second'),
          '$_root/b.nl.md': _lessonCalled('second'),
          'assets/lessons/README.md': '# Not a lesson',
        }),
      );

      expect(course.lessons.map((l) => l.forLocale('en').id), ['second', 'first']);
      expect(course.lessons.map((l) => l.entry.order), [1, 2]);
      expect(course.lessons.first.translations.keys, unorderedEquals(['en', 'nl']));
    });

    test('reads a lesson written the way an author writes one', () async {
      final course = await Course.load(
        bundle: _CourseBundle({'$_root/contents.en.md': '- [Fixture](lesson.md)\n', '$_root/lesson.md': lesson}),
      );

      expect(course.lessons.single.forLocale('en').sections, isNotEmpty);
    });

    test('a bundle with nothing in it is a course with no lessons', () async {
      final course = await Course.load(bundle: _CourseBundle(const {}));

      expect(course.lessons, isEmpty);
    });

    test('a malformed lesson names its file', () async {
      const broken = '# Broken\n\n```metadata\nid: broken\n```\n\n## A step\n\nNo metadata block.\n';
      const path = '$_root/broken.nl.md';

      await expectLater(
        Course.load(bundle: _CourseBundle(const {'$_root/contents.nl.md': '- [Broken](broken.nl.md)\n', path: broken})),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', startsWith('$path: '))),
      );
    });

    test('translations of one lesson that name different feature toggles are refused', () async {
      expect(
        () => Course.load(
          bundle: _CourseBundle({
            '$_root/contents.en.md': '- [a](a.en.md)\n',
            '$_root/contents.nl.md': '- [a](a.nl.md)\n',
            '$_root/a.en.md': _lessonCalled('a').replaceFirst('id: a\n', 'id: a\nfeature: files\n'),
            '$_root/a.nl.md': _lessonCalled('a'),
          }),
        ),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('names the feature'))),
      );
    });

    test('two locales that list a different lesson in the same place are refused', () async {
      // Translations are paired by position, so a contents file out of step
      // would show one lesson's Dutch under another's English.
      await expectLater(
        Course.load(
          bundle: _CourseBundle({
            '$_root/contents.en.md': '- [First](a.md)\n- [Second](b.md)\n',
            '$_root/contents.nl.md': '- [Tweede](b.md)\n- [Eerste](a.md)\n',
            '$_root/a.md': _lessonCalled('first'),
            '$_root/b.md': _lessonCalled('second'),
          }),
        ),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('same lessons in the same order'))),
      );
    });
  });

  group('Course.entriesFrom', () {
    test('lists a subject\'s lessons in the order its contents file gives, whatever the files are called', () {
      final entries = Course.entriesFrom(const {
        '$_root/contents.nl.md': '- [Hallo](z-hello.nl.md)\n- [Variabelen](week-1/00-variables.nl.md)\n',
        '$_root/week-1/00-variables.nl.md': '',
        '$_root/z-hello.nl.md': '',
      });

      expect(entries.map((e) => e.paths['nl']), ['$_root/z-hello.nl.md', '$_root/week-1/00-variables.nl.md']);
      expect(entries.map((e) => e.order), [1, 2]);
      expect(entries.map((e) => e.listedTitles['nl']), ['Hallo', 'Variabelen']);
      expect(entries.every((e) => e.subject == 'python'), isTrue);
    });

    test('pairs a lesson\'s translations by where each contents file lists them', () {
      final entries = Course.entriesFrom(const {
        '$_root/contents.en.md': '- [Hello](hello.en.md)\n',
        '$_root/contents.nl.md': '- [Hallo](hallo.nl.md)\n',
        '$_root/hello.en.md': '',
        '$_root/hallo.nl.md': '',
      });

      expect(entries.single.paths, {'en': '$_root/hello.en.md', 'nl': '$_root/hallo.nl.md'});
    });

    test('a lesson with no translation is linked to in the language it has', () {
      final entries = Course.entriesFrom(const {
        '$_root/contents.en.md': '- [Hallo](hallo.nl.md)\n',
        '$_root/contents.nl.md': '- [Hallo](hallo.nl.md)\n',
        '$_root/hallo.nl.md': '',
      });

      expect(entries.single.paths, {'en': '$_root/hallo.nl.md', 'nl': '$_root/hallo.nl.md'});
    });

    test('a group carries its id and its heading in every locale', () {
      final entries = Course.entriesFrom(const {
        '$_root/contents.en.md': '- [Intro](intro.md)\n# Week 1 · The basics {#week-1}\n- [A](a.md)\n- [B](b.md)\n',
        '$_root/contents.nl.md': '- [Intro](intro.md)\n# Week 1 · De basis {#week-1}\n- [A](a.md)\n- [B](b.md)\n',
        '$_root/intro.md': '',
        '$_root/a.md': '',
        '$_root/b.md': '',
      });

      expect(entries.map((e) => e.group?.id), [null, 'week-1', 'week-1']);
      expect(entries[1].group!.titleFor('nl'), 'Week 1 · De basis');
      expect(entries[1].group!.titleFor('en'), 'Week 1 · The basics');
      expect(entries[1].group!.titleFor('de'), 'Week 1 · The basics', reason: 'English, as a lesson falls back');
    });

    test('a group carries the feature toggle its heading names', () {
      final entries = Course.entriesFrom({
        '$_root/contents.nl.md': '# Week 5 {#week-5 feature=files}\n- [A](a.md)\n',
        '$_root/a.md': '',
      });

      expect(entries.single.group?.feature, 'files');
    });

    test('contents files that give one group different feature toggles are refused', () {
      expect(
        () => Course.entriesFrom({
          '$_root/contents.en.md': '# Week 5 {#week-5 feature=files}\n- [A](a.en.md)\n',
          '$_root/contents.nl.md': '# Week 5 {#week-5}\n- [A](a.nl.md)\n',
          '$_root/a.en.md': '',
          '$_root/a.nl.md': '',
        }),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('different feature'))),
      );
    });

    test('contents files of one subject that differ in shape are refused', () {
      const lessons = {'$_root/a.md': '', '$_root/b.md': ''};

      expect(
        () => Course.entriesFrom(const {
          '$_root/contents.en.md': '- [A](a.md)\n- [B](b.md)\n',
          '$_root/contents.nl.md': '- [A](a.md)\n',
          ...lessons,
        }),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('lists 1 lessons'))),
      );
      expect(
        () => Course.entriesFrom(const {
          '$_root/contents.en.md': '# One {#one}\n- [A](a.md)\n- [B](b.md)\n',
          '$_root/contents.nl.md': '# Een {#one}\n- [A](a.md)\n---\n- [B](b.md)\n',
          ...lessons,
        }),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('under a different group'))),
      );
    });

    test('a listed file that is not there is refused, by name', () {
      expect(
        () => Course.entriesFrom(const {'$_root/contents.nl.md': '- [Weg](gone.nl.md)\n'}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('$_root/contents.nl.md'), contains('gone.nl.md')),
          ),
        ),
      );
    });

    test('a malformed contents file names itself and the line', () {
      expect(
        () => Course.entriesFrom(const {'$_root/contents.nl.md': '\n## Te diep\n'}),
        throwsA(
          isA<FormatException>().having((e) => e.message, 'message', startsWith('$_root/contents.nl.md: Line 2')),
        ),
      );
    });

    test('a subject with files and no contents is refused, rather than opening on an empty catalog', () {
      expect(
        () => Course.entriesFrom(const {'$_root/01-hello.nl.md': ''}),
        throwsA(isA<FormatException>().having((e) => e.message, 'message', contains('no contents.<locale>.md'))),
      );
    });

    test('ignores what is not under a subject', () {
      final entries = Course.entriesFrom(const {
        'assets/lessons/README.md': '# Not a lesson',
        'assets/fonts/Lexend-Variable.ttf': '',
        '$_root/contents.nl.md': '- [Ok](ok.nl.md)\n',
        '$_root/ok.nl.md': '',
        '$_root/notes.txt': 'not markdown',
        '$_root/README.md': 'listed nowhere, and that is fine',
      });

      expect(entries, hasLength(1));
    });
  });

  /// A course of `count` python lessons plus one lesson in another subject.
  Course courseOf(int count) => Course(
    lessons: [
      // Sorted by subject, as a loaded course is.
      const CourseLesson(
        entry: LessonEntry(subject: 'javascript', order: 1, paths: {'nl': 'x'}),
        translations: {'nl': Lesson(id: 'hello', title: 'hello', sections: [])},
      ),
      for (var order = 1; order <= count; order++)
        CourseLesson(
          entry: LessonEntry(subject: 'python', order: order, paths: const {'nl': 'x'}),
          translations: {'nl': Lesson(id: 'lesson-$order', title: 'lesson-$order', sections: const [])},
        ),
    ],
  );

  String idOf(CourseLesson lesson) => lesson.translations.values.first.id;

  test('subjects are listed once each, in course order', () {
    final course = courseOf(2);

    expect(course.subjects, ['javascript', 'python']);
    expect(course.lessonsFor('python').map(idOf), ['lesson-1', 'lesson-2']);
    expect(course.lessonsFor('ruby'), isEmpty);
  });

  group('feature toggles', () {
    const files = LessonGroup(id: 'week-5', titles: {'nl': 'Week 5'}, feature: 'files');

    CourseLesson lesson(String id, {LessonGroup? group, String? feature}) => CourseLesson(
      entry: LessonEntry(subject: 'python', order: 1, group: group, paths: const {'nl': 'x'}),
      translations: {'nl': Lesson(id: id, title: id, feature: feature, sections: const [])},
    );

    final course = Course(
      lessons: [
        lesson('always'),
        lesson('own', feature: 'csv'),
        lesson('grouped', group: files),
        lesson('both', group: files, feature: 'csv'),
        lesson('last'),
      ],
    );

    List<String> shown(bool Function(String feature) isOn) => course.visibleWith(isOn).lessons.map(idOf).toList();

    test('are every name the course uses, on a lesson or a group, once each and sorted', () {
      expect(course.features, ['csv', 'files']);
      expect(courseOf(2).features, isEmpty);
    });

    test('hide a lesson until its own toggle and its group\'s are both on', () {
      expect(shown((_) => false), ['always', 'last']);
      expect(shown((feature) => feature == 'csv'), ['always', 'own', 'last']);
      expect(shown((feature) => feature == 'files'), ['always', 'grouped', 'last']);
      expect(shown((_) => true), ['always', 'own', 'grouped', 'both', 'last']);
    });

    test('are skipped by lessonAfter, which leads on from a hidden lesson too', () {
      bool none(String _) => false;

      expect(idOf(course.lessonAfter(course.lessons.first, isOn: none)!), 'last');
      // Opened by its address, a hidden lesson still has a way on.
      expect(idOf(course.lessonAfter(course.lessons[2], isOn: none)!), 'last');
      expect(idOf(course.lessonAfter(course.lessons.first)!), 'own', reason: 'without isOn nothing is skipped');
    });
  });

  group('lessonAfter', () {
    test('answers with the next lesson in course order', () {
      final course = courseOf(3);
      final first = course.lessonsFor('python').first;

      expect(idOf(course.lessonAfter(first)!), 'lesson-2');
    });

    test('the last lesson of a subject has none, rather than the next subject\'s first', () {
      final course = courseOf(2);

      expect(course.lessonAfter(course.lessonsFor('javascript').last), isNull);
      expect(course.lessonAfter(course.lessonsFor('python').last), isNull);
    });

    test('a lesson from a second parse of the same course still finds its successor', () {
      final course = courseOf(2);
      // Matched on the lesson's id, so an equal-but-not-identical lesson works.
      final copy = CourseLesson(
        entry: course.lessonsFor('python').first.entry,
        translations: const {'nl': Lesson(id: 'lesson-1', title: 'Anders', sections: [])},
      );

      expect(idOf(course.lessonAfter(copy)!), 'lesson-2');
    });
  });

  test('a subject round-trips through its URL slug', () {
    expect(subjectSlug('python'), 'learn-python');
    expect(subjectFromSlug('learn-python'), 'python');
    expect(subjectFromSlug(subjectSlug('javascript')), 'javascript');
  });

  test('a slug that is not one of ours is rejected rather than guessed at', () {
    // `/:subjectSlug` is a catch-all, so it will be handed any unknown path.
    expect(subjectFromSlug('python'), isNull);
    expect(subjectFromSlug('initialization'), isNull);
    expect(subjectFromSlug(''), isNull);
  });

  test('a subject is named as a reader would write it', () {
    expect(subjectLabel('python'), 'Python');
    expect(subjectLabel('javascript'), 'Javascript');
    expect(subjectLabel(''), '');
  });

  test('a subject the table does not name has no emoji, and its card falls back', () {
    expect(subjectEmoji('python'), '\u{1F40D}');
    // A subject directory may be added without touching the table.
    expect(subjectEmoji('javascript'), isNull);
  });

  test('Python indents by four spaces, and a subject the table does not name by two', () {
    expect(subjectIndentSize('python'), 4);
    expect(subjectIndentSize('javascript'), 2);
  });

  test('windows are offered only by a build that ships the machine\'s image', () {
    expect(subjectHasWindows('python', imageIncluded: true), isTrue);
    expect(subjectHasWindows('javascript', imageIncluded: true), isFalse);
    // What a deploy without the image gets: no card for a page that can only 404.
    expect(subjectHasWindows('python', imageIncluded: false), isFalse);
    expect(subjectHasWindows('python'), vmImageIncluded);
  });
}
