/**
 * Coarse distance bucketing for opt-in "runners nearby" discovery (issue #466).
 *
 * The `discoverable_runners_near` SECURITY DEFINER RPC computes and returns
 * only a bucket index — exact metres never cross the wire, so a caller can't
 * triangulate an opted-in runner. This module is the single source of truth
 * for the bucket boundaries (mirrored in SQL) plus the label-key mapping the
 * UI renders ("~2 km away", "~5 km away", …).
 *
 * Dart twin: `apps/mobile_android/lib/nearby.dart` — keep the boundaries,
 * bucket count, and label keys in lockstep. The SQL CASE in migration
 * `20270426_001_discoverable_runners_nearby.sql` MUST match `nearbyDistanceBucket`.
 */

/** Upper bounds (metres) for buckets 0..3; bucket 4 is everything beyond. */
export const NEARBY_BUCKET_BOUNDS_M: readonly number[] = [2000, 5000, 10000, 25000];

/** The number of distinct buckets (0..NEARBY_BUCKET_COUNT-1). */
export const NEARBY_BUCKET_COUNT = NEARBY_BUCKET_BOUNDS_M.length + 1;

/**
 * Map a distance in metres to its coarse bucket index (0..4), matching the
 * SQL CASE exactly. Negative / NaN inputs clamp to bucket 0 (nearest) so a
 * bad value can never leak a finer signal than the coarsest visible bucket.
 */
export function nearbyDistanceBucket(distanceM: number): number {
	if (Number.isNaN(distanceM) || distanceM < 0) return 0;
	for (let i = 0; i < NEARBY_BUCKET_BOUNDS_M.length; i++) {
		if (distanceM < NEARBY_BUCKET_BOUNDS_M[i]) return i;
	}
	return NEARBY_BUCKET_COUNT - 1;
}

/**
 * The upper distance bound (metres) a bucket represents — `< bound` for
 * buckets 0..count-2, and `null` (open-ended, "beyond the last bound") for the
 * final bucket. The UI formats this bound with the viewer's unit preference so
 * the coarse label stays km/mi-correct ("within ~2 km" / "within ~1.2 mi").
 * Out-of-range indices clamp into [0, count-1].
 */
export function nearbyBucketUpperBoundM(bucket: number): number | null {
	const b = Math.min(Math.max(Math.trunc(bucket), 0), NEARBY_BUCKET_COUNT - 1);
	return b < NEARBY_BUCKET_BOUNDS_M.length ? NEARBY_BUCKET_BOUNDS_M[b] : null;
}
