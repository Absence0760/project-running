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

  /// True when the most recent GPS fix was rejected by the accuracy gate
  /// (low-accuracy fix under tree cover / urban canyon), so distance is
  /// not advancing even though the stopwatch keeps ticking. Lets the UI
  /// disclose "distance paused" instead of looking frozen. Cleared as soon
  /// as a fix passes the gate again. Always false before the first dropped
  /// fix and for indoor / no-GPS runs.
  final bool weakGps;

  const RunSnapshot({
    required this.elapsed,
    required this.distanceMetres,
    this.currentPaceSecondsPerKm,
    this.currentPosition,
    this.offRouteDistanceMetres,
    this.routeRemainingMetres,
    this.track = const [],
    this.weakGps = false,
  });
}
