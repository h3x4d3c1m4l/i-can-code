import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/about_screen/about_screen_controller.dart';
import 'package:i_can_code/views/about_screen/about_screen_view.dart';
import 'package:i_can_code/views/about_screen/about_screen_view_model.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';

/// Which build this is and what it is made of: the app's version, the source,
/// the licences, and the toolchains and runtimes behind it.
@RoutePage()
class AboutScreen extends ScreenBase<AboutScreenViewModel, AboutScreenController, AboutScreenView> {

  const AboutScreen({super.key});

  @override
  AboutScreenController createController({
    required AboutScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return AboutScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  AboutScreenView createView({
    required AboutScreenController controller,
    required AboutScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return AboutScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  AboutScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return AboutScreenViewModel(contextAccessor: contextAccessor);
  }

}
