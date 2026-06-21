/// Pure aggregation for the personal run-track heatmap (mobile mirror of
/// web `/runs/heatmap`, persona-hunt finding #53). Flattens many of the
/// runner's own GPS tracks into weighted grid cells: repeated routes
/// accumulate weight in the same cell instead of exploding the point
/// count, so the flutter_map heat layer can render thousands of runs
/// without one circle per raw sample. Dart twin of
/// `apps/web/src/lib/routes/run_heatmap.ts` — keep in lockstep. The
/// GeoJSON emitters on the web side are MapLibre-specific; the mobile
/// renderer consumes [HeatCell]s + tracks directly, so only the pure
/// aggregation (`buildHeatCells` / `heatBounds`) is shared here.
library;

class HeatLatLng {
  final double lat;
  final double lng;
  const HeatLatLng(this.lat, this.lng);
}

class HeatCell {
  final double lat;
  final double lng;
  final int weight;
  const HeatCell({required this.lat, required this.lng, required this.weight});
}

/// ~33 m at the equator. Fine enough that distinct streets stay distinct,
/// coarse enough that one route's thousands of samples collapse to a
/// manageable cell count.
const double kDefaultGridDeg = 0.0003;

/// Largest weight a single cell reports. A daily-commute cell would
/// otherwise dwarf everything else and flatten the rest of the map to one
/// colour; clamping keeps the gradient legible.
const int kMaxCellWeight = 50;

bool _isFinitePoint(HeatLatLng? p) {
  return p != null &&
      p.lat.isFinite &&
      p.lng.isFinite &&
      p.lat.abs() <= 90 &&
      p.lng.abs() <= 180;
}

/// Quantise every point of every track into a grid and sum hits per cell.
/// Each cell's coordinate is its grid-centre; weight is the clamped hit
/// count. Empty / all-invalid input yields an empty list.
List<HeatCell> buildHeatCells(
  List<List<HeatLatLng>> tracks, {
  double gridDeg = kDefaultGridDeg,
}) {
  if (!(gridDeg > 0)) gridDeg = kDefaultGridDeg;
  final counts = <String, int>{};
  for (final track in tracks) {
    for (final p in track) {
      if (!_isFinitePoint(p)) continue;
      // Round-half-toward-+Infinity to match JS `Math.round` exactly: Dart's
      // `.round()` rounds half AWAY from zero, so a negative coordinate landing
      // on a grid half-boundary (the Americas / west of Greenwich) would
      // quantise to a different cell than the web twin. `(x+0.5).floor()`
      // reproduces `Math.round` for every sign.
      final gx = (p.lng / gridDeg + 0.5).floor();
      final gy = (p.lat / gridDeg + 0.5).floor();
      final key = '$gx:$gy';
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final cells = <HeatCell>[];
  counts.forEach((key, count) {
    final parts = key.split(':');
    final gx = int.parse(parts[0]);
    final gy = int.parse(parts[1]);
    cells.add(HeatCell(
      lng: gx * gridDeg,
      lat: gy * gridDeg,
      weight: count < kMaxCellWeight ? count : kMaxCellWeight,
    ));
  });
  return cells;
}

/// Bounding box of a set of cells as `[[west, south], [east, north]]`.
/// Null when there's nothing to fit.
List<List<double>>? heatBounds(List<HeatCell> cells) {
  if (cells.isEmpty) return null;
  var minLat = double.infinity;
  var minLng = double.infinity;
  var maxLat = double.negativeInfinity;
  var maxLng = double.negativeInfinity;
  for (final c in cells) {
    if (c.lat < minLat) minLat = c.lat;
    if (c.lat > maxLat) maxLat = c.lat;
    if (c.lng < minLng) minLng = c.lng;
    if (c.lng > maxLng) maxLng = c.lng;
  }
  return [
    [minLng, minLat],
    [maxLng, maxLat],
  ];
}
