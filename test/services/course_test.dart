import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';

void main() {
  test('subjects are listed once each, in course order', () {
    final entries = Course.entriesFrom([
      'assets/lessons/python/02-variables.nl.md',
      'assets/lessons/python/01-hello.nl.md',
      'assets/lessons/javascript/01-hello.nl.md',
    ]);
    final course = Course(
      lessons: [for (final entry in entries) CourseLesson(entry: entry, translations: const {})],
    );

    // Sorted by subject then order, so javascript's single lesson comes first.
    expect(course.subjects, ['javascript', 'python']);
    expect(course.lessonsFor('python').map((l) => l.entry.slug), ['hello', 'variables']);
    expect(course.lessonsFor('ruby'), isEmpty);
  });

  group('lessonAfter', () {
    /// A course of `count` python lessons plus one lesson in another subject,
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

    test('the last lesson of a subject has none, rather than the next subject\'s first', () {
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
}
