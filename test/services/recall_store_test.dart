import 'package:flutter_test/flutter_test.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/recall_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

CourseLesson _lesson({required String id, List<SectionKind> kinds = const [SectionKind.exercise]}) => CourseLesson(
  entry: LessonEntry(language: 'python', order: 1, slug: id, paths: const {'nl': 'x'}),
  translations: {
    'nl': Lesson(
      id: id,
      title: 'T',
      sections: [
        for (final (index, kind) in kinds.indexed)
          LessonSection(
            id: '$id-$index',
            title: '$id $index',
            kind: kind,
            prose: '',
            starter: kind.isAssignment ? '' : null,
            validator: kind.usesValidator ? 'pass' : null,
            pairs: kind == SectionKind.matchPairs
                ? const [LessonPair(cue: 'a', answer: 'b'), LessonPair(cue: 'c', answer: 'd')]
                : const [],
            program: kind == SectionKind.predictOutput ? 'print(1)' : null,
            lines: kind == SectionKind.orderLines ? const ['print(1)', 'print(2)'] : const [],
          ),
      ],
    ),
  },
);

void main() {
  /// A clock the test moves by hand.
  late DateTime clock;
  late RecallStore store;

  RecallStore build() => RecallStore(now: () => clock);

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    clock = DateTime(2026, 3, 1, 9);
    store = build();
  });

  group('the ladder', () {
    test('a lesson nobody has scheduled is due, which is how this fails', () async {
      // The rule that matters most: storage that was cleared, refused, or
      // written before this existed must not turn the refresher off for good.
      final lesson = _lesson(id: 'intro');

      expect(store.entryFor(lesson), isNull);
      expect(store.isDue(lesson), isTrue);
    });

    test('finishing a lesson puts it a day out, not straight back on the pile', () async {
      final lesson = _lesson(id: 'intro');

      await store.schedule(lesson);

      expect(store.isDue(lesson), isFalse);
      expect(store.entryFor(lesson)?.rung, 0);
      expect(store.entryFor(lesson)?.due, clock.add(const Duration(days: 1)));
    });

    test('a day later it is due', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);

      clock = clock.add(const Duration(days: 1));

      expect(store.isDue(lesson), isTrue);
    });

    test('a refresher that goes well moves the lesson to the next rung', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);
      clock = clock.add(const Duration(days: 1));

      await store.advance(lesson);

      expect(store.entryFor(lesson)?.rung, 1);
      expect(store.isDue(lesson), isFalse);

      clock = clock.add(const Duration(days: 2));
      expect(store.isDue(lesson), isFalse, reason: 'the second rung is three days out, not one');

      clock = clock.add(const Duration(days: 1));
      expect(store.isDue(lesson), isTrue);
    });

    test('past the last rung a lesson settles and stops being offered', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);
      await store.advance(lesson);
      await store.advance(lesson);

      clock = clock.add(const Duration(days: 365));

      expect(store.entryFor(lesson)?.rung, RecallStoreBase.ladder.length);
      expect(store.isDue(lesson), isFalse, reason: 'the ladder has an end');
    });

    test('a refresher that goes badly comes round sooner and takes nothing away', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);
      await store.advance(lesson);

      await store.hold(lesson);

      expect(store.entryFor(lesson)?.rung, 0, reason: 'back one rung');
      expect(store.entryFor(lesson)?.due, clock.add(const Duration(days: 1)));
    });

    test('holding the first rung does not fall off the bottom', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);

      await store.hold(lesson);

      expect(store.entryFor(lesson)?.rung, 0);
    });

    test('scheduling a lesson twice does not push its refresher away again', () async {
      final lesson = _lesson(id: 'intro');
      await store.schedule(lesson);
      final first = store.entryFor(lesson);

      clock = clock.add(const Duration(hours: 20));
      await store.schedule(lesson);

      expect(store.entryFor(lesson), first);
    });
  });

  group('storage', () {
    test('a schedule survives a reload', () async {
      final lesson = _lesson(id: 'intro');
      final course = Course(lessons: [lesson]);
      await store.schedule(lesson);

      final reopened = build();
      await reopened.load(course);

      expect(reopened.entryFor(lesson)?.rung, 0);
      expect(reopened.isDue(lesson), isFalse);
    });

    test('an entry that will not read back is treated as nothing saved', () async {
      // Which is due — see the fail-open rule.
      final lesson = _lesson(id: 'intro');
      final course = Course(lessons: [lesson]);
      await SharedPreferencesAsync().setString(RecallStoreBase.keyFor('python', 'intro'), 'not json at all');

      final reopened = build();
      await reopened.load(course);

      expect(reopened.entryFor(lesson), isNull);
      expect(reopened.isDue(lesson), isTrue);
    });

    test('clearing forgets every schedule', () async {
      final lesson = _lesson(id: 'intro');
      final course = Course(lessons: [lesson]);
      await store.schedule(lesson);

      await store.clear();

      final reopened = build();
      await reopened.load(course);

      expect(reopened.entryFor(lesson), isNull);
    });
  });

  group('recallSession', () {
    test('asks only for the steps whose answer the student produces', () {
      // Producing an answer beats recognising one. A board of tiles is the
      // bottom of that ladder, and an ordering step is recognition wearing a
      // puzzle's clothes — its lines are handed over.
      final lesson = _lesson(
        id: 'intro',
        kinds: [
          SectionKind.info,
          SectionKind.quickExercise,
          SectionKind.matchPairs,
          SectionKind.exercise,
          SectionKind.predictOutput,
          SectionKind.orderLines,
        ],
      );

      final items = recallSession([lesson]);

      expect(items.map((item) => item.section.kind), [
        SectionKind.quickExercise,
        SectionKind.exercise,
        SectionKind.predictOutput,
      ]);
    });

    test('interleaves lessons rather than working through one at a time', () {
      final first = _lesson(id: 'one', kinds: [SectionKind.exercise, SectionKind.exercise]);
      final second = _lesson(id: 'two', kinds: [SectionKind.exercise, SectionKind.exercise]);

      final items = recallSession([first, second]);

      expect(items.map((item) => item.section.id), ['one-0', 'two-0', 'one-1', 'two-1']);
    });

    test('a shorter lesson runs out without stopping the rest', () {
      final short = _lesson(id: 'one', kinds: [SectionKind.exercise]);
      final long = _lesson(id: 'two', kinds: [SectionKind.exercise, SectionKind.exercise]);

      expect(recallSession([short, long]).map((item) => item.section.id), ['one-0', 'two-0', 'two-1']);
    });

    test('a session is capped, so a refresher stays a refresher', () {
      final lesson = _lesson(id: 'one', kinds: List.filled(9, SectionKind.exercise));

      expect(recallSession([lesson]), hasLength(5));
      expect(recallSession([lesson], limit: 2), hasLength(2));
    });

    test('a lesson with nothing to produce asks nothing', () {
      final lesson = _lesson(id: 'one', kinds: [SectionKind.info, SectionKind.matchPairs, SectionKind.orderLines]);

      expect(recallSession([lesson]), isEmpty);
    });
  });
}
