import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_view_model.dart';

class InitializationScreenController extends ScreenControllerBase<InitializationScreenViewModel> {

  /// How often a failing step is retried before the screen offers a retry
  /// button.
  ///
  /// Bounded: everything this screen waits on is a bundled asset, so a failure
  /// means a broken build rather than a server that might come back.
  static const int _maxAttempts = 3;

  bool _disposed = false;

  InitializationScreenController({required super.viewModel, required super.contextAccessor}) {
    unawaited(initialize());
  }

  /// Loads what the first screen needs, then replaces this screen with the
  /// catalog.
  Future<void> initialize() async {
    viewModel.reset();
    try {
      // Decides whether there is anything to show at all, so its failure is
      // fatal.
      final course = await _step(InitializationStep.loadingCourse, Course.load);
      if (_disposed) return;
      // Re-registered, because a retry runs this a second time.
      if (GetIt.I.isRegistered<Course>()) await GetIt.I.unregister<Course>();
      GetIt.I.registerSingleton<Course>(course);

      // Compiling CPython is the longest part of a cold start; doing it here
      // means the student waits behind a progress message rather than on the
      // first Run. Reading progress needs the course loaded, and swallows its
      // own failures.
      await GetIt.I<ProgressStore>().load(course);
      if (_disposed) return;

      await _step(InitializationStep.startingRuntime, GetIt.I<PythonRuntime>().ready);
      if (_disposed) return;
    } on Object catch (error) {
      if (!_disposed) viewModel.setError('$error');
      return;
    }

    // Only now may the guard let other routes through.
    GetIt.I<BootstrapStatus>().markCompleted();

    // A reload aimed at a lesson was diverted here; take it the rest of the
    // way.
    final pending = GetIt.I<PendingNavigationService>().consumePendingRoute();
    await _replaceAll([pending ?? const LanguagesRoute()]);
  }

  /// Runs [body] as [step], retrying up to [_maxAttempts] times with a widening
  /// delay. Rethrows once the attempts are spent.
  Future<T> _step<T>(InitializationStep step, Future<T> Function() body) async {
    for (var attempt = 0; ; attempt++) {
      if (_disposed) throw StateError('Initialization was abandoned.');
      viewModel.setStep(step, retries: attempt);
      try {
        return await body();
      } on Object {
        if (attempt >= _maxAttempts - 1) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 250 * (attempt + 1)));
      }
    }
  }

  /// Resets the navigation stack to [routes], unless the screen is already gone.
  ///
  /// Guarded on [_disposed] first: [BuildContextAccessor.buildContext] is only
  /// assigned once the screen has built, so it MUST NOT be touched before then.
  Future<void> _replaceAll(List<PageRouteInfo<dynamic>> routes) async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll(routes);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

}
