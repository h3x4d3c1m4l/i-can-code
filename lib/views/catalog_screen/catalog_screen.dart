import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_controller.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';

@RoutePage()
class CatalogScreen extends ScreenBase<CatalogScreenViewModel, CatalogScreenController, CatalogScreenView> {

  /// Which subject's lessons to list, as it appears in the address —
  /// `learn-python`. A path parameter, so a reload lands on the same catalog.
  final String subjectSlug;

  const CatalogScreen({@PathParam('subjectSlug') required this.subjectSlug, super.key});

  @override
  CatalogScreenController createController({
    required CatalogScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return CatalogScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  CatalogScreenView createView({
    required CatalogScreenController controller,
    required CatalogScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return CatalogScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  CatalogScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return CatalogScreenViewModel(contextAccessor: contextAccessor, subjectSlug: subjectSlug);
  }

}
