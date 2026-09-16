import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_controller.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_view.dart';
import 'package:i_can_code/views/repl_screen/repl_screen_view_model.dart';

@RoutePage()
class ReplScreen extends ScreenBase<ReplScreenViewModel, ReplScreenController, ReplScreenView> {

  /// Whose console this is, as it appears in the address — `learn-python`. A
  /// path parameter, so a reload lands back on the same one.
  final String languageSlug;

  const ReplScreen({@PathParam('languageSlug') required this.languageSlug, super.key});

  @override
  ReplScreenController createController({
    required ReplScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ReplScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  ReplScreenView createView({
    required ReplScreenController controller,
    required ReplScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ReplScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  ReplScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return ReplScreenViewModel(contextAccessor: contextAccessor, languageSlug: languageSlug);
  }

}
