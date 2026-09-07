import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/recall_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/lesson_screen/components/prediction_verdict.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_view_model.dart';

class RecallScreenController extends ScreenControllerBase<RecallScreenViewModel> {

  final PythonAttemptRunner _runner = GetIt.I<PythonAttemptRunner>();
  final PythonRuntime _runtime = GetIt.I<PythonRuntime>();
  final RecallStore _recall = GetIt.I<RecallStore>();

  bool _disposed = false;

  /// Identifies the run in flight, so an answer arriving after the student has
  /// moved on belongs to nobody. Same reason the lesson screen keeps one.
  int _runToken = 0;

  RecallScreenController({required super.viewModel, required super.contextAccessor});

  String? get runtimeVersion => _runtime.version;

  /// Runs what the student wrote and checks it against the section's own
  /// validator — the same one that judged it the first time.
  Future<void> run(LessonSection section, String code) async {
    if (viewModel.running) return;

    final token = ++_runToken;
    viewModel.startRun();
    final result = await _runner.attempt(code: code, validator: section.validator);
    if (_disposed || token != _runToken) return;

    viewModel.finishRun(result, passed: result.passed);
  }

  /// Runs a predict item's program and holds [prediction] against what it
  /// printed.
  ///
  /// **A prediction only counts here when it is right**, which is the one place
  /// this differs from the same step inside a lesson. There, seeing the answer
  /// is the whole exercise and a wrong guess still completes the step; here the
  /// question is not "have you met this?" but "do you still know it?", and that
  /// answer feeds the ladder.
  ///
  /// It still costs nothing to be wrong: the output and the explanation are
  /// shown either way, and a miss only brings the lesson round again sooner.
  Future<void> predict(LessonSection section, String prediction) async {
    if (viewModel.running) return;

    final token = ++_runToken;
    viewModel.startRun(prediction: prediction);
    final result = await _runner.attempt(code: section.program ?? '');
    if (_disposed || token != _runToken) return;

    viewModel.finishRun(result, passed: result.passed && matchesPrediction(prediction, result.output));
  }

  Future<void> stop() async {
    if (!viewModel.running) return;

    _runToken++;
    viewModel.stopRun();
    await _runtime.cancel();
  }

  /// On to the next item, and — after the last — settles the ladder.
  Future<void> next() async {
    await stop();
    final wasLast = viewModel.index + 1 >= viewModel.items.length;
    viewModel.advance();

    if (wasLast) await _settle();
  }

  /// Moves every lesson this session drew from up or back a rung.
  ///
  /// Up only when nothing from that lesson was missed. A miss moves it back and
  /// brings it round sooner; it **never takes a tick away** — progress stays
  /// monotonic, and nothing here is graded.
  Future<void> _settle() async {
    for (final lesson in viewModel.lessons) {
      if (viewModel.passedEveryItemOf(lesson)) {
        await _recall.advance(lesson);
      } else {
        await _recall.hold(lesson);
      }
    }
  }

  /// Back to the catalog this refresher was started from.
  Future<void> leave() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const LanguagesRoute(),
      CatalogRoute(languageSlug: languageSlug(viewModel.language)),
    ]);
  }

  /// Returns to the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const LanguagesRoute()]);
  }

  @override
  void dispose() {
    _disposed = true;
    // A refresher can also be left by the trail or the browser's Back button,
    // and a program left running would hold the runtime for the next screen.
    unawaited(stop());
    super.dispose();
  }

}
