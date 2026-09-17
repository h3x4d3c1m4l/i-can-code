import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/microbit_program_screen/microbit_program_screen_view.dart';

@RoutePage()
class MicrobitProgramScreen extends ScreenBase<MicrobitSessionViewModel, MicrobitSessionController, MicrobitProgramScreenView> {

  /// Whose board this is, as it appears in the address, such as `learn-python`.
  /// A path parameter, so a reload lands on the same one.
  final String languageSlug;

  const MicrobitProgramScreen({@PathParam('languageSlug') required this.languageSlug, super.key});

  @override
  MicrobitSessionController createController({
    required MicrobitSessionViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    // The program the student just wrote is meant to run, so nothing interrupts
    // the board on its way into it.
    return MicrobitSessionController(viewModel: viewModel, contextAccessor: contextAccessor, interrupt: false);
  }

  @override
  MicrobitProgramScreenView createView({
    required MicrobitSessionController controller,
    required MicrobitSessionViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return MicrobitProgramScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  MicrobitSessionViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return MicrobitSessionViewModel(contextAccessor: contextAccessor, languageSlug: languageSlug);
  }

}
