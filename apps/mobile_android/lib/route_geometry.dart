import 'package:core_models/core_models.dart' show Waypoint;

import 'run_stats.dart' show haversineMetres;

/// Pure geometry helpers for displaying a planned polyline. Lifted
/// to a stand-alone file (vs inlined in `route_detail_screen.dart`)
/// so the math can be unit-tested without booting a screen, and so
/// the helper is reachable from any other route-preview surface that
/// wants a scrubber (e.g. a future feed-card preview).

/// Interpolate the position along [waypoints] at the given
/// normalized [fraction] (0.0 = start, 1.0 = end). Returns null when
/// the polyline is too short to interpolate (`< 2` waypoints).
///
/// Used by the route-detail screen's scrubber slider: the slider
/// emits a 0..1 value as the user drags from start to finish, this
/// helper produces the lat/lng to render the "runner" pulse on the
/// map.
///
/// Distance-weighted — a long segment between two waypoints takes
/// proportionally more of the scrubber's range than a short
/// segment, so dragging at constant speed feels like dragging the
/// runner at a constant pace along the route.
Waypoint? interpolateAlongRoute(
  List<Waypoint> waypoints,
  double fraction,
) {
  if (waypoints.length < 2) return null;
  final f = fraction.clamp(0.0, 1.0);
  // Compute cumulative distance + segment lengths in one pass so
  // we can locate the target distance with a linear scan. The
  // polylines this is called on are bounded by the route builder
  // (typically < 1000 points), so the O(n) scan is fine.
  final totalLen = _cumulativeLengthM(waypoints);
  if (totalLen <= 0) {
    // Degenerate (all points coincident). Snap to the first.
    return waypoints.first;
  }
  final target = totalLen * f;
  var seen = 0.0;
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    final segLen = haversineMetres(a.lat, a.lng, b.lat, b.lng);
    if (segLen <= 0) continue;
    final segEnd = seen + segLen;
    if (target <= segEnd || i == waypoints.length - 1) {
      // Target falls inside this segment OR we've reached the last
      // segment without overshooting (handles fraction=1.0 cleanly).
      final localT = ((target - seen) / segLen).clamp(0.0, 1.0);
      return Waypoint(
        lat: a.lat + (b.lat - a.lat) * localT,
        lng: a.lng + (b.lng - a.lng) * localT,
        elevationMetres: _lerpNullable(
          a.elevationMetres,
          b.elevationMetres,
          localT,
        ),
      );
    }
    seen = segEnd;
  }
  return waypoints.last;
}

/// Compute the total polyline length (metres) via cumulative
/// haversine. Cheap O(n) — same shape the recorder + run-stats
/// helpers use elsewhere in the app.
double polylineLengthMetres(List<Waypoint> waypoints) =>
    _cumulativeLengthM(waypoints);

double _cumulativeLengthM(List<Waypoint> waypoints) {
  var total = 0.0;
  for (var i = 1; i < waypoints.length; i++) {
    final a = waypoints[i - 1];
    final b = waypoints[i];
    total += haversineMetres(a.lat, a.lng, b.lat, b.lng);
  }
  return total;
}

double? _lerpNullable(double? a, double? b, double t) {
  if (a == null && b == null) return null;
  if (a == null) return b;
  if (b == null) return a;
  return a + (b - a) * t;
}
