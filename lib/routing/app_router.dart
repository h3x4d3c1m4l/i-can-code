import 'package:auto_route/auto_route.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/routing/bootstrap_guard.dart';

/// The section id that means "wherever I left off" rather than a real section.
///
/// Reserved: a lesson must not name a section this. `lesson_test.dart` holds it.
const String resumeSection = 'resume';

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
