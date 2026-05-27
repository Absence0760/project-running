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

/// ±5 minutes — wider than the cross-platform ingest clock skew
/// you see in practice, narrower than back-to-back runs are likely
/// scheduled.
const Duration kCrossSourceTimeWindow = Duration(minutes: 5);

/// ±5% of the existing run's distance. A 10 km run can vary by
/// 500 m between Strava's polyline length and Health Connect's
/// summary; that's well inside this window.
const double kCrossSourceDistanceFraction = 0.05;

/// Returns true when `candidate` looks like a re-import of one of
/// the `existing` runs from a different source. Comparison is
/// directional: we don't dedup against runs of the SAME source as
/// `candidate` (those are guarded by external_id at the DB level).
bool isCrossSourceDuplicate(Run candidate, List<Run> existing) {
  for (final r in existing) {
    if (r.source == candidate.source) continue;
    final dt = (r.startedAt
            .difference(candidate.startedAt)
            .abs());
    if (dt > kCrossSourceTimeWindow) continue;
    final candidateDist = candidate.distanceMetres;
    final existingDist = r.distanceMetres;
    if (existingDist <= 0 || candidateDist <= 0) continue;
    final ratio = (candidateDist - existingDist).abs() / existingDist;
    if (ratio > kCrossSourceDistanceFraction) continue;
    return true;
  }
  return false;
}
