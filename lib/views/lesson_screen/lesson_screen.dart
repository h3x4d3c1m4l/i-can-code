import 'package:auto_route/annotations.dart';
import 'package:i_can_code/services/lessons/lesson.dart';
import 'package:i_can_code/views/base/build_context_accessor.dart';
import 'package:i_can_code/views/base/screen_base.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_controller.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_view.dart';
import 'package:i_can_code/views/lesson_screen/lesson_screen_view_model.dart';

@RoutePage()
class LessonScreen extends ScreenBase<LessonScreenViewModel, LessonScreenController, LessonScreenView> {

  /// Which lesson to open — [Lesson.id], from the file's document-level
  /// `metadata` block. A path parameter, so a reload lands back here.
  final String lessonId;

  /// The language segment the lesson sits under. Not used to find the lesson,
  /// but it lets a reload rebuild the trail before the course is loaded.
  final String languageSlug;

  /// Which step to open, by [LessonSection.id] rather than by position, so a
  /// bookmarked link survives the author reordering the lesson.
  ///
  /// Null means "wherever I left off". The screen resolves that and rewrites the
  /// address to the section it lands on.
  final String? sectionId;

  const LessonScreen({
    @PathParam('languageSlug') required this.languageSlug,
    @PathParam('lessonId') required this.lessonId,
    @PathParam('sectionId') this.sectionId,
    super.key,
  });

  @override
  LessonScreenController createController({
    required LessonScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LessonScreenController(viewModel: viewModel, contextAccessor: contextAccessor);
  }

  @override
  LessonScreenView createView({
    required LessonScreenController controller,
    required LessonScreenViewModel viewModel,
    required BuildContextAccessor contextAccessor,
  }) {
    return LessonScreenView(viewModel: viewModel, controller: controller, contextAccessor: contextAccessor);
  }

  @override
  LessonScreenViewModel createViewModel({required BuildContextAccessor contextAccessor}) {
    return LessonScreenViewModel(contextAccessor: contextAccessor, lessonId: lessonId, sectionId: sectionId);
  }

}
