import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_controller.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view.dart';
import 'package:i_can_code/views/editor_settings_screen/editor_settings_screen_view_model.dart';

@RoutePage()
class EditorSettingsScreen extends ScreenBase<EditorSettingsScreenViewModel, EditorSettingsScreenController, EditorSettingsScreenView> {

  const EditorSettingsScreen({super.key});

  @override
  EditorSettingsScreenController createController({
    required EditorSettingsScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return EditorSettingsScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  EditorSettingsScreenView createView({
    required EditorSettingsScreenController controller,
    required EditorSettingsScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return EditorSettingsScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  EditorSettingsScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return EditorSettingsScreenViewModel(contextAccessor: contextAccessor);
  }

}
