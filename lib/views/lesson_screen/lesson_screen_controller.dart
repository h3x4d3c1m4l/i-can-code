import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_view_model.dart';

class LessonScreenController extends ScreenControllerBase<LessonScreenViewModel> {

  final PythonAttemptRunner _runner = GetIt.I<PythonAttemptRunner>();
  final ProgressStore _progress = GetIt.I<ProgressStore>();

  bool _disposed = false;

  LessonScreenController({required super.viewModel, required super.contextAccessor}) {
    // `/resume` and stale ids are resolved by the view model, so the address
    // still needs rewriting. After the first frame, because the accessor's
    // context does not exist before the screen has built.
    if (viewModel.addressNeedsRewrite) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(goTo(viewModel.step)));
    }
  }

  /// Runs the student's code for the current step and checks it.
  ///
  /// [section] is passed in because the view already resolved it for the current
  /// locale; re-resolving here could pick a different translation mid-run.
  Future<void> run(LessonSection section, String code) async {
    if (viewModel.running) return;

    viewModel.startRun();
    final result = await _runner.attempt(code: code, validator: section.validator);
    if (_disposed) return;
    viewModel.finishRun(result);
    if (result.passed) await _remember(section);
  }

  /// The kind of the step being shown. Read off any translation —
  /// `lesson_test.dart` holds that every locale has the same sections.
  SectionKind get _currentKind =>
      viewModel.lesson.translations.values.first.sections[viewModel.step].kind;

  /// Moves to the next step, or to the lesson's end page after the last one.
  Future<void> next(int stepCount) async {
    // An info step is never run, so leaving it completes it. Marked on the way
    // out: the progress bar draws a completed step ahead of the current one, so
    // marking on arrival would lose the "you are here".
    if (!_currentKind.isAssignment) {
      viewModel.markPassed();
      await _remember(_currentSection);
    }

    await _advance(stepCount);
  }

  /// Leaves an optional step without completing it.
  Future<void> skip(int stepCount) => _advance(stepCount);

  /// Back one step, or off the end page onto the last step.
  ///
  /// Records nothing on the way: moving backwards is reading, not progress.
  /// [canGoBack] is what decides whether it is offered, so this has nowhere to
  /// go only if it is called anyway.
  Future<void> previous(int stepCount) async {
    if (viewModel.completed) return goTo(stepCount - 1);
    if (viewModel.step == 0) return;

    await goTo(viewModel.step - 1);
  }

  /// Whether there is a step behind this one. False on the very first step,
  /// where a back button would be a control that does nothing.
  bool get canGoBack => viewModel.completed || viewModel.step > 0;

  /// Moves one step on, or shows the lesson's end page after the last one.
  Future<void> _advance(int stepCount) async {
    if (viewModel.step + 1 < stepCount) {
      await goTo(viewModel.step + 1);
      return;
    }

    // The end page rather than the catalog: it is where the way on to the next
    // lesson lives, and where a finished lesson is actually acknowledged.
    viewModel.complete();
  }

  /// Moves to [step] and names it in the address, so a reload lands back here.
  ///
  /// `replace` rather than `push`, so Back leaves the lesson instead of walking
  /// it backwards a step at a time.
  Future<void> goTo(int step) async {
    viewModel.goTo(step);
    if (_disposed || !contextAccessor.buildContext.mounted) return;

    final lesson = viewModel.lesson.translations.values.first;
    await contextAccessor.buildContext.router.replace(
      lessonRoute(
        languageSlug: languageSlug(viewModel.lesson.entry.language),
        lessonId: lesson.id,
        sectionId: lesson.sections[step].id,
      ),
    );
  }

  LessonSection get _currentSection =>
      viewModel.lesson.translations.values.first.sections[viewModel.step];

  /// Records [section] as done, and notes it when that tick is what finished
  /// the lesson.
  ///
  /// Asked around the write rather than on the last step, because the last step
  /// is not always the one that completes a lesson: a student who left a gap
  /// and came back to fill it finishes it in the middle.
  Future<void> _remember(LessonSection section) async {
    final wasFinished = _progress.isFinished(viewModel.lesson);
    await _progress.markFinished(viewModel.lesson, section.id);

    if (!wasFinished && _progress.isFinished(viewModel.lesson)) viewModel.noteLessonFinished();
  }

  /// Opens the next lesson in this language, or the catalog when this was the
  /// last one.
  ///
  /// Lands on its first unfinished step, the same as opening it from the
  /// catalog would. The catalog is left under it, so Back still goes there.
  Future<void> openNextLesson() async {
    final next = GetIt.I<Course>().lessonAfter(viewModel.lesson);
    if (next == null) {
      await openLanguage(viewModel.lesson.entry.language);
      return;
    }
    if (_disposed || !contextAccessor.buildContext.mounted) return;

    final lesson = next.translations.values.first;
    await contextAccessor.buildContext.router.replaceAll([
      const LanguagesRoute(),
      CatalogRoute(languageSlug: languageSlug(next.entry.language)),
      lessonRoute(
        languageSlug: languageSlug(next.entry.language),
        lessonId: lesson.id,
        sectionId: lesson.sections[_progress.firstUnfinishedStep(next)].id,
      ),
    ]);
  }

  /// Opens the catalog for [language].
  Future<void> openLanguage(String language) async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([
      const LanguagesRoute(),
      CatalogRoute(languageSlug: languageSlug(language)),
    ]);
  }

  /// Returns to the app's home. Guarded on [_disposed]: the accessor is only
  /// assigned once the screen has built, so it MUST NOT be touched before.
  Future<void> leave() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const LanguagesRoute()]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

}
