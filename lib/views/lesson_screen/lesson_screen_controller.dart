import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
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

  /// Moves to the next step, or back to the catalog after the last one.
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

  /// Moves one step on, or back to the catalog after the last one.
  Future<void> _advance(int stepCount) async {
    if (viewModel.step + 1 < stepCount) {
      await goTo(viewModel.step + 1);
      return;
    }
    await openLanguage(viewModel.lesson.entry.language);
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
      LessonRoute(
        languageSlug: languageSlug(viewModel.lesson.entry.language),
        lessonId: lesson.id,
        sectionId: lesson.sections[step].id,
      ),
    );
  }

  LessonSection get _currentSection =>
      viewModel.lesson.translations.values.first.sections[viewModel.step];

  Future<void> _remember(LessonSection section) => _progress.markFinished(viewModel.lesson, section.id);

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
