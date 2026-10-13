import 'package:auto_route/annotations.dart';
import 'package:i_can_code/routing/catalog_anchor.dart';
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

  /// The group the address asks for, by its id: `?group=week-1`.
  final String? group;

  /// The lesson the address asks for, by its id: `?lesson=uitvoer`.
  final String? lesson;

  const CatalogScreen({
    @PathParam('subjectSlug') required this.subjectSlug,
    @QueryParam('group') this.group,
    @QueryParam('lesson') this.lesson,
    super.key,
  });

  /// What the address asks the catalog to scroll to and light up, or null when
  /// it asks for nothing. A lesson is the narrower of the two, so it wins.
  CatalogAnchor? get anchor => switch ((lesson, group)) {
    (final String id, _) => (kind: CatalogAnchorKind.lesson, id: id),
    (_, final String id) => (kind: CatalogAnchorKind.group, id: id),
    _ => null,
  };

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
