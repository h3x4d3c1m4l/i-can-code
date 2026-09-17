import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_controller.dart';
import 'package:i_can_code/views/components/microbit/microbit_session_view_model.dart';
import 'package:i_can_code/views/microbit_repl_screen/microbit_repl_screen_view.dart';

@RoutePage()
class MicrobitReplScreen extends ScreenBase<MicrobitSessionViewModel, MicrobitSessionController, MicrobitReplScreenView> {

  /// Whose board this is, as it appears in the address, such as `learn-python`.
  /// A path parameter, so a reload lands on the same one.
  final String languageSlug;

  const MicrobitReplScreen({@PathParam('languageSlug') required this.languageSlug, super.key});

  @override
  MicrobitSessionController createController({
    required MicrobitSessionViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    // The prompt is what this screen is for, so every start breaks into it —
    // whatever the board was running.
    return MicrobitSessionController(viewModel: viewModel, contextAccessor: contextAccessor, interrupt: true);
  }

  @override
  MicrobitReplScreenView createView({
    required MicrobitSessionController controller,
    required MicrobitSessionViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return MicrobitReplScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  MicrobitSessionViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return MicrobitSessionViewModel(contextAccessor: contextAccessor, languageSlug: languageSlug);
  }

}
