import 'package:core_models/core_models.dart' show Waypoint;

import '../run_stats.dart' show haversineMetres;

/// Pure helper for the route builder's "snap to start" affordance. When
/// the user is about to place a waypoint near the route's starting
/// point AND the route already has at least 3 prior waypoints, the
/// builder should close the loop on the start instead of leaving a
/// stub-end nearby.
///
/// `kSnapToStartMetres` is loose enough to forgive a fat-finger tap on
/// a phone screen but tight enough that a deliberate tap a block away
/// doesn't accidentally snap home. The web equivalent uses a 25-px
/// screen-space budget; on mobile the same idea expressed in metres
/// keeps the threshold sane across zoom levels.
const double kSnapToStartMetres = 30;

/// True when [tap] is close enough to [start] to snap the loop closed,
/// AND there's enough route already drawn for closing to make sense
/// (web uses `waypoints.length < 3 → no snap`). Pure function — no
/// flutter_map dependency, unit-testable.
bool shouldSnapToStart({
  required Waypoint tap,
  required List<Waypoint> existingWaypoints,
  double toleranceM = kSnapToStartMetres,
}) {
  if (existingWaypoints.length < 3) return false;
  final start = existingWaypoints.first;
  final d = haversineMetres(start.lat, start.lng, tap.lat, tap.lng);
  return d < toleranceM;
}

/// Minimum spacing between any two waypoints (metres). Tighter than
/// the 30 m snap-to-start tolerance — that one's a deliberate UX
/// affordance for closing the loop; this one's a defence against
/// fat-finger double-taps, drag-onto-neighbour collisions, and
/// snap-to-road cascades that pull two distinct taps onto the same
/// road segment.
///
/// 5 m chosen so a deliberate "tight" placement (running around a
/// statue, zig-zagging through a market) still works while obvious
/// degenerate-near-duplicate clicks get rejected. A back-and-forth
/// between two waypoints 5 m apart is OSRM's smallest meaningful
/// edge and not really a place the runner can actually run.
const double kMinWaypointSpacingM = 5;

/// True when adding [tap] would land within [toleranceM] of any
/// existing waypoint other than [excludeIndex] (the one being
/// dragged, when applicable). Used by the route builder's tap +
/// drag handlers to reject degenerate placements that would
/// produce a zero-length segment in the polyline.
///
/// Pure function — pin test in `snap_to_start_test.dart`.
bool isTooCloseToOtherWaypoints({
  required Waypoint candidate,
  required List<Waypoint> existing,
  int? excludeIndex,
  double toleranceM = kMinWaypointSpacingM,
}) {
  for (var i = 0; i < existing.length; i++) {
    if (i == excludeIndex) continue;
    final w = existing[i];
    if (haversineMetres(w.lat, w.lng, candidate.lat, candidate.lng) <
        toleranceM) {
      return true;
    }
  }
  return false;
}
