import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/editor_settings.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view_model.dart';

class EditorSettingsScreenController extends ScreenControllerBase<EditorSettingsScreenViewModel> {

  final EditorSettings _settings;
  bool _disposed = false;

  /// [settings] is for tests; the screen uses the app's own.
  EditorSettingsScreenController({
    required super.viewModel,
    required super.contextAccessor,
    EditorSettings? settings,
  }) : _settings = settings ?? GetIt.I<EditorSettings>() {
    viewModel.tkinterSetup.text = _settings.tkinterSetup;
    viewModel.tkinterSetup.addListener(_keepTkinterSetup);
  }

  bool get tkinterSetupIsDefault => _settings.tkinterSetupIsDefault;

  /// Every edit is kept at once, so a Tkinter page still open under this screen
  /// runs it on its next Run.
  void _keepTkinterSetup() => unawaited(_settings.setTkinterSetup(viewModel.tkinterSetup.text));

  void restoreTkinterSetup() => viewModel.tkinterSetup.text = EditorSettingsBase.defaultTkinterSetup;

  /// Back to wherever the cog was pressed, or home when this screen was opened
  /// by its address and there is nothing under it.
  Future<void> goBack() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    final router = contextAccessor.buildContext.router;
    if (router.canPop()) {
      await router.maybePop();
    } else {
      await goHome();
    }
  }

  Future<void> goHome() async {
    if (_disposed || !contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    viewModel.tkinterSetup.removeListener(_keepTkinterSetup);
    super.dispose();
  }

}
