import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_controller.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_view.dart';
import 'package:i_can_code/views/languages_screen/languages_screen_view_model.dart';

/// The app's home: which language do you want to learn?
@RoutePage()
class LanguagesScreen extends ScreenBase<LanguagesScreenViewModel, LanguagesScreenController, LanguagesScreenView> {

  const LanguagesScreen({super.key});

  @override
  LanguagesScreenController createController({
    required LanguagesScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LanguagesScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  LanguagesScreenView createView({
    required LanguagesScreenController controller,
    required LanguagesScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LanguagesScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  LanguagesScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return LanguagesScreenViewModel(contextAccessor: contextAccessor);
  }

}
