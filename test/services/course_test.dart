import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

void main() {
  test('languages are listed once each, in course order', () {
    final entries = Course.entriesFrom([
      'assets/lessons/python/02-variables.nl.md',
      'assets/lessons/python/01-input-and-output.nl.md',
      'assets/lessons/javascript/01-hello.nl.md',
    ]);
    final course = Course(
      lessons: [for (final entry in entries) CourseLesson(entry: entry, translations: const {})],
    );

    // Sorted by language then order, so javascript's single lesson comes first.
    expect(course.languages, ['javascript', 'python']);
    expect(course.lessonsFor('python').map((l) => l.entry.slug), ['input-and-output', 'variables']);
    expect(course.lessonsFor('ruby'), isEmpty);
  });

  group('lessonAfter', () {
    /// A course of `count` python lessons plus one lesson in another language,
    /// which must never be offered as "next".
    Course courseOf(int count) {
      final entries = Course.entriesFrom([
        for (var order = 1; order <= count; order++)
          'assets/lessons/python/0$order-lesson-$order.nl.md',
        'assets/lessons/javascript/01-hello.nl.md',
      ]);

      return Course(
        lessons: [
          for (final entry in entries)
            CourseLesson(
              entry: entry,
              translations: {'nl': Lesson(id: entry.slug, title: entry.slug, sections: const [])},
            ),
        ],
      );
    }

    test('answers with the next lesson in course order', () {
      final course = courseOf(3);
      final first = course.lessonsFor('python').first;

      expect(course.lessonAfter(first)!.entry.slug, 'lesson-2');
    });

    test('the last lesson of a language has none, rather than the next language\'s first', () {
      final course = courseOf(2);
      final last = course.lessonsFor('python').last;

      expect(course.lessonAfter(last), isNull);
    });

    test('a lesson from a second parse of the same course still finds its successor', () {
      final course = courseOf(2);
      // Matched on the lesson's id, so an equal-but-not-identical lesson works.
      final copy = CourseLesson(
        entry: course.lessonsFor('python').first.entry,
        translations: {'nl': Lesson(id: 'lesson-1', title: 'Anders', sections: const [])},
      );

      expect(course.lessonAfter(copy)!.entry.slug, 'lesson-2');
    });
  });

  test('a language round-trips through its URL slug', () {
    expect(languageSlug('python'), 'learn-python');
    expect(languageFromSlug('learn-python'), 'python');
    expect(languageFromSlug(languageSlug('javascript')), 'javascript');
  });

  test('a slug that is not one of ours is rejected rather than guessed at', () {
    // `/:languageSlug` is a catch-all, so it will be handed any unknown path.
    expect(languageFromSlug('python'), isNull);
    expect(languageFromSlug('initialization'), isNull);
    expect(languageFromSlug(''), isNull);
  });

  test('a language is named as a reader would write it', () {
    expect(languageLabel('python'), 'Python');
    expect(languageLabel('javascript'), 'Javascript');
    expect(languageLabel(''), '');
  });

  test('a language the table does not name has no emoji, and its card falls back', () {
    expect(languageEmoji('python'), '\u{1F40D}');
    // A language directory may be added without touching the table.
    expect(languageEmoji('javascript'), isNull);
  });
}
