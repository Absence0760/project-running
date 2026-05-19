/// Pure waypoint-generation helpers for the Route Builder's
/// "Generate by distance" feature. Mirrors
/// `apps/web/src/lib/route_loop.ts` — keep in lockstep (the math has
/// had two field-reported bugs around degenerate inputs, so changes
/// on either side must land on both).
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'run_stats.dart' show haversineMetres;

/// Two endpoints closer than this are treated as the same point — the
/// user wanted a loop and the slight delta is just map-click precision.
/// Below this distance the point-to-point math degenerates (perp
/// offset → 0 because dLat/dLng → 0) and the next iteration's
/// scaleFactor explodes.
const double kNearPointMetres = 50;

/// Absolute scaleFactor bounds the bisection search will never exceed.
const double kScaleFactorMin = 0.05;
const double kScaleFactorMax = 2;

/// Empirical starting scale for the default 4-waypoint (square)
/// layout. See web `route_loop.ts` for the derivation comment.
const double kDefaultScaleFactor = 0.65;

/// Number of interior radial waypoints in the scaffolding pattern.
/// 4 (square) is the sweet spot.
const int kDefaultNumPoints = 4;

/// Acceptance band — within this ratio range of the target we stop
/// adjusting.
const double kAcceptBandMin = 0.85;
const double kAcceptBandMax = 1.15;

/// Upper bound for a sane Generate-by-distance target. 1000 km past
/// any documented road run — anything beyond is almost certainly a
/// unit-conversion bug.
const double kMaxTargetDistanceMetres = 1_000_000;

/// Reject NaN, Infinity, non-positive, and the absurd-large case at
/// the API boundary instead of burning iteration attempts.
bool isValidTargetDistance(num? m) {
  if (m == null) return false;
  if (!m.isFinite) return false;
  if (m <= 0) return false;
  if (m > kMaxTargetDistanceMetres) return false;
  return true;
}

class ScaleRange {
  final double lower;
  final double upper;
  const ScaleRange(this.lower, this.upper);
}

ScaleRange initScaleRange() =>
    const ScaleRange(kScaleFactorMin, kScaleFactorMax);

/// Bisect the scaleFactor toward a target distance. Robust when
/// OSRM's actual distance is a noisy / non-monotonic function of
/// scale.
({double scale, ScaleRange range}) bisectScale({
  required ScaleRange range,
  required double currentScale,
  required double targetDistanceMetres,
  required double actualDistanceMetres,
}) {
  var lower = range.lower;
  var upper = range.upper;
  if (actualDistanceMetres > targetDistanceMetres) {
    upper = math.min(upper, currentScale);
  } else {
    lower = math.max(lower, currentScale);
  }
  var next = (lower + upper) / 2;
  next = next.clamp(kScaleFactorMin, kScaleFactorMax);
  return (scale: next, range: ScaleRange(lower, upper));
}

/// Is the actual distance within the acceptance band of the target?
bool isWithinAcceptBand({
  required double targetDistanceMetres,
  required double actualDistanceMetres,
}) {
  if (actualDistanceMetres <= 0) return false;
  final ratio = targetDistanceMetres / actualDistanceMetres;
  return ratio > kAcceptBandMin && ratio < kAcceptBandMax;
}

/// Generate the waypoint sequence for a Generate-by-distance request.
///
/// Returns `[start, ...inner, closing]` — what the routing code feeds
/// into OSRM. Does not call OSRM itself.
///
/// When [end] is null OR within [kNearPointMetres] of [start], emits a
/// closed loop of [numPoints] radial waypoints around start at radius
/// `(targetDistanceMetres * scaleFactor) / (2π)` plus a closing
/// waypoint at start. Otherwise emits a curved point-to-point.
List<LatLng> generateLoopWaypoints({
  required LatLng start,
  LatLng? end,
  required double targetDistanceMetres,
  double scaleFactor = kDefaultScaleFactor,
  int numPoints = kDefaultNumPoints,
  double radialSeedRad = 0,
}) {
  final startEndDistM = end == null
      ? 0.0
      : haversineMetres(start.latitude, start.longitude, end.latitude, end.longitude);
  final isLoop = end == null || startEndDistM < kNearPointMetres;

  if (isLoop) {
    final radiusM = (targetDistanceMetres * scaleFactor) / (2 * math.pi);
    final radiusDeg = radiusM / 111320;
    final cosLat = math.cos(start.latitude * math.pi / 180);

    final out = <LatLng>[LatLng(start.latitude, start.longitude)];
    for (var i = 1; i <= numPoints; i++) {
      final angle = radialSeedRad + (i / numPoints) * math.pi * 2;
      out.add(LatLng(
        start.latitude + math.sin(angle) * radiusDeg,
        start.longitude + (math.cos(angle) * radiusDeg) / cosLat,
      ));
    }
    out.add(LatLng(start.latitude, start.longitude));
    return out;
  }

  // Point-to-point with a perpendicular curve sized to hit the target.
  final e = end;
  final directDist = startEndDistM;
  final curveAmount = math.max(
    0,
    (targetDistanceMetres * scaleFactor - directDist) /
        math.max(directDist, 1),
  );
  final dLat = e.latitude - start.latitude;
  final dLng = e.longitude - start.longitude;
  final perpLat = -dLng * curveAmount * 0.4;
  final perpLng = dLat * curveAmount * 0.4;

  final out = <LatLng>[LatLng(start.latitude, start.longitude)];
  for (var i = 1; i <= numPoints; i++) {
    final t = i / (numPoints + 1);
    final curveFactor = math.sin(t * math.pi);
    out.add(LatLng(
      start.latitude + dLat * t + perpLat * curveFactor,
      start.longitude + dLng * t + perpLng * curveFactor,
    ));
  }
  out.add(LatLng(e.latitude, e.longitude));
  return out;
}

/// Select the visible waypoints to keep AFTER a successful generate.
/// The scaffolding waypoints are an implementation detail — collapse
/// down to 4 anchors: start, two mid-polyline samples, close.
List<LatLng> selectLoopAnchors({
  required List<LatLng> polyline,
  required LatLng start,
  required LatLng close,
}) {
  final out = <LatLng>[LatLng(start.latitude, start.longitude)];
  if (polyline.length >= 4) {
    final mid1Idx = math.max(1, (polyline.length / 3).round());
    final mid2Idx = math.min(
      polyline.length - 2,
      (2 * polyline.length / 3).round(),
    );
    out.add(polyline[mid1Idx]);
    if (mid2Idx > mid1Idx) {
      out.add(polyline[mid2Idx]);
    }
  }
  out.add(LatLng(close.latitude, close.longitude));
  return out;
}
