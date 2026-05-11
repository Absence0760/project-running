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
