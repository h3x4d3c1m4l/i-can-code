import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/microbit_screen/microbit_screen_controller.dart';
import 'package:i_can_code/views/microbit_screen/microbit_screen_view.dart';
import 'package:i_can_code/views/microbit_screen/microbit_screen_view_model.dart';

@RoutePage()
class MicrobitScreen extends ScreenBase<MicrobitScreenViewModel, MicrobitScreenController, MicrobitScreenView> {

  /// Whose board this is, as it appears in the address, such as `learn-python`.
  /// A path parameter, so a reload lands on the same one.
  final String languageSlug;

  const MicrobitScreen({@PathParam('languageSlug') required this.languageSlug, super.key});

  @override
  MicrobitScreenController createController({
    required MicrobitScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return MicrobitScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  MicrobitScreenView createView({
    required MicrobitScreenController controller,
    required MicrobitScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return MicrobitScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  MicrobitScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return MicrobitScreenViewModel(contextAccessor: contextAccessor, languageSlug: languageSlug);
  }

}
