import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_controller.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_view.dart';
import 'package:i_can_code/views/initialization_screen/initialization_screen_view_model.dart';

@RoutePage()
class InitializationScreen
    extends ScreenBase<InitializationScreenViewModel, InitializationScreenController, InitializationScreenView> {

  const InitializationScreen({super.key});

  @override
  InitializationScreenController createController({
    required InitializationScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return InitializationScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  InitializationScreenView createView({
    required InitializationScreenController controller,
    required InitializationScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return InitializationScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  InitializationScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return InitializationScreenViewModel(contextAccessor: contextAccessor);
  }

}
