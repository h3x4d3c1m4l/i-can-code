import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';

/// Sends a project's lesson address to the project's own screen.
///
/// A project is a lesson file, so an address typed or bookmarked in the lesson
/// form, `/learn-python/dobbelsteen`, resolves to the lesson screen, which walks
/// a lesson one step at a time and cannot show one. Everything the app builds
/// itself goes through [openingRoute] and never gets here.
class ProjectGuard extends AutoRouteGuard {

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final slug = resolver.route.params.optString('subjectSlug');
    final lessonId = resolver.route.params.optString('lessonId');

    // Before the bootstrap there is no course to ask. `BootstrapGuard` parks
    // the address, and it comes back through here once there is.
    if (slug == null || lessonId == null || !GetIt.I.isRegistered<Course>()) {
      resolver.next();
      return;
    }

    final isProject = GetIt.I<Course>().lessons
        .map((lesson) => lesson.translations.values.first)
        .any((lesson) => lesson.id == lessonId && lesson.isProject);
    if (!isProject) {
      resolver.next();
      return;
    }

    // Not `redirectUntil`, which parks the lesson route until the project is
    // popped and then abandons it: that is a detour, and this is a different
    // address. The stack is rebuilt the way opening the project from its
    // catalog would have left it, after this navigation has been dropped.
    resolver.next(false);
    scheduleMicrotask(
      () => unawaited(
        router.replaceAll([
          const SubjectsRoute(),
          CatalogRoute(subjectSlug: slug),
          projectRoute(subjectSlug: slug, lessonId: lessonId),
        ]),
      ),
    );
  }

}
