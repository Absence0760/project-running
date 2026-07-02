package internal

import "math"

// Cross-provider near-duplicate detection.
//
// The per-provider dedupe key (`metadata.strava_id`, checked by
// IsStravaActivityImported) only catches a re-import of the SAME Strava
// activity. A single physical activity that reaches us under two
// providers — a Garmin watch that auto-uploads to Strava, then the same
// run imported from a Garmin bulk-export ZIP or an Apple HealthKit copy —
// lands as two rows with different provider ids, so the strava_id key
// never sees the other. Two recordings of one effort start within seconds
// and cover ~the same distance; two genuinely distinct runs can't start
// within a few minutes of each other (you can't record two tracks at
// once). We gate on BOTH axes so a warm-up + race of similar distance but
// well-separated starts is never suppressed. Keep in lockstep with the TS
// twin `isCrossProviderDuplicate` in
// `apps/web/src/lib/integrations/garmin_dedupe.ts` +
// `apps/backend/supabase/functions/_shared/strava.ts` and the Dart twin in
// `apps/mobile_android/lib/cross_source_dedup.dart`.

// RunIdentity is a run's identity for cross-provider matching: start
// instant (epoch ms) and total distance (metres).
type RunIdentity struct {
	StartedAtMs int64
	DistanceM   float64
}

// CrossProviderStartToleranceS is the max start-time gap (seconds) for two
// rows to be the same effort. A few minutes absorbs the offset between a
// watch's and a service's start stamp.
const CrossProviderStartToleranceS = 180

// CrossProviderDistanceFraction is the max relative distance difference for
// two rows to be the same effort. GPS / algorithm differences between
// providers move total distance a percent or two; 5 % matches the same run
// across providers without merging two different-length efforts.
const CrossProviderDistanceFraction = 0.05

// IsCrossProviderDuplicate reports whether candidate is a near-duplicate of
// any row in existing — start within the tolerance AND distance within the
// fraction. Callers skip the import when this returns true so a run already
// present under ANY source isn't re-inserted.
func IsCrossProviderDuplicate(candidate RunIdentity, existing []RunIdentity) bool {
	for _, row := range existing {
		dtS := math.Abs(float64(candidate.StartedAtMs-row.StartedAtMs)) / 1000
		if dtS > CrossProviderStartToleranceS {
			continue
		}
		larger := math.Max(math.Abs(candidate.DistanceM), math.Abs(row.DistanceM))
		diff := math.Abs(candidate.DistanceM - row.DistanceM)
		if larger == 0 || diff <= larger*CrossProviderDistanceFraction {
			return true
		}
	}
	return false
}
