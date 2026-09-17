import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';

class CatalogScreenController extends ScreenControllerBase<CatalogScreenViewModel> {

  CatalogScreenController({required super.viewModel, required super.contextAccessor});

  /// Back to the language picker, which is the app's home.
  Future<void> goHome() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const LanguagesRoute()]);
  }

  /// Opens this language's interactive console. Not a lesson: nothing in it is
  /// checked and nothing is recorded, which is why it sits under its own
  /// heading rather than at the end of the list.
  Future<void> openRepl() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      ReplRoute(languageSlug: languageSlug(viewModel.language)),
    );
  }

  /// Opens the page a program is written and put on a board from.
  Future<void> openMicrobitProgram() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      MicrobitProgramRoute(languageSlug: languageSlug(viewModel.language)),
    );
  }

  /// Opens MicroPython's own prompt, on the board.
  Future<void> openMicrobitRepl() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      MicrobitReplRoute(languageSlug: languageSlug(viewModel.language)),
    );
  }

  /// Opens a lesson where the student left off — its first unfinished step, or
  /// the beginning if there is none.
  Future<void> openLesson(CourseLesson lesson) async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      lessonRoute(
        languageSlug: languageSlug(viewModel.language),
        lessonId: lesson.translations.values.first.id,
        sectionId: lesson.translations.values.first
            .sections[viewModel.progress.firstUnfinishedStep(lesson)]
            .id,
      ),
    );
  }

}
