import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_controller.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_view.dart';
import 'package:i_can_code/views/licenses_screen/licenses_screen_view_model.dart';

/// The licence of the app itself, and of everything it ships with.
///
/// What Flutter's `LicensePage` is to a Material app. That one is Material, and
/// lists a flat run of packages; this one groups them by where they come from.
@RoutePage()
class LicensesScreen extends ScreenBase<LicensesScreenViewModel, LicensesScreenController, LicensesScreenView> {

  const LicensesScreen({super.key});

  @override
  LicensesScreenController createController({
    required LicensesScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LicensesScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  LicensesScreenView createView({
    required LicensesScreenController controller,
    required LicensesScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LicensesScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  LicensesScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return LicensesScreenViewModel(contextAccessor: contextAccessor);
  }

}
