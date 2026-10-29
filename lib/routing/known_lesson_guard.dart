import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/lessons/course.dart';

/// Sends an address naming a lesson the course does not have to the subject
/// picker.
///
/// Such an address comes from outside the app: a bookmark of a lesson since
/// removed or renamed, or of an address the router no longer has. The lesson
/// and project screens look their lesson up and cannot be built without one.
class KnownLessonGuard extends AutoRouteGuard {

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final lessonId = resolver.route.params.optString('lessonId');

    // Before the bootstrap there is no course to ask. `BootstrapGuard` parks
    // the address, and it comes back through here once there is.
    if (lessonId == null || !GetIt.I.isRegistered<Course>()) {
      resolver.next();
      return;
    }

    final known = GetIt.I<Course>().lessons.any((lesson) => lesson.translations.values.first.id == lessonId);
    if (known) {
      resolver.next();
      return;
    }

    // Replaced rather than redirected, for the reason `ProjectGuard` gives.
    resolver.next(false);
    scheduleMicrotask(() => unawaited(router.replaceAll([const SubjectsRoute()])));
  }

}
