import 'dart:math';

import 'package:core_models/core_models.dart';

/// Compute **moving time** from a GPS track — the subset of elapsed time
/// during which the runner was actually moving, excluding stops at traffic
/// lights, water fountains, and so on.
///
/// This is a derived metric, computed once at the finished-run screen from
/// the recorded waypoints. It replaces the old live auto-pause feature,
/// which had a long tail of false-positive bugs at walking pace and during
/// GPS warmup. Strava and Nike Run Club both compute moving time the same
/// way — as a post-processing step rather than a live pause.
///
/// Algorithm: walk consecutive waypoint pairs. For each segment, compute
/// `speed = distance / time`. If the segment's speed is above
/// [minSpeedMps], count its time toward moving time; otherwise exclude it.
///
/// [minSpeedMps] defaults to 0.5 m/s (~1.8 km/h) — slower than a slow walk
/// but faster than GPS jitter while standing still. Tune by activity if
/// needed.
///
/// Waypoints without timestamps are skipped (the recorder stamps every
/// point, but imported runs may not).
Duration movingTimeOf(
  List<Waypoint> track, {
  double minSpeedMps = 0.5,
}) {
  if (track.length < 2) return Duration.zero;

  var movingMs = 0;
  for (var i = 1; i < track.length; i++) {
    final a = track[i - 1];
    final b = track[i];
    final at = a.timestamp;
    final bt = b.timestamp;
    if (at == null || bt == null) continue;

    final dtMs = bt.difference(at).inMilliseconds;
    if (dtMs <= 0) continue;

    final distance = haversineMetres(a.lat, a.lng, b.lat, b.lng);
    final speed = distance / (dtMs / 1000.0);
    if (speed >= minSpeedMps) {
      movingMs += dtMs;
    }
  }
  return Duration(milliseconds: movingMs);
}

/// Fastest continuous `windowMetres` covered anywhere in the track.
///
/// This is what users expect "Fastest 5k" to mean — the quickest rolling
/// 5 km window inside any run, not `total_time * 5000 / total_distance`,
/// which just reports the overall average pace scaled to 5 km. The two
/// give the same answer only for runs that were paced perfectly evenly.
///
/// Returns null when the track has fewer than two timestamped points or
/// covers less than [windowMetres] total distance. Segments with missing
/// timestamps are tolerated — the algorithm skips them for the time sum
/// and lets the distance sum continue.
///
/// Algorithm: sliding window. For each endpoint `j`, advance the start
/// `i` forward as long as the window `[i+1, j]` still covers at least
/// [windowMetres]. When the window crosses the exact [windowMetres]
/// boundary, linearly interpolate inside the [i, i+1] segment to find
/// the precise start time — otherwise the result would be quantised to
/// whichever waypoint first pushed the window over the threshold, which
/// is noisy for sparse tracks. O(n).
Duration? fastestWindowOf(List<Waypoint> track, double windowMetres) {
  final n = track.length;
  if (n < 2 || windowMetres <= 0) return null;

  final cum = List<double>.filled(n, 0);
  for (var i = 1; i < n; i++) {
    cum[i] = cum[i - 1] +
        haversineMetres(
          track[i - 1].lat,
          track[i - 1].lng,
          track[i].lat,
          track[i].lng,
        );
  }
  if (cum[n - 1] < windowMetres) return null;

  Duration? best;
  var i = 0;
  for (var j = 1; j < n; j++) {
    while (i + 1 < j && cum[j] - cum[i + 1] >= windowMetres) {
      i++;
    }
    if (cum[j] - cum[i] < windowMetres) continue;

    final ti = track[i].timestamp;
    final tj = track[j].timestamp;
    if (ti == null || tj == null) continue;

    final segDist = cum[i + 1] - cum[i];
    int startMs;
    if (segDist <= 0) {
      startMs = ti.millisecondsSinceEpoch;
    } else {
      final ti1 = track[i + 1].timestamp;
      if (ti1 == null) {
        startMs = ti.millisecondsSinceEpoch;
      } else {
        final targetCum = cum[j] - windowMetres;
        final fraction = ((targetCum - cum[i]) / segDist).clamp(0.0, 1.0);
        final a = ti.millisecondsSinceEpoch;
        final b = ti1.millisecondsSinceEpoch;
        startMs = a + ((b - a) * fraction).round();
      }
    }

    final windowMs = tj.millisecondsSinceEpoch - startMs;
    if (windowMs <= 0) continue;
    final d = Duration(milliseconds: windowMs);
    if (best == null || d < best) best = d;
  }
  return best;
}

/// Great-circle distance between two lat/lng points in metres.
double haversineMetres(
  double lat1,
  double lng1,
  double lat2,
  double lng2,
) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final sinLat = sin(dLat / 2);
  final sinLng = sin(dLng / 2);
  final a = sinLat * sinLat +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sinLng * sinLng;
  return r * 2 * atan2(sqrt(a), sqrt(1 - a));
}
