import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/app.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/locale_controller.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';
import 'package:i_can_code/services/progress/progress_store.dart';
import 'package:i_can_code/services/python/python_attempt_runner.dart';
import 'package:i_can_code/services/python/python_runtime.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  setupServices();
  runApp(const ICanCodeApp());
}

/// Registers the app-wide singletons before the widget tree is built.
///
/// MUST do no I/O: work that can fail or take time belongs to the initialization
/// screen, which can show progress and offer a retry.
///
/// [Course] is deliberately absent — the initialization screen registers it once
/// loaded, so reaching any screen past it guarantees it is there.
void setupServices() {
  final python = createPythonRuntime();

  GetIt.I
    ..registerSingleton<AppRouter>(AppRouter())
    ..registerSingleton<BootstrapStatus>(BootstrapStatus())
    ..registerSingleton<PendingNavigationService>(PendingNavigationService())
    ..registerSingleton<LocaleController>(LocaleController())
    ..registerSingleton<ProgressStore>(ProgressStore())
    ..registerSingleton<PythonRuntime>(python)
    ..registerSingleton<PythonAttemptRunner>(PythonAttemptRunner(python));
}
