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

/// Smallest elevation move that counts as real climb, in metres. Consumer GPS
/// altitude is noisy at the 1-3 m level sample to sample, and a raw 1 Hz sum
/// over a long run integrates that jitter into thousands of metres of vert that
/// never happened. The reference height only moves once a change clears this
/// band in either direction, so noise inside it contributes nothing while a
/// genuine climb is counted in full.
const double kElevationGainMinDeltaM = 3;

/// Total positive elevation change across the track, in metres, over the RAW
/// track — never a simplified one. Twin of `computeElevationGain` in
/// `apps/web/src/lib/routes/route_simplify.ts`; keep in lockstep.
///
/// Two rules, both load-bearing:
///
/// 1. A waypoint with no elevation is skipped and the last valid reading is
///    carried across the gap, so an intermittent dropout (tree cover, a tunnel,
///    satellite reacquisition on a long ultra) doesn't silently erase the climb
///    that spans the missing samples.
/// 2. A change only counts once it clears [kElevationGainMinDeltaM].
///
/// Callers must pass the raw track. Running this over an RDP-simplified
/// polyline reads a hill as flat: RDP measures perpendicular distance in 2-D
/// only, so a straight road over a summit collapses to its endpoints and the
/// climb between them disappears.
/// Total elevation LOSS across the raw track, in metres — the exact mirror of
/// [computeElevationGain], gate and dropout-carry included. Mobile-only: the
/// run-detail screen shows the two side by side, and grading one through the
/// noise band while summing the other raw would read as a bug (a flat road
/// would report 0 m of climb next to hundreds of metres of descent).
double computeElevationLoss(List<Waypoint> track) {
  double loss = 0;
  double? ref;
  for (final p in track) {
    final ele = p.elevationMetres;
    if (ele == null) continue;
    if (ref == null) {
      ref = ele;
      continue;
    }
    final delta = ele - ref;
    if (delta <= -kElevationGainMinDeltaM) {
      loss += -delta;
      ref = ele;
    } else if (delta >= kElevationGainMinDeltaM) {
      ref = ele;
    }
  }
  return loss;
}

double computeElevationGain(List<Waypoint> track) {
  final acc = ElevationGainAccumulator();
  acc.addAll(track);
  return acc.gainMetres;
}

/// Streaming form of [computeElevationGain] — the same gate and dropout-carry,
/// fed one waypoint at a time. The live recording screen sees the track grow
/// every GPS tick and cannot re-scan the whole thing per tick on a multi-hour
/// run, so it holds an accumulator and appends the tail. [computeElevationGain]
/// is this class run to completion, which is what keeps the live counter and
/// the finished-run figure from ever disagreeing.
class ElevationGainAccumulator {
  double _gain = 0;
  double? _ref;

  double get gainMetres => _gain;

  void reset() {
    _gain = 0;
    _ref = null;
  }

  void add(Waypoint point) {
    final ele = point.elevationMetres;
    if (ele == null) return;
    final ref = _ref;
    if (ref == null) {
      _ref = ele;
      return;
    }
    final delta = ele - ref;
    if (delta >= kElevationGainMinDeltaM) {
      _gain += delta;
      _ref = ele;
    } else if (delta <= -kElevationGainMinDeltaM) {
      // A real descent — move the reference down so the next climb is measured
      // from the valley, not from the previous summit.
      _ref = ele;
    }
  }

  void addAll(Iterable<Waypoint> points) {
    for (final p in points) {
      add(p);
    }
  }
}
