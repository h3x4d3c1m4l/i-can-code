import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';
import 'package:i_can_code/services/progress/progress_store.dart';

/// Sends a lesson's address on to the screen that can show it, when it names
/// the other one.
///
/// A project is a lesson file, so an address typed or bookmarked in the lesson
/// form, `/learn-python/dobbelsteen`, resolves to the lesson screen, which walks
/// a lesson one step at a time and cannot show one. The other way round, an
/// edited address such as `/learn-python/project/uitvoer` resolves to the
/// project screen with a lesson that has no tasks. Everything the app builds
/// itself goes through [openingRoute] and never gets here.
class ProjectGuard extends AutoRouteGuard {

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final lessonId = resolver.route.params.optString('lessonId');

    // Before the bootstrap there is no course to ask. `BootstrapGuard` parks
    // the address, and it comes back through here once there is.
    if (lessonId == null || !GetIt.I.isRegistered<Course>()) {
      resolver.next();
      return;
    }

    // A lesson the course does not have is `KnownLessonGuard`'s.
    final lesson = GetIt.I<Course>().lessons
        .where((lesson) => lesson.translations.values.first.id == lessonId)
        .firstOrNull;
    final onProjectScreen = resolver.route.name == ProjectRoute.name;
    if (lesson == null || lesson.translations.values.first.isProject == onProjectScreen) {
      resolver.next();
      return;
    }

    // Not `redirectUntil`, which parks the route until the one it opens is
    // popped and then abandons it: that is a detour, and this is a different
    // address. The stack is rebuilt the way opening the lesson from its
    // catalog would have left it, after this navigation has been dropped.
    resolver.next(false);
    scheduleMicrotask(
      () => unawaited(
        router.replaceAll([
          const SubjectsRoute(),
          CatalogRoute(subjectSlug: subjectSlug(lesson.entry.subject)),
          openingRoute(lesson, GetIt.I<ProgressStore>()),
        ]),
      ),
    );
  }

}
