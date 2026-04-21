import 'package:core_models/core_models.dart';

/// A point-in-time snapshot emitted during a live recording session.
class RunSnapshot {
  final Duration elapsed;
  final double distanceMetres;
  final double? currentPaceSecondsPerKm;

  /// Latest GPS fix, if any. Null during the initial warmup and for indoor
  /// runs where location services were never available — the stopwatch
  /// keeps ticking and the live map falls back to its "Waiting for GPS..."
  /// placeholder until a fix arrives.
  final Waypoint? currentPosition;
  final double? offRouteDistanceMetres;

  /// Distance remaining to the end of the selected route, in metres.
  /// Null when no route is selected.
  final double? routeRemainingMetres;

  /// The full GPS track recorded so far (unmodifiable).
  final List<Waypoint> track;

  const RunSnapshot({
    required this.elapsed,
    required this.distanceMetres,
    this.currentPaceSecondsPerKm,
    this.currentPosition,
    this.offRouteDistanceMetres,
    this.routeRemainingMetres,
    this.track = const [],
  });
}
