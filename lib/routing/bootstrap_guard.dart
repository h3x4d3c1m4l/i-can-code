import 'package:auto_route/auto_route.dart';
import 'package:get_it/get_it.dart';
import 'package:i_can_code/routing/app_router.gr.dart';
import 'package:i_can_code/services/bootstrap_status.dart';
import 'package:i_can_code/services/pending_navigation_service.dart';

/// Makes every route wait for the one-time startup work.
///
/// Without it a reload straight onto a lesson builds a screen whose services the
/// initialization screen has not registered yet. It also makes that screen
/// unreachable afterwards, so Back cannot replay the bootstrap.
class BootstrapGuard extends AutoRouteGuard {

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final started = GetIt.I<BootstrapStatus>().completed;

    if (resolver.routeName == InitializationRoute.name) {
      if (started) {
        resolver.redirectUntil(const LanguagesRoute());
      } else {
        resolver.next();
      }
      return;
    }

    if (started) {
      resolver.next();
      return;
    }

    // Rebuilt from the resolved route rather than captured by hand, so path and
    // query parameters survive the detour.
    GetIt.I<PendingNavigationService>().setPendingRoute(
      PageRouteInfo(
        resolver.route.name,
        args: resolver.route.args,
        rawPathParams: resolver.route.params.rawMap,
        rawQueryParams: resolver.route.queryParams.rawMap,
      ),
    );
    resolver.redirectUntil(const InitializationRoute());
  }

}
