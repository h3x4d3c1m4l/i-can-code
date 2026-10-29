import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/views/base/screen_controller_base.dart';
import 'package:i_can_code/views/catalog_screen/catalog_screen_view_model.dart';
import 'package:i_can_code/views/catalog_screen/components/restart_lesson_dialog.dart';

class CatalogScreenController extends ScreenControllerBase<CatalogScreenViewModel> {

  /// A push of the Tkinter page that has not reached the stack yet.
  bool _openingTkinter = false;

  CatalogScreenController({required super.viewModel, required super.contextAccessor});

  /// Back to the subject picker, which is the app's home.
  Future<void> goHome() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.replaceAll([const SubjectsRoute()]);
  }

  /// Opens this subject's interactive console. Not a lesson: nothing in it is
  /// checked and nothing is recorded, which is why it sits under its own
  /// heading rather than at the end of the list.
  Future<void> openRepl() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      ReplRoute(subjectSlug: subjectSlug(viewModel.subject)),
    );
  }

  /// Opens the page a program is written and run on, in the browser.
  Future<void> openProgram() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      ProgramRoute(subjectSlug: subjectSlug(viewModel.subject)),
    );
  }

  /// Opens the page a program is written and put on a board from.
  Future<void> openMicrobitProgram() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      MicrobitProgramRoute(subjectSlug: subjectSlug(viewModel.subject)),
    );
  }

  /// Opens MicroPython's own prompt, on the board.
  Future<void> openMicrobitRepl() async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(
      MicrobitReplRoute(subjectSlug: subjectSlug(viewModel.subject)),
    );
  }

  /// Opens the page a program with windows is written and run on. Ignored while
  /// such a page is open or on its way: the host keeps one machine per tab, and
  /// a second page's would destroy the first's.
  ///
  /// Not a flag held until [StackRouter.push] resolves, because that waits for
  /// a pop, and a page `replaceAll` removes is never popped while this catalog's
  /// own page survives the call.
  Future<void> openTkinter() async {
    if (_openingTkinter || !contextAccessor.buildContext.mounted) return;
    final router = contextAccessor.buildContext.router;
    if (router.stackData.any((route) => route.name == TkinterRoute.name)) return;

    _openingTkinter = true;
    void landed() {
      _openingTkinter = false;
      router.removeListener(landed);
    }

    // The router notifies as the page lands, and from then on the stack answers.
    router.addListener(landed);
    try {
      await router.push(TkinterRoute(subjectSlug: subjectSlug(viewModel.subject)));
    } finally {
      landed();
    }
  }

  /// Opens a lesson where the student left off — its first unfinished step, or
  /// the beginning if there is none. A project opens on its own screen.
  Future<void> openLesson(CourseLesson lesson) async {
    if (!contextAccessor.buildContext.mounted) return;
    await contextAccessor.buildContext.router.push(openingRoute(lesson, viewModel.progress));
  }

  /// Whether [lesson] has ticks or code to forget.
  bool canRestart(CourseLesson lesson) => viewModel.progress.isStarted(lesson) || viewModel.drafts.hasCodeIn(lesson);

  /// Forgets [lesson]'s ticks and code once the student confirms, so it opens
  /// on its first step and its starter code again. [title] names it in the
  /// question, in the reader's language.
  Future<void> restartLesson(CourseLesson lesson, String title) async {
    if (!canRestart(lesson) || !contextAccessor.buildContext.mounted) return;
    if (!await showRestartLessonDialog(contextAccessor.buildContext, lesson: title)) return;

    await (viewModel.progress.forget(lesson), viewModel.drafts.forgetLesson(lesson)).wait;
  }

}
