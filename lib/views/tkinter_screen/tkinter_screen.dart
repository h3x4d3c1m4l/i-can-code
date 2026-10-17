import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_controller.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view.dart';
import 'package:i_can_code/views/tkinter_screen/tkinter_screen_view_model.dart';

@RoutePage()
class TkinterScreen extends ScreenBase<TkinterScreenViewModel, TkinterScreenController, TkinterScreenView> {

  /// Whose page this is, as it appears in the address, such as `learn-python`.
  /// A path parameter, so a reload lands on the same one.
  final String subjectSlug;

  const TkinterScreen({@PathParam('subjectSlug') required this.subjectSlug, super.key});

  @override
  TkinterScreenController createController({
    required TkinterScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return TkinterScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  TkinterScreenView createView({
    required TkinterScreenController controller,
    required TkinterScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return TkinterScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  TkinterScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return TkinterScreenViewModel(contextAccessor: contextAccessor, subjectSlug: subjectSlug);
  }

}
