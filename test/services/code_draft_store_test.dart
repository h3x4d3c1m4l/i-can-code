import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/code_draft_store.dart';
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
          LessonSection(id: sectionId, title: sectionId, kind: SectionKind.exercise, prose: '', starter: ''),
      ],
    ),
  },
);

final CourseLesson _intro = _lesson(id: 'intro', sectionIds: ['a', 'b']);

/// What a fresh store over the same storage reads back, which is what a reload
/// produces.
Future<String?> _stored(CourseLesson lesson, String sectionId) async {
  final reloaded = CodeDraftStore();
  await reloaded.load(Course(lessons: [lesson]));
  return reloaded.codeFor(lesson, sectionId);
}

void main() {
  late CodeDraftStore store;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    store = CodeDraftStore();
  });

  // Cancels the pending write, which would otherwise outlive the test.
  tearDown(() => store.flush());

  test('a section nobody typed into has no draft', () {
    expect(store.codeFor(_intro, 'a'), isNull);
    expect(store.hasDrafts, isFalse);
  });

  test('a draft is kept in memory at once, and in storage from the next flush', () async {
    store.keep(_intro, 'a', 'print(1)');
    expect(store.codeFor(_intro, 'a'), 'print(1)');
    expect(await _stored(_intro, 'a'), isNull);

    await store.flush();
    expect(await _stored(_intro, 'a'), 'print(1)');
    expect(await _stored(_intro, 'b'), isNull);
  });

  testWidgets('a pause in typing writes it out', (tester) async {
    store.keep(_intro, 'a', 'print(1)');

    await tester.pump(CodeDraftStoreBase.writeDelay - const Duration(milliseconds: 1));
    expect(await _stored(_intro, 'a'), isNull);

    await tester.pump(const Duration(milliseconds: 1));
    expect(await _stored(_intro, 'a'), 'print(1)');
  });

  testWidgets('typing again puts the write off, and the last code is the one written', (tester) async {
    const half = Duration(milliseconds: 600);

    store.keep(_intro, 'a', 'print(1)');
    await tester.pump(half);
    store.keep(_intro, 'a', 'print(12)');
    await tester.pump(half);
    expect(await _stored(_intro, 'a'), isNull, reason: 'the second keystroke started the pause over');

    await tester.pump(half);
    expect(await _stored(_intro, 'a'), 'print(12)');
  });

  test('a forgotten draft is gone from storage too', () async {
    store.keep(_intro, 'a', 'print(1)');
    await store.flush();

    store.forget(_intro, 'a');
    expect(store.codeFor(_intro, 'a'), isNull);

    await store.flush();
    expect(await _stored(_intro, 'a'), isNull);
  });

  test('a reordered lesson keeps each draft on its own section', () async {
    store.keep(_intro, 'b', 'print(2)');
    await store.flush();

    final reordered = _lesson(id: 'intro', sectionIds: ['b', 'a']);
    expect(await _stored(reordered, 'b'), 'print(2)');
    expect(await _stored(reordered, 'a'), isNull);
  });

  test('clearing forgets everything, and outlives the store', () async {
    store
      ..keep(_intro, 'a', 'print(1)')
      ..keep(_intro, 'b', 'print(2)');
    await store.flush();
    expect(store.hasDrafts, isTrue);

    await store.clear();
    expect(store.hasDrafts, isFalse);
    expect(await _stored(_intro, 'a'), isNull, reason: 'the clear has to reach storage, not just memory');
    expect(await _stored(_intro, 'b'), isNull);
  });

  test('code of a section that is gone still counts, and clearing reaches it', () async {
    // Typed under the lesson's old id, which a rename leaves behind.
    store.keep(_lesson(id: 'input-and-output', sectionIds: ['a']), 'a', 'print(1)');
    await store.flush();

    final renamed = CodeDraftStore();
    await renamed.load(Course(lessons: [_intro]));
    expect(renamed.hasDrafts, isTrue, reason: 'nothing shows it, but there is something to clear');

    await renamed.clear();
    final reloaded = CodeDraftStore();
    await reloaded.load(Course(lessons: [_intro]));
    expect(reloaded.hasDrafts, isFalse);
  });

  test('clearing also reaches a draft forgotten since the last write', () async {
    store.keep(_intro, 'a', 'print(1)');
    await store.flush();
    store.forget(_intro, 'a');

    await store.clear();
    expect(await _stored(_intro, 'a'), isNull);
  });

  testWidgets('clearing drops a write that was still waiting', (tester) async {
    store.keep(_intro, 'a', 'print(1)');

    await store.clear();
    await tester.pump(CodeDraftStoreBase.writeDelay * 2);
    expect(await _stored(_intro, 'a'), isNull);
  });

  test('sections of the same name in different lessons are kept apart', () {
    expect(CodeDraftStoreBase.keyFor('python', 'intro', 'a'), isNot(CodeDraftStoreBase.keyFor('python', 'loops', 'a')));
    expect(CodeDraftStoreBase.keyFor('python', 'intro', 'a'), isNot(CodeDraftStoreBase.keyFor('java', 'intro', 'a')));
  });

  group('a project', () {
    final project = CourseLesson(
      entry: const LessonEntry(language: 'python', track: 'microbit', order: 1, slug: 'dice', paths: {'nl': 'x'}),
      translations: {
        'nl': const Lesson(
          id: 'dice',
          title: 'T',
          layout: LessonLayout.project,
          runtime: LessonRuntime.microbit,
          sections: [
            LessonSection(id: 'roll', title: 'roll', kind: SectionKind.task, prose: '', doneWhen: 'x'),
            LessonSection(id: 'shake', title: 'shake', kind: SectionKind.task, prose: '', doneWhen: 'x'),
          ],
        ),
      },
    );

    Future<CodeDraftStore> reload() async {
      final reloaded = CodeDraftStore();
      await reloaded.load(Course(lessons: [project]));
      return reloaded;
    }

    test('keeps one program for all its tasks, and a snapshot per task', () async {
      store
        ..keepWork(project, 'print(2)')
        ..keepSnapshot(project, 'roll', 'print(1)');
      await store.flush();

      final reloaded = await reload();
      expect(reloaded.workFor(project), 'print(2)');
      expect(reloaded.snapshotFor(project, 'roll'), 'print(1)');
      expect(reloaded.snapshotFor(project, 'shake'), isNull);
    });

    test('forgetting the program leaves the snapshots alone', () async {
      store
        ..keepWork(project, 'print(2)')
        ..keepSnapshot(project, 'roll', 'print(1)')
        ..forgetWork(project);
      await store.flush();

      final reloaded = await reload();
      expect(reloaded.workFor(project), isNull);
      expect(reloaded.snapshotFor(project, 'roll'), 'print(1)');
    });

    test('clearing forgets both', () async {
      store
        ..keepWork(project, 'print(2)')
        ..keepSnapshot(project, 'roll', 'print(1)');
      await store.clear();

      final reloaded = await reload();
      expect(reloaded.workFor(project), isNull);
      expect(reloaded.snapshotFor(project, 'roll'), isNull);
    });
  });
}
