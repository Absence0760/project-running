import 'package:core_models/core_models.dart' show Waypoint;

import 'run_stats.dart' show haversineMetres;

/// Detect "out-and-back" overlap on a route — the user passes through
/// the same physical segment twice (typically: run out, turn around,
/// run back the same way). The web equivalent (`RouteBuilder.svelte`)
/// renders these segments purple. Today the web is stubbed (overlap
/// source set to `coordinates: []`); this Dart impl is the working
/// version.
///
/// Algorithm — for each pair of non-adjacent polyline segments,
/// check whether they cover the same line within [toleranceM] metres:
///   1. their endpoints are within `2 * toleranceM` of each other in
///      either alignment (forward / reverse — out-and-back is reverse),
///   2. and the midpoints are within `toleranceM` of each other.
///
/// O(n²) — fine up to a few hundred points, which matches the OSRM
/// output for typical city routes. For long routes we sample down to
/// [maxScannedPoints] points first (default 200) so the cost stays
/// bounded.

/// A contiguous polyline slice that overlaps an earlier slice. Indices
/// reference the input polyline.
class OverlapSpan {
  final int startIndex;
  final int endIndex; // inclusive
  const OverlapSpan({required this.startIndex, required this.endIndex});

  /// True when [index] sits inside this span.
  bool contains(int index) => index >= startIndex && index <= endIndex;
}

/// Returns a list of [OverlapSpan] covering polyline indices that
/// retrace an earlier section. Empty list when no overlap is found or
/// when the polyline is too short to overlap itself.
///
/// [toleranceM]: how close two segments must be to count as the same
/// piece of road. Defaults to 20 m — generous enough that minor OSRM
/// jitter on an out-and-back returns the same segment, strict enough
/// that genuinely-parallel-but-not-overlapping streets don't trip it.
List<OverlapSpan> detectOverlapSpans(
  List<Waypoint> polyline, {
  double toleranceM = 20,
  int maxScannedPoints = 200,
}) {
  if (polyline.length < 4) return const [];
  // Down-sample for the segment-pair scan but report indices in the
  // original frame.
  final scanned = polyline.length <= maxScannedPoints
      ? polyline
      : _downsample(polyline, maxScannedPoints);
  final isSampled = !identical(scanned, polyline);
  final stride = isSampled ? polyline.length / scanned.length : 1.0;

  // Precompute cumulative path distance so we can skip segment pairs
  // that sit too close along the route — a dense polyline (e.g. OSRM
  // emits ~1 m steps on long straights) trips a naive endpoint check
  // because consecutive segments share endpoints inside the budget.
  // Two segments must be > 2 × toleranceM apart along the route to
  // count as "retrace candidates"; closer than that and they're
  // either adjacent or near-adjacent on the same line.
  final cum = <double>[0];
  for (var k = 1; k < scanned.length; k++) {
    cum.add(
      cum[k - 1] +
          haversineMetres(
            scanned[k - 1].lat,
            scanned[k - 1].lng,
            scanned[k].lat,
            scanned[k].lng,
          ),
    );
  }
  final minGapM = toleranceM * 2;

  final hits = <int>{};
  for (var i = 0; i + 1 < scanned.length - 2; i++) {
    final a1 = scanned[i];
    final a2 = scanned[i + 1];
    for (var j = i + 2; j + 1 < scanned.length; j++) {
      // Path-distance gate — endpoint of A to start of B must exceed
      // the minimum gap, else this is just "next segment on the same
      // line" rather than "retracing the same piece of road later".
      if (cum[j] - cum[i + 1] < minGapM) continue;
      final b1 = scanned[j];
      final b2 = scanned[j + 1];
      if (_segmentsOverlap(a1, a2, b1, b2, toleranceM)) {
        // Both segments retrace each other — mark both in original
        // index space.
        final iOrig = (i * stride).round();
        final jOrig = (j * stride).round();
        hits.add(iOrig);
        hits.add(iOrig + 1);
        hits.add(jOrig);
        hits.add(jOrig + 1);
      }
    }
  }
  if (hits.isEmpty) return const [];
  return _collapseToSpans(hits.toList()..sort());
}

bool _segmentsOverlap(
  Waypoint a1,
  Waypoint a2,
  Waypoint b1,
  Waypoint b2,
  double toleranceM,
) {
  // Endpoints aligned forward OR reverse (out-and-back is reverse).
  final endpointBudget = toleranceM * 2;
  final forward = haversineMetres(a1.lat, a1.lng, b1.lat, b1.lng) <
          endpointBudget &&
      haversineMetres(a2.lat, a2.lng, b2.lat, b2.lng) < endpointBudget;
  final reverse = haversineMetres(a1.lat, a1.lng, b2.lat, b2.lng) <
          endpointBudget &&
      haversineMetres(a2.lat, a2.lng, b1.lat, b1.lng) < endpointBudget;
  if (!forward && !reverse) return false;
  // Midpoints close — confirms the line shape and rules out the
  // accidental case of two endpoints landing near each other on
  // intersecting roads at right angles.
  final midA = Waypoint(
    lat: (a1.lat + a2.lat) / 2,
    lng: (a1.lng + a2.lng) / 2,
  );
  final midB = Waypoint(
    lat: (b1.lat + b2.lat) / 2,
    lng: (b1.lng + b2.lng) / 2,
  );
  return haversineMetres(midA.lat, midA.lng, midB.lat, midB.lng) <
      toleranceM;
}

List<Waypoint> _downsample(List<Waypoint> coordinates, int maxPoints) {
  if (coordinates.length <= maxPoints) return coordinates;
  final step = (coordinates.length - 1) / (maxPoints - 1);
  return [
    for (var i = 0; i < maxPoints; i++) coordinates[(i * step).round()],
  ];
}

List<OverlapSpan> _collapseToSpans(List<int> sortedHits) {
  final out = <OverlapSpan>[];
  var start = sortedHits.first;
  var prev = start;
  for (var k = 1; k < sortedHits.length; k++) {
    final cur = sortedHits[k];
    if (cur == prev || cur == prev + 1) {
      prev = cur;
      continue;
    }
    out.add(OverlapSpan(startIndex: start, endIndex: prev));
    start = cur;
    prev = cur;
  }
  out.add(OverlapSpan(startIndex: start, endIndex: prev));
  return out;
}
