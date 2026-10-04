import 'package:auto_route/annotations.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/project_screen/project_screen_controller.dart';
import 'package:i_can_code/views/project_screen/project_screen_view.dart';
import 'package:i_can_code/views/project_screen/project_screen_view_model.dart';

/// A lesson with `layout: project`: one program for a micro:bit, built up over
/// its tasks. See `docs/lesson-format.md`.
@RoutePage()
class ProjectScreen extends ScreenBase<ProjectScreenViewModel, ProjectScreenController, ProjectScreenView> {

  /// Which project to open, by the lesson's id. A path parameter, so a reload
  /// lands back here.
  final String lessonId;

  /// The subject segment the project sits under.
  final String subjectSlug;

  const ProjectScreen({
    @PathParam('subjectSlug') required this.subjectSlug,
    @PathParam('lessonId') required this.lessonId,
    super.key,
  });

  @override
  ProjectScreenController createController({
    required ProjectScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ProjectScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  ProjectScreenView createView({
    required ProjectScreenController controller,
    required ProjectScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return ProjectScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  ProjectScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return ProjectScreenViewModel(contextAccessor: contextAccessor, subjectSlug: subjectSlug, lessonId: lessonId);
  }

}
