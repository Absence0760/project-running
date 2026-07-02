import 'dart:math';

import 'run_stats.dart' show haversineMetres;

/// Snap a dropped point to a route's polyline.
///
/// Course markers (aid stations, cutoffs, …) are anchored to the course, so
/// the marker editor lets the owner drop / drag a pin and "stick it to the
/// route line". This is the pure projection behind that: given a tapped
/// lng/lat and the route's polyline, return the nearest point ON the line —
/// the perpendicular foot on the closest segment, not merely the nearest
/// vertex — plus where along the route it lands.
///
/// `position_m` for a saved marker is still derived authoritatively
/// server-side (ST_LineLocatePoint against routes.geom, migration
/// 20270129_001), so [alongM] here is a client-side preview only — it lets
/// the editor show an approximate distance while dragging without a round
/// trip. The snapped lng/lat is what makes the pin render exactly on the
/// line.
///
/// Twin of web's `routes/route_snap.ts` (`snapToPolyline`). Keep in lockstep.

class SnapResult {
  const SnapResult({
    required this.lng,
    required this.lat,
    required this.segmentIndex,
    required this.t,
    required this.alongM,
    required this.offsetM,
  });

  /// Snapped longitude — on the polyline.
  final double lng;

  /// Snapped latitude — on the polyline.
  final double lat;

  /// Index `i` of the segment `[coords[i], coords[i+1]]` the point fell on.
  final int segmentIndex;

  /// Fraction in [0,1] along that segment to the foot of the projection.
  final double t;

  /// Cumulative distance from the route start to the snapped point, metres.
  final double alongM;

  /// Perpendicular distance from the input point to the line, metres.
  final double offsetM;

  @override
  bool operator ==(Object other) =>
      other is SnapResult &&
      other.lng == lng &&
      other.lat == lat &&
      other.segmentIndex == segmentIndex &&
      other.t == t &&
      other.alongM == alongM &&
      other.offsetM == offsetM;

  @override
  int get hashCode => Object.hash(lng, lat, segmentIndex, t, alongM, offsetM);
}

/// Project [point] onto the polyline [coords] (`[lng, lat]` pairs) and return
/// the nearest on-line point. Returns null when the polyline has fewer than
/// two points (nothing to snap to). Projection is done in a local
/// equirectangular frame around each segment — accurate to well within a
/// metre at the scale a marker is dropped, and dependency-free.
SnapResult? snapToPolyline(
  ({double lng, double lat}) point,
  List<List<double>> coords,
) {
  if (coords.length < 2) return null;
  if (!point.lng.isFinite || !point.lat.isFinite) return null;

  const r = 6371000.0;
  double toRad(double d) => d * pi / 180;

  SnapResult? best;
  var bestOffset = double.infinity;
  // Running cumulative distance to the START of the current segment.
  var cumulative = 0.0;

  for (var i = 0; i < coords.length - 1; i++) {
    final aLng = coords[i][0];
    final aLat = coords[i][1];
    final bLng = coords[i + 1][0];
    final bLat = coords[i + 1][1];
    final segLen = haversineMetres(aLat, aLng, bLat, bLng);

    // Local planar frame: metres east/north of segment start `a`,
    // with longitude scaled by cos(lat) so a degree of lng matches a
    // degree of lat in ground distance.
    final cosLat = cos(toRad(aLat));
    const ax = 0.0;
    const ay = 0.0;
    final bx = toRad(bLng - aLng) * r * cosLat;
    final by = toRad(bLat - aLat) * r;
    final px = toRad(point.lng - aLng) * r * cosLat;
    final py = toRad(point.lat - aLat) * r;

    final dx = bx - ax;
    final dy = by - ay;
    final lenSq = dx * dx + dy * dy;
    // Degenerate (duplicate) vertices → treat as the start point.
    final t = lenSq > 0 ? ((px * dx + py * dy) / lenSq).clamp(0.0, 1.0) : 0.0;

    final sLng = aLng + (bLng - aLng) * t;
    final sLat = aLat + (bLat - aLat) * t;
    final offset = haversineMetres(point.lat, point.lng, sLat, sLng);

    if (offset < bestOffset) {
      bestOffset = offset;
      best = SnapResult(
        lng: sLng,
        lat: sLat,
        segmentIndex: i,
        t: t,
        alongM: cumulative + segLen * t,
        offsetM: offset,
      );
    }
    cumulative += segLen;
  }

  return best;
}
