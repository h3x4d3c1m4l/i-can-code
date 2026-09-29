import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/routing/bootstrap_guard.dart';
import 'package:i_can_code/routing/project_guard.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';

/// The section id that means "wherever I left off" rather than a real section.
///
/// Reserved: a lesson must not name a section this. `test/content/lessons_test.dart`
/// holds it.
const String resumeSection = 'resume';

/// The lesson id the interactive console sits on.
///
/// Reserved for the same reason and in the same place: it occupies a language's
/// second address segment, where a lesson id would otherwise go, so a lesson
/// with this id would be unreachable. `test/content/lessons_test.dart` holds it.
const String replLesson = 'repl';

/// The lesson id writing a program to a micro:bit sits on.
///
/// Reserved exactly as [replLesson] is, for the same reason and held by the same
/// test: it occupies a language's second address segment, so a lesson with this
/// id would be unreachable.
const String microbitLesson = 'microbit';

/// The lesson id the micro:bit's own prompt sits on.
///
/// A second address rather than a second view of [microbitLesson], because the
/// two want opposite things of the board: a prompt has to interrupt whatever is
/// running, and a program has to be left alone to run. Reserved like the others.
const String microbitReplLesson = 'microbit-repl';

/// One step of a lesson, as a route. **Build a [LessonRoute] through here
/// rather than directly**, because of the key.
///
/// auto_route keys a page on its route *name* alone, so replacing one
/// `LessonRoute` with another is a page update rather than a new page: the same
/// element, the same `State`, and so the previous lesson's view model. Keying
/// the screen on the lesson is what makes a jump to a different lesson a
/// different screen — and keying it the same way on every step of a lesson is
/// what keeps moving *within* one from throwing that state away.
///
/// A route parsed from the address carries no key of its own, so the first
/// move away from a cold-loaded step rebuilds the screen once. Nothing is at
/// stake there beyond code typed on the step being left.
LessonRoute lessonRoute({
  required String languageSlug,
  required String lessonId,
  required String sectionId,
}) => LessonRoute(
  key: ValueKey(lessonId),
  languageSlug: languageSlug,
  lessonId: lessonId,
  sectionId: sectionId,
);

/// A project, as a route. **Build a [ProjectRoute] through here**, for the
/// reason [lessonRoute] gives: keyed on the lesson, so opening the next project
/// from the end of this one is a new screen rather than this one updated.
///
/// Under [microbitLesson] because a project is a program for a board, and that
/// address is where a program for a board already lives. `microbit` is a
/// reserved lesson id, so no lesson can claim the segment.
ProjectRoute projectRoute({required String languageSlug, required String lessonId}) => ProjectRoute(
  key: ValueKey(lessonId),
  languageSlug: languageSlug,
  lessonId: lessonId,
);

/// Where [lesson] opens from outside it: a project on its own screen, and any
/// other lesson at the first step [progress] does not have as finished.
PageRouteInfo<void> openingRoute(CourseLesson lesson, ProgressStore progress) {
  final first = lesson.translations.values.first;
  final slug = languageSlug(lesson.entry.language);

  if (first.isProject) return projectRoute(languageSlug: slug, lessonId: first.id);

  return lessonRoute(
    languageSlug: slug,
    lessonId: first.id,
    sectionId: first.sections[progress.firstUnfinishedStep(lesson)].id,
  );
}

@AutoRouterConfig()
class AppRouter extends RootStackRouter {

  /// There is no login, so the only gate is whether startup has finished.
  @override
  List<AutoRouteGuard> get guards => [BootstrapGuard()];

  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: LanguagesRoute.page, initial: true, path: '/'),
    // Before the catch-all below, which would otherwise claim it.
    AutoRoute(page: InitializationRoute.page, path: '/initialization'),
    AutoRoute(page: CatalogRoute.page, path: '/:languageSlug'),
    // Above the lesson addresses below, which it would otherwise match as a
    // lesson called "repl". Same arrangement as /initialization above the
    // language catch-all, and the reason [replLesson] is a reserved id.
    AutoRoute(page: ReplRoute.page, path: '/:languageSlug/$replLesson'),
    AutoRoute(page: MicrobitProgramRoute.page, path: '/:languageSlug/$microbitLesson'),
    AutoRoute(page: MicrobitReplRoute.page, path: '/:languageSlug/$microbitReplLesson'),
    // Three segments, like a lesson step, so above that route too. `microbit`
    // is reserved as a lesson id, which keeps the two from ever meaning the
    // same address.
    AutoRoute(page: ProjectRoute.page, path: '/:languageSlug/$microbitLesson/:lessonId'),
    // A lesson's bare address means "wherever I left off". auto_route matches on
    // an exact segment count, so that cannot be an optional segment below — and
    // **a page may appear only once**, so a second AutoRoute is out too
    // (auto_route rejects a duplicate route name when the router is built, after
    // codegen and the build have passed).
    //
    // Hence the redirect to a reserved section id: an unknown id already means
    // "resume" to the screen, which rewrites the address to where it lands.
    RedirectRoute(path: '/:languageSlug/:lessonId', redirectTo: '/:languageSlug/:lessonId/$resumeSection'),
    AutoRoute(page: LessonRoute.page, path: '/:languageSlug/:lessonId/:sectionId', guards: [ProjectGuard()]),
  ];

}
