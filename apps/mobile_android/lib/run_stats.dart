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

    final distance = _haversineMetres(a.lat, a.lng, b.lat, b.lng);
    final speed = distance / (dtMs / 1000.0);
    if (speed >= minSpeedMps) {
      movingMs += dtMs;
    }
  }
  return Duration(milliseconds: movingMs);
}

/// Great-circle distance between two lat/lng points in metres.
double _haversineMetres(
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
