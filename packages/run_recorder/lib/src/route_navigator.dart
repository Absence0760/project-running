import 'package:core_models/core_models.dart';

/// Detects off-route deviation during a live run.
class RouteNavigator {
  final Route route;

  /// Distance threshold in metres before triggering an off-route alert.
  static const double offRouteThresholdMetres = 50.0;

  RouteNavigator({required this.route});

  /// Returns the distance in metres from [position] to the nearest point
  /// on the route. Returns null if no route is loaded.
  double? distanceFromRoute(Waypoint position) {
    // TODO: Implement nearest-point-on-route calculation
    throw UnimplementedError();
  }

  /// Returns the remaining distance in metres along the route from [position].
  double? remainingDistance(Waypoint position) {
    // TODO: Implement remaining distance calculation
    throw UnimplementedError();
  }
}
