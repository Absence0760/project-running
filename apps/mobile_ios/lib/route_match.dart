import 'package:core_models/core_models.dart';

/// Strong-match thresholds for the auto-link suggestion.
///
/// A candidate qualifies as a "definitely the same route" auto-link
/// target when **both** apply:
///
///   - `startOffsetM + endOffsetM < endpointBudgetMetres`
///     (the recording starts and ends close to the route's endpoints)
///   - `|runDistanceM - candidate.distanceM| / max(runDistanceM, 1) <
///     lengthRatioMax`
///     (the recording and the route are roughly the same length)
///
/// The constants mirror the web's `suggestRoute` policy in
/// `apps/web/src/routes/runs/[id]/+page.svelte` — keep both in sync.
/// Either dimension alone is too noisy: an in-and-out segment that
/// shares geometry with a longer loop can have tiny endpoint offsets
/// but very different length; a tracker dropout at one end can push
/// a perfect-length match over the endpoint budget.
const double routeMatchEndpointBudgetMetres = 200;
const double routeMatchLengthRatioMax = 0.2;

/// Pick the best strong-match candidate for auto-linking. Returns
/// `null` when no candidate satisfies both thresholds — callers
/// should not auto-link in that case (the run can still be linked
/// manually via the run-detail suggestion surface).
///
/// Candidates are assumed pre-ordered by the
/// `routes_intersecting_track` RPC (best first by spatial overlap).
/// The first candidate that passes both gates wins; we don't try to
/// re-rank because the spatial ordering is more reliable than any
/// scalar combination of offsets + length.
RouteMatchCandidate? bestStrongRouteMatch(
  Iterable<RouteMatchCandidate> candidates, {
  required double runDistanceMetres,
}) {
  // Guard against a zero or negative run distance — division would
  // amplify any length difference into a huge ratio. Treat it as
  // "no match" rather than throwing.
  if (runDistanceMetres <= 0) return null;
  for (final c in candidates) {
    if (c.startOffsetM + c.endOffsetM >= routeMatchEndpointBudgetMetres) {
      continue;
    }
    final lengthRatio =
        (c.distanceM - runDistanceMetres).abs() / runDistanceMetres;
    if (lengthRatio >= routeMatchLengthRatioMax) continue;
    return c;
  }
  return null;
}
