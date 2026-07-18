/// Coarse distance bucketing for opt-in "runners nearby" discovery (issue #466).
///
/// The `discoverable_runners_near` SECURITY DEFINER RPC computes and returns
/// only a bucket index — exact metres never cross the wire, so a caller can't
/// triangulate an opted-in runner. This file is the single source of truth for
/// the bucket boundaries (mirrored in SQL) plus the label-key mapping the UI
/// renders ("~2 km away", "~5 km away", …).
///
/// Web twin: `apps/web/src/lib/social/nearby.ts` — keep the boundaries, bucket
/// count, and label keys in lockstep. The SQL CASE in migration
/// `20270426_001_discoverable_runners_nearby.sql` MUST match
/// `nearbyDistanceBucket`.
library;

/// Upper bounds (metres) for buckets 0..3; bucket 4 is everything beyond.
const List<int> kNearbyBucketBoundsM = [2000, 5000, 10000, 25000];

/// The number of distinct buckets (0..kNearbyBucketCount-1).
final int kNearbyBucketCount = kNearbyBucketBoundsM.length + 1;

/// Map a distance in metres to its coarse bucket index (0..4), matching the
/// SQL CASE exactly. Negative / NaN inputs clamp to bucket 0 (nearest) so a
/// bad value can never leak a finer signal than the coarsest visible bucket.
int nearbyDistanceBucket(num distanceM) {
  if (distanceM.isNaN || distanceM < 0) return 0;
  for (var i = 0; i < kNearbyBucketBoundsM.length; i++) {
    if (distanceM < kNearbyBucketBoundsM[i]) return i;
  }
  return kNearbyBucketCount - 1;
}

/// The upper distance bound (metres) a bucket represents — `< bound` for
/// buckets 0..count-2, and `null` (open-ended, "beyond the last bound") for the
/// final bucket. The UI formats this bound with the viewer's unit preference so
/// the coarse label stays km/mi-correct. Out-of-range indices clamp into
/// [0, count-1].
int? nearbyBucketUpperBoundM(int bucket) {
  final b = bucket.clamp(0, kNearbyBucketCount - 1);
  return b < kNearbyBucketBoundsM.length ? kNearbyBucketBoundsM[b] : null;
}
