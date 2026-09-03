import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/routing/bootstrap_guard.dart';

/// The section id that means "wherever I left off" rather than a real section.
///
/// Reserved: a lesson must not name a section this. `lesson_test.dart` holds it.
const String resumeSection = 'resume';

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
    // A lesson's bare address means "wherever I left off". auto_route matches on
    // an exact segment count, so that cannot be an optional segment below — and
    // **a page may appear only once**, so a second AutoRoute is out too
    // (auto_route rejects a duplicate route name when the router is built, after
    // codegen and the build have passed).
    //
    // Hence the redirect to a reserved section id: an unknown id already means
    // "resume" to the screen, which rewrites the address to where it lands.
    RedirectRoute(path: '/:languageSlug/:lessonId', redirectTo: '/:languageSlug/:lessonId/$resumeSection'),
    AutoRoute(page: LessonRoute.page, path: '/:languageSlug/:lessonId/:sectionId'),
  ];

}
