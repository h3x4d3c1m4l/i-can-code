import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';

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
}
