import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/program_screen/program_screen_controller.dart';
import 'package:i_can_code/views/program_screen/program_screen_view.dart';
import 'package:i_can_code/views/program_screen/program_screen_view_model.dart';

@RoutePage()
class ProgramScreen extends ScreenBase<ProgramScreenViewModel, ProgramScreenController, ProgramScreenView> {

  /// Whose page this is, as it appears in the address, such as `learn-python`.
  /// A path parameter, so a reload lands on the same one.
  final String subjectSlug;

  const ProgramScreen({@PathParam('subjectSlug') required this.subjectSlug, super.key});

  @override
  ProgramScreenController createController({
    required ProgramScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ProgramScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  ProgramScreenView createView({
    required ProgramScreenController controller,
    required ProgramScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ProgramScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  ProgramScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return ProgramScreenViewModel(contextAccessor: contextAccessor, subjectSlug: subjectSlug);
  }

}
