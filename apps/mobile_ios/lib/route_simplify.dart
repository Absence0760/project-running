import 'dart:math' as math;

import 'package:core_models/core_models.dart';

/// Simplify a polyline using the Ramer–Douglas–Peucker algorithm. Returns
/// a subset of [points] that preserves the shape within [epsilonMetres] of
/// perpendicular distance from the straight-line segments. Used to turn a
/// noisy GPS track from a run into a cleaner saved route.
///
/// 10 m is a good default for running — it collapses jitter while keeping
/// every turn the runner actually took.
List<Waypoint> simplifyTrack(
  List<Waypoint> points, {
  double epsilonMetres = 10,
}) {
  if (points.length < 3) return List.of(points);

  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;
  _dpStep(points, 0, points.length - 1, epsilonMetres, keep);

  final out = <Waypoint>[];
  for (int i = 0; i < points.length; i++) {
    if (keep[i]) out.add(points[i]);
  }
  return out;
}

void _dpStep(
  List<Waypoint> points,
  int first,
  int last,
  double eps,
  List<bool> keep,
) {
  if (last <= first + 1) return;
  double maxDist = 0;
  int maxIndex = first;
  for (int i = first + 1; i < last; i++) {
    final d = _perpDistanceMetres(points[i], points[first], points[last]);
    if (d > maxDist) {
      maxDist = d;
      maxIndex = i;
    }
  }
  if (maxDist > eps) {
    keep[maxIndex] = true;
    _dpStep(points, first, maxIndex, eps, keep);
    _dpStep(points, maxIndex, last, eps, keep);
  }
}

/// Perpendicular distance from [point] to the segment [a..b], in metres.
/// Uses an equirectangular projection — accurate enough at the ~100 m scale
/// Douglas–Peucker cares about, and vastly cheaper than per-point great
/// circle math.
double _perpDistanceMetres(Waypoint point, Waypoint a, Waypoint b) {
  const r = 6371000.0;
  final latRad = a.lat * math.pi / 180;
  final cosLat = math.cos(latRad);

  double x(Waypoint w) => w.lng * math.pi / 180 * cosLat * r;
  double y(Waypoint w) => w.lat * math.pi / 180 * r;

  final ax = x(a);
  final ay = y(a);
  final bx = x(b);
  final by = y(b);
  final px = x(point);
  final py = y(point);

  final dx = bx - ax;
  final dy = by - ay;
  final lengthSq = dx * dx + dy * dy;
  if (lengthSq == 0) {
    final ex = px - ax;
    final ey = py - ay;
    return math.sqrt(ex * ex + ey * ey);
  }

  final t = (((px - ax) * dx) + ((py - ay) * dy)) / lengthSq;
  final tClamped = t.clamp(0.0, 1.0);
  final projX = ax + tClamped * dx;
  final projY = ay + tClamped * dy;
  final fx = px - projX;
  final fy = py - projY;
  return math.sqrt(fx * fx + fy * fy);
}

/// Total positive elevation change across the track, in metres. Waypoints
/// without elevation readings are skipped.
double computeElevationGain(List<Waypoint> track) {
  double gain = 0;
  for (int i = 1; i < track.length; i++) {
    final prev = track[i - 1].elevationMetres;
    final curr = track[i].elevationMetres;
    if (prev != null && curr != null && curr > prev) {
      gain += curr - prev;
    }
  }
  return gain;
}
