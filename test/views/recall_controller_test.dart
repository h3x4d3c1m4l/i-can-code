import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/progress/recall_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_controller.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A runtime whose runs are answered by the test, so a verdict can be handed
/// over line by line.
class _StubRuntime implements PythonRuntime {

  Completer<PythonResult>? _pending;

  @override
  bool get isSupported => true;

  @override
  String? get version => 'Python 3.14.0';

  @override
  Future<void> ready() async {}

  @override
  Future<PythonResult> run(String code, {String stdin = ''}) => (_pending = Completer<PythonResult>()).future;

  @override
  Future<void> cancel() async {
    _take()?.complete(const PythonResult(stdout: '', stderr: 'Stopped.', exitCode: 130));
  }

  void finish({required bool passed, String output = ''}) {
    _take()?.complete(
      PythonResult(
        stdout: '$output${PythonAttemptRunner.sentinel}${jsonEncode({'ok': passed, 'output': output})}\n',
        stderr: '',
      ),
    );
  }

  Completer<PythonResult>? _take() {
    final pending = _pending;
    _pending = null;
    return pending;
  }

  @override
  void dispose() {}

}

/// One exercise and one prediction, which is what a refresher draws from.
const List<LessonSection> _sections = [
  LessonSection(id: 'write', title: 'Schrijven', kind: SectionKind.exercise, prose: '', starter: '', validator: 'pass'),
  LessonSection(id: 'guess', title: 'Raden', kind: SectionKind.predictOutput, prose: '', program: 'print(42)'),
];

void main() {
  late _StubRuntime runtime;
  late CourseLesson lesson;
  var clock = DateTime(2026, 3, 1, 9);

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    clock = DateTime(2026, 3, 1, 9);
    runtime = _StubRuntime();

    lesson = CourseLesson(
      entry: Course.entriesFrom(['assets/lessons/python/01-loops.nl.md']).single,
      translations: {'nl': Lesson(id: 'loops', title: 'Loops', sections: _sections)},
    );

    GetIt.I
      ..registerSingleton<Course>(Course(lessons: [lesson]))
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<RecallStore>(RecallStore(now: () => clock))
      ..registerSingleton<PythonRuntime>(runtime)
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(runtime));

    // Finished, and never scheduled — which is due. See the fail-open rule.
    for (final section in _sections) {
      await GetIt.I<ProgressStore>().markFinished(lesson, section.id);
    }
  });

  tearDown(GetIt.I.reset);

  (RecallScreenController, RecallScreenViewModel) open() {
    final accessor = BuildContextAccessor();
    final viewModel = RecallScreenViewModel(contextAccessor: accessor, languageSlug: 'learn-python');

    return (RecallScreenController(viewModel: viewModel, contextAccessor: accessor), viewModel);
  }

  test('a refresher draws the written step and the predicted one', () {
    final (_, viewModel) = open();

    expect(viewModel.items.map((item) => item.section.id), ['write', 'guess']);
  });

  test('a right prediction is what counts as knowing it', () async {
    final (controller, viewModel) = open();
    viewModel.advance();

    unawaited(controller.predict(_sections[1], '42'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();

    expect(viewModel.passed, contains(1));
  });

  test('a wrong prediction does not, though the answer is still shown', () async {
    // The one place this differs from the same step inside a lesson, where
    // seeing the answer *is* the exercise and a wrong guess still completes it.
    // Here the question is whether it was retained, and that feeds the ladder.
    final (controller, viewModel) = open();
    viewModel.advance();

    unawaited(controller.predict(_sections[1], 'iets anders'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();

    expect(viewModel.passed, isNot(contains(1)));
    expect(viewModel.attempt?.output, '42\n', reason: 'wrong costs a rung, never the answer');
    expect(viewModel.prediction, 'iets anders', reason: 'frozen, so typing on cannot flip the verdict');
  });

  test('a clean run through moves the lesson up a rung', () async {
    final (controller, viewModel) = open();
    final recall = GetIt.I<RecallStore>();

    unawaited(controller.run(_sections[0], 'print(1)'));
    await pumpEventQueue();
    runtime.finish(passed: true);
    await pumpEventQueue();
    await controller.next();

    unawaited(controller.predict(_sections[1], '42'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();
    await controller.next();

    expect(viewModel.completed, isTrue);
    expect(recall.entryFor(lesson)?.rung, 1);
    expect(recall.isDue(lesson), isFalse);
  });

  test('a miss brings the lesson round sooner and takes no tick away', () async {
    final (controller, viewModel) = open();
    final recall = GetIt.I<RecallStore>();

    unawaited(controller.run(_sections[0], 'oops'));
    await pumpEventQueue();
    runtime.finish(passed: false);
    await pumpEventQueue();
    await controller.next();
    await controller.next();

    expect(viewModel.completed, isTrue);
    expect(recall.entryFor(lesson)?.rung, 0, reason: 'back to the first rung');
    expect(
      GetIt.I<ProgressStore>().isFinished(lesson),
      isTrue,
      reason: 'a refresher never unfinishes a lesson',
    );
  });

  test('every item offers a way on, passed or not', () async {
    // A refresher measures what was kept; it must never be a door the student
    // cannot get through.
    final (controller, viewModel) = open();

    await controller.next();

    expect(viewModel.index, 1);
    expect(viewModel.passed, isEmpty);
  });
}
