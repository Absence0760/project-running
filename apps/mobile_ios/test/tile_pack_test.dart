import 'package:flutter_test/flutter_test.dart';

import '../lib/tile_pack.dart';

/// Mirror of `apps/web/src/lib/routes/tile_pack.test.ts`. Keep these 8
/// cases in lockstep. Pure slippy-map math, so both platforms must
/// enumerate identical tile sets.
void main() {
  const smallBox =
      TileBbox(minLat: 47.36, minLng: 8.53, maxLat: 47.39, maxLng: 8.56);

  test('a small bbox at a single zoom yields the covering tile rectangle', () {
    final tiles = tilesForBbox(smallBox, minZoom: 14, maxZoom: 14);
    expect(tiles.length, greaterThanOrEqualTo(1));
    expect(tiles.every((t) => t.z == 14), isTrue);
    final xs = tiles.map((t) => t.x).toSet();
    final ys = tiles.map((t) => t.y).toSet();
    expect(tiles.length, xs.length * ys.length);
  });

  test('multi-zoom is the union of each zooms tile set', () {
    final z14 = tilesForBbox(smallBox, minZoom: 14, maxZoom: 14).length;
    final z15 = tilesForBbox(smallBox, minZoom: 15, maxZoom: 15).length;
    final both = tilesForBbox(smallBox, minZoom: 14, maxZoom: 15).length;
    expect(both, z14 + z15);
  });

  test('a deeper zoom never has fewer tiles than a shallower one', () {
    final z12 = tilesForBbox(smallBox, minZoom: 12, maxZoom: 12).length;
    final z16 = tilesForBbox(smallBox, minZoom: 16, maxZoom: 16).length;
    expect(z16, greaterThanOrEqualTo(z12));
  });

  test('estimateTileCount matches the enumerated length', () {
    expect(
      estimateTileCount(smallBox, minZoom: 12, maxZoom: 16),
      tilesForBbox(smallBox, minZoom: 12, maxZoom: 16).length,
    );
  });

  test('the count cap throws before enumerating a too-large pack', () {
    const huge = TileBbox(minLat: 0, minLng: 0, maxLat: 60, maxLng: 60);
    expect(
      () => tilesForBbox(huge,
          minZoom: kDefaultMinZoom, maxZoom: kDefaultMaxZoom),
      throwsA(isA<StateError>()),
    );
  });

  test('a custom maxTiles cap is honoured', () {
    expect(
      () => tilesForBbox(smallBox, minZoom: 12, maxZoom: 16, maxTiles: 1),
      throwsA(isA<StateError>()),
    );
  });

  test('a degenerate point bbox yields exactly one tile per zoom', () {
    const point =
        TileBbox(minLat: 47.37, minLng: 8.54, maxLat: 47.37, maxLng: 8.54);
    expect(tilesForBbox(point, minZoom: 14, maxZoom: 14).length, 1);
    expect(tilesForBbox(point, minZoom: 12, maxZoom: 16).length, 5);
  });

  test('swapped min/max corners are normalised, not empty', () {
    const swapped =
        TileBbox(minLat: 47.39, minLng: 8.56, maxLat: 47.36, maxLng: 8.53);
    expect(
      tilesForBbox(swapped, minZoom: 14, maxZoom: 14),
      tilesForBbox(smallBox, minZoom: 14, maxZoom: 14),
    );
  });
}
