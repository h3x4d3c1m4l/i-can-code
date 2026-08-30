import 'package:auto_route/auto_route.dart';

/// Holds the route the app was asked for while it was still starting up.
///
/// A reload can land straight on a lesson, which needs the course loaded. The
/// guard parks the destination here and diverts to the initialization screen,
/// which navigates on once the bootstrap is done.
class PendingNavigationService {

  PageRouteInfo? _route;

  void setPendingRoute(PageRouteInfo route) => _route = route;

  /// Returns the stored route and forgets it, so a later navigation cannot be
  /// hijacked by a stale destination.
  PageRouteInfo? consumePendingRoute() {
    final route = _route;
    _route = null;
    return route;
  }

}
