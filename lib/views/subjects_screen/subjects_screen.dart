import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_controller.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_view.dart';
import 'package:i_can_code/views/subjects_screen/subjects_screen_view_model.dart';

/// The app's home: what do you want to learn?
@RoutePage()
class SubjectsScreen extends ScreenBase<SubjectsScreenViewModel, SubjectsScreenController, SubjectsScreenView> {

  const SubjectsScreen({super.key});

  @override
  SubjectsScreenController createController({
    required SubjectsScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return SubjectsScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  SubjectsScreenView createView({
    required SubjectsScreenController controller,
    required SubjectsScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return SubjectsScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  SubjectsScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return SubjectsScreenViewModel(contextAccessor: contextAccessor);
  }

}
