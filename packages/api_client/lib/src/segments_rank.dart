/// Pure helpers shared between the v1 + v2 segment leaderboard
/// fetchers. Lives at the api_client layer so both `apps/mobile_*/lib/`
/// (the byte-identical Flutter twin) and any future server-side
/// caller can reuse the same logic.
///
/// Mirrors `apps/web/src/lib/segments.ts` (assignCompetitionRanks +
/// SEGMENT_AGE_BANDS). Keep the two in lockstep — the
/// shared-library-syncer agent watches the pair.
library;

/// Standard competition rank for an ascending-time leaderboard.
/// Tied times share the lower rank; the next distinct time skips
/// to its natural ordinal position. Example: times [10, 10, 15] →
/// ranks [1, 1, 3].
///
/// `timeOf` extracts the comparison key from each row. Caller passes
/// rows already sorted ascending by that key.
List<int> assignCompetitionRanks<T>(
  List<T> rows,
  num Function(T) timeOf,
) {
  final out = <int>[];
  // No sentinel — we use a `seeded` flag so the first row's time can
  // be anything (including 0 or a negative) without colliding with a
  // pre-seeded "no last value yet" marker.
  num lastTime = 0;
  var lastRank = 0;
  var seeded = false;
  for (var i = 0; i < rows.length; i++) {
    final t = timeOf(rows[i]);
    final rank = (seeded && t == lastTime) ? lastRank : i + 1;
    lastTime = t;
    lastRank = rank;
    seeded = true;
    out.add(rank);
  }
  return out;
}

/// Strava-style age bins for tiered segment leaderboards. Must match
/// `apps/web/src/lib/segments.ts#SEGMENT_AGE_BANDS` and the buckets
/// the `segment_leaderboard_tiered` RPC accepts (migration
/// 20260829_001).
const kSegmentAgeBands = <String>[
  '18-19',
  '20-24',
  '25-29',
  '30-34',
  '35-39',
  '40-44',
  '45-49',
  '50-54',
  '55-59',
  '60-64',
  '65-69',
  '70-74',
  '75+',
];
