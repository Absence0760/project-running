/// Pixel-proximity clustering for the route-discovery map pins.
///
/// flutter_map has no native marker clustering (unlike MapLibre on web,
/// which the discovery map uses there), so rather than pull in a new
/// dependency on the byte-identical mobile twin we do the clustering in
/// pure Dart: a single greedy pass that merges any pins within
/// [radiusPx] of each other at the current zoom. The caller supplies a
/// [project] that maps a lat/lng to CRS pixel coordinates at the current
/// zoom (e.g. flutter_map's `MapCamera.project`), so the merge distance
/// is in screen pixels and clusters break apart as you zoom in — the
/// same behaviour as the web cluster layer.
///
/// O(n^2) but n is the per-viewport pin cap (<=100), so it's trivial.
/// Pure functions, no Flutter / flutter_map deps (the projector is
/// injected), which keeps it unit-testable.
library;

typedef ScreenPoint = ({double x, double y});

/// One pin, or a merged group of pins, at a display position. [items]
/// holds the originals; [isCluster] is true when more than one merged.
class PinCluster<T> {
  final double lat;
  final double lng;
  final List<T> items;
  const PinCluster({required this.lat, required this.lng, required this.items});

  bool get isCluster => items.length > 1;
  int get count => items.length;
  T get first => items.first;
}

List<PinCluster<T>> clusterPins<T>({
  required List<T> items,
  required double Function(T) latOf,
  required double Function(T) lngOf,
  required ScreenPoint Function(double lat, double lng) project,
  double radiusPx = 60,
}) {
  final n = items.length;
  if (n == 0) return const [];
  final px = <ScreenPoint>[
    for (final it in items) project(latOf(it), lngOf(it)),
  ];
  final used = List<bool>.filled(n, false);
  final r2 = radiusPx * radiusPx;
  final out = <PinCluster<T>>[];
  for (var i = 0; i < n; i++) {
    if (used[i]) continue;
    used[i] = true;
    final members = <T>[items[i]];
    var sumLat = latOf(items[i]);
    var sumLng = lngOf(items[i]);
    for (var j = i + 1; j < n; j++) {
      if (used[j]) continue;
      final dx = px[i].x - px[j].x;
      final dy = px[i].y - px[j].y;
      if (dx * dx + dy * dy <= r2) {
        used[j] = true;
        members.add(items[j]);
        sumLat += latOf(items[j]);
        sumLng += lngOf(items[j]);
      }
    }
    out.add(PinCluster<T>(
      lat: sumLat / members.length,
      lng: sumLng / members.length,
      items: members,
    ));
  }
  return out;
}
