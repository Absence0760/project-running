/// Pure helper that computes the per-canonical-distance fastest
/// embedded effort for a Run's GPS track and merges it into the
/// metadata bag. Persona-hunt Round 2 finding Pro #4 — pre-fix the
/// canonical `personal_records` cache only considered whole-run
/// distance, so a sub-20 5k inside an 18 km long run never landed in
/// the user's PR list. Migration 20260529_001 now reads
/// `metadata.fastest_X_s` alongside whole-run candidates; this
/// helper writes those keys at save time.
///
/// Same canonical distances + bracket midpoints the SQL trigger
/// uses (the trigger's brackets are ±2% wide; the helper picks the
/// midpoint distance per `docs/backend/metadata.md` so a 5.05 km effort
/// inside a long run is searched as 5000 m exactly).

import 'package:core_models/core_models.dart';

import 'run_stats.dart';

/// (metadata_key, distance_metres) pairs the trigger looks for.
const _embeddedBestDistances = <String, double>{
  'fastest_5k_s': 5000,
  'fastest_10k_s': 10000,
  'fastest_half_marathon_s': 21097.5,
  'fastest_marathon_s': 42195,
};

/// Returns `metadata` with `fastest_X_s` keys merged in for each
/// canonical distance the track is long enough to cover. Existing
/// keys in `metadata` are preserved unless the helper computes a
/// FASTER time for the same key (defensive: a manual edit by the
/// runner overrides the auto-detection only if it's faster — the
/// auto value is the floor).
///
/// Returns `metadata` unchanged if the track has fewer than 3
/// points or no canonical distance fits inside it. Callers pass
/// the merged result back to the api_client save path.
Map<String, dynamic>? enrichMetadataWithEmbeddedBests({
  required List<Waypoint> track,
  Map<String, dynamic>? metadata,
}) {
  if (track.length < 3) return metadata;
  final out = Map<String, dynamic>.from(metadata ?? const {});
  for (final entry in _embeddedBestDistances.entries) {
    final fastest = fastestWindowOf(track, entry.value);
    if (fastest == null) continue;
    final secs = fastest.inSeconds;
    if (secs <= 0) continue;
    final existing = out[entry.key];
    final existingSecs = existing is int
        ? existing
        : (existing is num ? existing.toInt() : null);
    // Keep the fastest. A manually-edited value that's faster than
    // the auto-computed one wins (rare); the auto-computed value
    // wins when the existing key was slower / absent / non-numeric.
    if (existingSecs == null || secs < existingSecs) {
      out[entry.key] = secs;
    }
  }
  return out;
}
