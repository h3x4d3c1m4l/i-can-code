import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

CourseLesson _lesson({required String id, required List<String> sectionIds}) => CourseLesson(
  entry: LessonEntry(language: 'python', order: 1, slug: id, paths: const {'nl': 'x'}),
  translations: {
    'nl': Lesson(
      id: id,
      title: 'T',
      sections: [
        for (final sectionId in sectionIds)
          LessonSection(id: sectionId, title: sectionId, kind: SectionKind.info, prose: ''),
      ],
    ),
  },
);

void main() {
  late ProgressStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = ProgressStore();
  });

  test('a lesson starts with nothing done', () {
    final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);

    expect(store.completedSteps(lesson), 0);
    expect(store.isStarted(lesson), isFalse);
    expect(store.isFinished(lesson), isFalse);
  });

  test('finishing every section finishes the lesson', () async {
    final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);

    await store.markFinished(lesson, 'a');
    expect(store.completedSteps(lesson), 1);
    expect(store.isStarted(lesson), isTrue);
    expect(store.isFinished(lesson), isFalse);

    await store.markFinished(lesson, 'b');
    expect(store.isFinished(lesson), isTrue);
  });

  test('a section marked twice counts once', () async {
    final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);

    await store.markFinished(lesson, 'a');
    await store.markFinished(lesson, 'a');

    expect(store.completedSteps(lesson), 1);
  });

  test('progress survives a reload', () async {
    final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);
    await store.markFinished(lesson, 'a');

    // A fresh store over the same storage is what a reload produces.
    final reloaded = ProgressStore();
    await reloaded.load(Course(lessons: [lesson]));

    expect(reloaded.completedSteps(lesson), 1);
  });

  group('when the author edits the lesson', () {
    test('a reordered section keeps its tick', () async {
      await store.markFinished(_lesson(id: 'intro', sectionIds: ['a', 'b']), 'b');

      // Same sections, other way round. Keying on position would move the tick.
      final reordered = _lesson(id: 'intro', sectionIds: ['b', 'a']);
      expect(store.completedSteps(reordered), 1);
      expect(store.finishedIn(reordered), {'b'});
    });

    test('an inserted section does not become finished', () async {
      await store.markFinished(_lesson(id: 'intro', sectionIds: ['a', 'b']), 'a');

      final grown = _lesson(id: 'intro', sectionIds: ['a', 'new', 'b']);
      expect(store.completedSteps(grown), 1);
      expect(store.isFinished(grown), isFalse);
    });

    test('a removed section stops counting', () async {
      final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);
      await store.markFinished(lesson, 'a');
      await store.markFinished(lesson, 'b');

      // 'b' is gone, so the one remaining section is all there is to finish.
      final shrunk = _lesson(id: 'intro', sectionIds: ['a']);
      expect(store.completedSteps(shrunk), 1);
      expect(store.isFinished(shrunk), isTrue);
    });
  });

  group('resuming', () {
    test('a fresh lesson opens at the beginning', () {
      expect(store.firstUnfinishedStep(_lesson(id: 'intro', sectionIds: ['a', 'b', 'c'])), 0);
    });

    test('a part-finished lesson opens at the first step still to do', () async {
      final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b', 'c']);
      await store.markFinished(lesson, 'a');

      expect(store.firstUnfinishedStep(lesson), 1);
    });

    test('a gap is resumed at the gap, not after the last tick', () async {
      final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b', 'c']);
      await store.markFinished(lesson, 'c');

      expect(store.firstUnfinishedStep(lesson), 0);
    });

    test('a finished lesson opens at the beginning again', () async {
      final lesson = _lesson(id: 'intro', sectionIds: ['a', 'b']);
      await store.markFinished(lesson, 'a');
      await store.markFinished(lesson, 'b');

      // Nothing left to resume, so revisiting starts over.
      expect(store.firstUnfinishedStep(lesson), 0);
    });
  });

  test('clearing forgets everything, and outlives the store', () async {
    final lesson = _lesson(id: 'intro', sectionIds: ['a']);
    await store.markFinished(lesson, 'a');
    expect(store.hasProgress, isTrue);

    await store.clear();
    expect(store.hasProgress, isFalse);

    final reloaded = ProgressStore();
    await reloaded.load(Course(lessons: [lesson]));
    expect(reloaded.hasProgress, isFalse, reason: 'the clear has to reach storage, not just memory');
  });

  test('lessons of the same name in different languages are kept apart', () {
    expect(
      ProgressStoreBase.keyFor('python', 'intro'),
      isNot(ProgressStoreBase.keyFor('javascript', 'intro')),
    );
  });
}
