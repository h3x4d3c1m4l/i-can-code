import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/app_info.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/python/python_runtime.dart';
import 'package:i_can_code/services/rustc_version/rustc_version.dart';
import 'package:i_can_code/views/about_screen/about_screen_view_model.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:url_launcher/url_launcher.dart';

class AboutScreenController extends ScreenControllerBase<AboutScreenViewModel> {

  bool _disposed = false;

  AboutScreenController({required super.viewModel, required super.contextAccessor}) {
    unawaited(_loadRustc());
    unawaited(_loadPython());
  }

  Future<void> _loadRustc() async {
    final version = await loadRustcVersion();
    if (!_disposed) viewModel.setRustc(version);
  }

  /// Loads the interpreter to ask it what it is, as a step that runs code would
  /// on arrival. It compiles in a worker, and the next such step finds it ready.
  Future<void> _loadPython() async {
    final runtime = GetIt.I<PythonRuntime>();
    if (runtime.isSupported) {
      try {
        await runtime.ready();
      } on Object {
        // A runtime that did not load has no version to give, and the screen
        // says it is unknown.
      }
    }
    if (!_disposed) viewModel.setPython(runtime.version);
  }

  /// The app's source, in a new tab: the reader is not done with this one.
  Future<void> openSource() => launchUrl(Uri.parse(kSourceUrl));

  /// Pushed rather than replaced, so Back returns here.
  Future<void> openLicenses() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(const LicensesRoute());
  }

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

}
