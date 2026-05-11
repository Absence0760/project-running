import 'package:core_models/core_models.dart';
import 'package:geolocator/geolocator.dart' show Geolocator;

/// Pure-geometry helper for the structured-workout ghost-pacer marker.
///
/// Given a [path] (typically the planned route's waypoints), an
/// [elapsed] duration, and a [targetPaceSecPerKm], walks the path
/// from `path.first` accumulating great-circle distance until
/// `elapsed * targetSpeed` is reached, then interpolates between the
/// two waypoints that bracket the target.
///
/// Returns `null` when no marker should render:
///   - [path] has fewer than two waypoints
///   - [elapsed] is non-positive
///   - [targetPaceSecPerKm] is non-positive (would mean "infinite speed")
///   - target distance overshoots the path length (the ghost has
///     already finished — caller can decide to render at `path.last`
///     by checking the return and falling back, or just hide the
///     marker, which is what `run_screen.dart` does so an over-budget
///     ghost doesn't bunch onto the finish line for the rest of the
///     step)
///
/// The returned [Waypoint] carries lat + lng only — elevation /
/// timestamp / bpm don't apply to a virtual marker. Callers should
/// treat it as a position fix, not a sample.
Waypoint? ghostPacerPosition({
  required List<Waypoint> path,
  required Duration elapsed,
  required int targetPaceSecPerKm,
}) {
  if (path.length < 2) return null;
  if (elapsed.inMilliseconds <= 0) return null;
  if (targetPaceSecPerKm <= 0) return null;

  // Target distance in metres: speed (m/s) × time (s).
  // Speed from sec/km: 1000 / paceSec/Km.
  final speedMps = 1000.0 / targetPaceSecPerKm;
  final targetDistance = speedMps * elapsed.inMilliseconds / 1000.0;

  // Walk the path accumulating great-circle distance between
  // consecutive waypoints until we cross the target. Use the same
  // Geolocator.distanceBetween that the recorder uses so the ghost
  // and the runner's distance accounting agree.
  var cumulative = 0.0;
  for (var i = 0; i + 1 < path.length; i++) {
    final a = path[i];
    final b = path[i + 1];
    final segMetres = Geolocator.distanceBetween(
      a.lat, a.lng, b.lat, b.lng,
    );
    final next = cumulative + segMetres;
    if (targetDistance <= next) {
      // The target falls inside [a, b]. Linear-interpolate by the
      // fraction of the segment we still need to cover.
      final remaining = targetDistance - cumulative;
      // `segMetres == 0` only when a and b coincide (impossible on a
      // real route, defensive); collapse to b.
      final t = segMetres > 0 ? remaining / segMetres : 1.0;
      return Waypoint(
        lat: a.lat + (b.lat - a.lat) * t,
        lng: a.lng + (b.lng - a.lng) * t,
      );
    }
    cumulative = next;
  }
  // Ghost has run off the end of the path — nothing useful to draw.
  return null;
}
