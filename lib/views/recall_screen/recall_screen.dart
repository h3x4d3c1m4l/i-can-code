import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_controller.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_view.dart';
import 'package:i_can_code/views/recall_screen/recall_screen_view_model.dart';

@RoutePage()
class RecallScreen extends ScreenBase<RecallScreenViewModel, RecallScreenController, RecallScreenView> {

  /// Which language's refresher this is, as it appears in the address. A path
  /// parameter, so a reload lands back on it — with a session built afresh,
  /// because what is due may have changed by then.
  final String languageSlug;

  const RecallScreen({@PathParam('languageSlug') required this.languageSlug, super.key});

  @override
  RecallScreenController createController({
    required RecallScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return RecallScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  RecallScreenView createView({
    required RecallScreenController controller,
    required RecallScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return RecallScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  RecallScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return RecallScreenViewModel(contextAccessor: contextAccessor, languageSlug: languageSlug);
  }

}
