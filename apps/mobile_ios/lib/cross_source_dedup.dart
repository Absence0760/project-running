/// Cross-source dedup at import time.
///
/// Persona-hunt Round 2 finding Intermediate #3: exact-match on
/// `external_id` works inside one source (round-1 fix for Strava
/// ZIP re-imports) but doesn't catch the same activity arriving via
/// two sources with different namespace prefixes. A Garmin run that
/// syncs to BOTH Strava AND Health Connect lands as two distinct
/// rows: `strava:<id>` and `healthconnect:<uuid>`. Weekly mileage
/// doubles for any affected day; the PB scanner sees the effort
/// twice; the heatmap shows the day twice as deep.
///
/// This helper is a pure fuzzy-match: a candidate import duplicates
/// an existing run when their start times agree within ±5 minutes
/// AND their distances agree within ±5%. The window is wide enough
/// to absorb the small clock + GPS-distance variance you get
/// between platforms (Garmin recorded the start at second 0; Strava
/// ingested it 2 seconds later; Health Connect summarised it
/// 1 second after that), tight enough to never falsely match two
/// genuinely-different runs.

import 'package:core_models/core_models.dart';

/// ±180 seconds — the canonical cross-provider start tolerance, in lockstep
/// with `CROSS_PROVIDER_START_TOLERANCE_S` in the web twin
/// (`apps/web/src/lib/integrations/garmin_dedupe.ts`), the Deno twin
/// (`apps/backend/supabase/functions/_shared/strava.ts`), and the Go worker
/// (`apps/job_worker/internal/cross_provider.go`). A few minutes absorbs the
/// offset between a watch's and a service's start stamp; two genuinely
/// distinct runs can't start this close (you can't record two tracks at once).
const Duration kCrossSourceTimeWindow = Duration(seconds: 180);

/// ±5% relative distance — matches `CROSS_PROVIDER_DISTANCE_FRACTION` in the
/// twins. GPS / algorithm differences between providers move total distance a
/// percent or two.
const double kCrossSourceDistanceFraction = 0.05;

/// Returns true when `candidate` looks like a re-import of one of the
/// `existing` runs from a different source — start within the tolerance AND
/// distance within the fraction (both axes, so a warm-up + race of similar
/// distance but well-separated starts is never suppressed).
///
/// The near-duplicate math is the byte-identical twin of the canonical
/// `isCrossProviderDuplicate` (start-gap ≤ 180 s AND |Δdist| ≤ 5% of the
/// LARGER distance). Two mobile-specific guards stay on top of it: the
/// comparison is cross-source only (`r.source == candidate.source` is skipped
/// — same-source re-imports are guarded by the per-user `external_id` unique
/// index at the DB, the mobile equivalent of the web importers running their
/// exact `seen`/`composite` dedupe first), and a zero-distance existing run is
/// ignored so a trackless indoor summary can't false-match.
bool isCrossSourceDuplicate(Run candidate, List<Run> existing) {
  for (final r in existing) {
    if (r.source == candidate.source) continue;
    final dt = r.startedAt.difference(candidate.startedAt).abs();
    if (dt > kCrossSourceTimeWindow) continue;
    final candidateDist = candidate.distanceMetres;
    final existingDist = r.distanceMetres;
    if (existingDist <= 0 || candidateDist <= 0) continue;
    final larger =
        candidateDist.abs() > existingDist.abs() ? candidateDist.abs() : existingDist.abs();
    final diff = (candidateDist - existingDist).abs();
    if (diff > larger * kCrossSourceDistanceFraction) continue;
    return true;
  }
  return false;
}
