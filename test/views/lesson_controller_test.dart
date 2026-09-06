import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_controller.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_view_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A runtime whose runs end only when this test says so — which is what a
/// `sleep(3000)` looks like from the outside.
class _HeldRuntime implements PythonRuntime {

  Completer<PythonResult>? _pending;

  /// How often the runtime was asked to stop. Every stop is a worker
  /// terminated, so the count is what proves a run was actually ended.
  int cancels = 0;

  bool get isRunning => _pending != null;

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
    cancels++;
    // The real one answers the run in flight rather than leaving it hanging,
    // with nothing worth reading in it.
    _take()?.complete(const PythonResult(stdout: '', stderr: 'Stopped.', exitCode: 130));
  }

  /// Answers the run in flight the way a program that finished would.
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

/// Two exercises, so there is a step to move on from and a last step to end on.
const List<LessonSection> _sections = [
  LessonSection(id: 'first', title: 'Eerste', kind: SectionKind.exercise, prose: '', starter: ''),
  LessonSection(id: 'guess', title: 'Raden', kind: SectionKind.predictOutput, prose: '', program: 'print(42)'),
  LessonSection(id: 'last', title: 'Laatste', kind: SectionKind.exercise, prose: '', starter: ''),
];

void main() {
  late _HeldRuntime runtime;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
    runtime = _HeldRuntime();

    GetIt.I
      ..registerSingleton<Course>(
        Course(
          lessons: [
            CourseLesson(
              entry: Course.entriesFrom(['assets/lessons/python/01-loops.nl.md']).single,
              translations: {'nl': Lesson(id: 'loops', title: 'Loops', sections: _sections)},
            ),
          ],
        ),
      )
      ..registerSingleton<ProgressStore>(ProgressStore())
      ..registerSingleton<PythonRuntime>(runtime)
      ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(runtime));
  });

  tearDown(GetIt.I.reset);

  /// A controller sitting on [sectionId], with its run already in flight.
  ///
  /// The section id is always one the lesson has, so nothing schedules the
  /// post-frame address rewrite — that would reach for a router this test has
  /// no tree to hold.
  Future<(LessonScreenController, LessonScreenViewModel)> running({String sectionId = 'first'}) async {
    final accessor = BuildContextAccessor();
    final viewModel = LessonScreenViewModel(contextAccessor: accessor, lessonId: 'loops', sectionId: sectionId);
    final controller = LessonScreenController(viewModel: viewModel, contextAccessor: accessor);

    unawaited(controller.run(_sections.firstWhere((s) => s.id == sectionId), 'time.sleep(3000)'));
    await pumpEventQueue();

    expect(viewModel.running, isTrue);
    expect(runtime.isRunning, isTrue, reason: 'the run has to reach the runtime before it can be stopped');

    return (controller, viewModel);
  }

  /// A controller sitting on the predict-output step, with nothing yet asked.
  (LessonScreenController, LessonScreenViewModel) predicting() {
    final accessor = BuildContextAccessor();
    final viewModel = LessonScreenViewModel(contextAccessor: accessor, lessonId: 'loops', sectionId: 'guess');

    return (LessonScreenController(viewModel: viewModel, contextAccessor: accessor), viewModel);
  }

  test('a prediction runs the lesson\'s own program, with no checks on it', () async {
    final (controller, viewModel) = predicting();
    final section = _sections.firstWhere((s) => s.id == 'guess');

    unawaited(controller.predict(section, 'iets anders'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();

    expect(viewModel.attempt?.output, '42\n');
    // Frozen at the moment of asking, so typing into the box afterwards cannot
    // rewrite the verdict on the screen.
    expect(viewModel.prediction, 'iets anders');
  });

  test('a wrong prediction still completes the step', () async {
    // Seeing the difference is the exercise, and there is nothing being graded
    // here: what decides the tick is that the program ran, not that the guess
    // was right.
    final (controller, viewModel) = predicting();
    final section = _sections.firstWhere((s) => s.id == 'guess');

    unawaited(controller.predict(section, 'volstrekt fout'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();

    expect(viewModel.passed, contains(viewModel.step));
    expect(GetIt.I<ProgressStore>().finishedIn(GetIt.I<Course>().lessons.single), contains('guess'));
  });

  test('leaving a predict step drops the answer that arrives after it', () async {
    final (controller, viewModel) = predicting();
    final section = _sections.firstWhere((s) => s.id == 'guess');

    unawaited(controller.predict(section, 'iets'));
    await pumpEventQueue();
    await controller.stop();
    runtime.finish(passed: true, output: '42\n');
    await pumpEventQueue();

    expect(viewModel.attempt, isNull, reason: 'a stopped run reports no verdict');
    expect(viewModel.prediction, isNull, reason: 'the prediction belongs to the verdict it was asked for');
  });

  test('Stop ends the run and leaves no verdict behind', () async {
    final (controller, viewModel) = await running();

    await controller.stop();

    expect(runtime.cancels, 1);
    expect(viewModel.running, isFalse, reason: 'the button goes back to Run');
    // Stopping is not something the student got wrong, so it draws no banner at
    // all — and the program's output died with the worker holding it anyway.
    expect(viewModel.attempt, isNull);

    // The stopped run still answers. That answer belongs to nobody.
    await pumpEventQueue();
    expect(viewModel.attempt, isNull, reason: 'a stopped run must not report a verdict');
    expect(viewModel.running, isFalse);
  });

  test('reaching the end page stops a run in flight', () async {
    final (controller, viewModel) = await running(sectionId: 'last');

    await controller.next(_sections.length);
    await pumpEventQueue();

    expect(runtime.cancels, 1);
    expect(viewModel.completed, isTrue);
    expect(viewModel.attempt, isNull, reason: 'the end page is no place for the last step\'s verdict');
  });

  test('leaving the screen stops a run in flight', () async {
    final (controller, viewModel) = await running();

    // The catch-all: a lesson can be left by the trail, the browser's Back
    // button or the settings menu, none of which this controller drives.
    controller.dispose();
    await pumpEventQueue();

    expect(runtime.cancels, 1);
    expect(viewModel.running, isFalse);
  });

  test('a run started after a stop still gets its verdict', () async {
    final (controller, viewModel) = await running();
    await controller.stop();

    unawaited(controller.run(_sections.first, 'print(1)'));
    await pumpEventQueue();
    runtime.finish(passed: true, output: '1\n');
    await pumpEventQueue();

    expect(viewModel.running, isFalse);
    expect(viewModel.attempt?.passed, isTrue, reason: 'stopping must not wedge the button for good');
    expect(viewModel.passed, contains(0));
  });

  test('a second Run is ignored while one is already going', () async {
    final (controller, _) = await running();

    await controller.run(_sections.first, 'print(1)');

    expect(runtime.cancels, 0, reason: 'the run in flight is left alone rather than superseded here');
  });
}
