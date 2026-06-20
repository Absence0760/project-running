import 'dart:math';

/// Pure slippy-map tile-enumeration math for offline tile packs. Dart twin of
/// `apps/web/src/lib/routes/tile_pack.ts` — keep the two in lockstep
/// (algorithm, edge cases, test counts).
///
/// The actual tile fetch + disk write lives in `offline_tile_pack.dart`; this
/// pure layer just turns a route bounding box + a zoom range into the
/// `{z,x,y}` tile coordinates that cover it, and caps the count so a huge
/// route × deep zoom can't blow up disk (decisions §167).

class TileBbox {
  const TileBbox({
    required this.minLat,
    required this.minLng,
    required this.maxLat,
    required this.maxLng,
  });
  final double minLat;
  final double minLng;
  final double maxLat;
  final double maxLng;
}

class TileCoord {
  const TileCoord(this.z, this.x, this.y);
  final int z;
  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      other is TileCoord && other.z == z && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(z, x, y);
}

/// Default zoom band for a route pack (decisions §167): z12 (neighbourhood
/// overview) through z16 (street detail) — the band the live run map uses.
const int kDefaultMinZoom = 12;
const int kDefaultMaxZoom = 16;

/// Per-pack hard ceiling. Guards against a pathological bbox silently
/// downloading gigabytes.
const int kMaxTilesPerPack = 5000;

const double _maxMercatorLat = 85.05112878;

/// Number of tiles a bbox would need across [minZoom, maxZoom]. Cheap
/// O(zooms) — used by the cap guard and a size preview without enumerating.
int estimateTileCount(
  TileBbox bbox, {
  int minZoom = kDefaultMinZoom,
  int maxZoom = kDefaultMaxZoom,
}) {
  final norm = _normaliseBbox(bbox);
  var total = 0;
  for (var z = minZoom; z <= maxZoom; z++) {
    final r = _tileRange(norm, z);
    total += (r.xMax - r.xMin + 1) * (r.yMax - r.yMin + 1);
  }
  return total;
}

/// Enumerate every `{z,x,y}` tile covering [bbox] across the inclusive zoom
/// range. Throws when the count would exceed [maxTiles] (default
/// [kMaxTilesPerPack]) so the caller surfaces a "too large" warning rather
/// than starting an unbounded download. A degenerate (zero-area) bbox still
/// yields the single tile its point falls in.
List<TileCoord> tilesForBbox(
  TileBbox bbox, {
  int minZoom = kDefaultMinZoom,
  int maxZoom = kDefaultMaxZoom,
  int maxTiles = kMaxTilesPerPack,
}) {
  if (minZoom > maxZoom) {
    throw ArgumentError('minZoom $minZoom > maxZoom $maxZoom');
  }
  final norm = _normaliseBbox(bbox);
  final count = estimateTileCount(norm, minZoom: minZoom, maxZoom: maxZoom);
  if (count > maxTiles) {
    throw StateError('tile pack would need $count tiles, over the $maxTiles cap');
  }
  final tiles = <TileCoord>[];
  for (var z = minZoom; z <= maxZoom; z++) {
    final r = _tileRange(norm, z);
    for (var x = r.xMin; x <= r.xMax; x++) {
      for (var y = r.yMin; y <= r.yMax; y++) {
        tiles.add(TileCoord(z, x, y));
      }
    }
  }
  return tiles;
}

TileBbox _normaliseBbox(TileBbox bbox) {
  final minLat = _clamp(min(bbox.minLat, bbox.maxLat), -_maxMercatorLat, _maxMercatorLat);
  final maxLat = _clamp(max(bbox.minLat, bbox.maxLat), -_maxMercatorLat, _maxMercatorLat);
  final minLng = _clamp(min(bbox.minLng, bbox.maxLng), -180, 180);
  final maxLng = _clamp(max(bbox.minLng, bbox.maxLng), -180, 180);
  return TileBbox(minLat: minLat, minLng: minLng, maxLat: maxLat, maxLng: maxLng);
}

class _Range {
  const _Range(this.xMin, this.xMax, this.yMin, this.yMax);
  final int xMin;
  final int xMax;
  final int yMin;
  final int yMax;
}

_Range _tileRange(TileBbox bbox, int z) {
  final n = 1 << z;
  final xMin = _clampTile(_lngToTileX(bbox.minLng, z), n);
  final xMax = _clampTile(_lngToTileX(bbox.maxLng, z), n);
  // y grows southward, so maxLat → smaller y.
  final yMin = _clampTile(_latToTileY(bbox.maxLat, z), n);
  final yMax = _clampTile(_latToTileY(bbox.minLat, z), n);
  return _Range(xMin, xMax, yMin, yMax);
}

int _lngToTileX(double lng, int z) {
  final n = 1 << z;
  return ((lng + 180) / 360 * n).floor();
}

int _latToTileY(double lat, int z) {
  final n = 1 << z;
  final rad = lat * pi / 180;
  return ((1 - log(tan(rad) + 1 / cos(rad)) / pi) / 2 * n).floor();
}

int _clampTile(int v, int n) => min(n - 1, max(0, v));

double _clamp(double v, double lo, double hi) => min(hi, max(lo, v));
