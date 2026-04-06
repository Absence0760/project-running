import 'package:core_models/core_models.dart';

/// A point-in-time snapshot emitted during a live recording session.
class RunSnapshot {
  final Duration elapsed;
  final double distanceMetres;
  final double? currentPaceSecondsPerKm;
  final Waypoint currentPosition;
  final double? offRouteDistanceMetres;

  const RunSnapshot({
    required this.elapsed,
    required this.distanceMetres,
    this.currentPaceSecondsPerKm,
    required this.currentPosition,
    this.offRouteDistanceMetres,
  });
}
