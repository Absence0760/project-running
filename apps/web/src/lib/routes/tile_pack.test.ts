import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	estimateTileCount,
	tilesForBbox,
	DEFAULT_MIN_ZOOM,
	DEFAULT_MAX_ZOOM,
	type TileBbox,
} from './tile_pack';

/**
 * Twin of `apps/mobile_android/test/tile_pack_test.dart` — keep these 8
 * cases in lockstep. Pure slippy-map math, so both platforms must enumerate
 * identical tile sets.
 */

const smallBox: TileBbox = { minLat: 47.36, minLng: 8.53, maxLat: 47.39, maxLng: 8.56 };

test('a small bbox at a single zoom yields the covering tile rectangle', () => {
	const tiles = tilesForBbox(smallBox, 14, 14);
	// Every tile is at z14, x/y in-range, and the set is the rectangle product.
	assert.ok(tiles.length >= 1);
	assert.ok(tiles.every((t) => t.z === 14));
	const xs = new Set(tiles.map((t) => t.x));
	const ys = new Set(tiles.map((t) => t.y));
	assert.equal(tiles.length, xs.size * ys.size);
});

test('multi-zoom is the union of each zooms tile set', () => {
	const z14 = tilesForBbox(smallBox, 14, 14).length;
	const z15 = tilesForBbox(smallBox, 15, 15).length;
	const both = tilesForBbox(smallBox, 14, 15).length;
	assert.equal(both, z14 + z15);
});

test('a deeper zoom never has fewer tiles than a shallower one', () => {
	const z12 = tilesForBbox(smallBox, 12, 12).length;
	const z16 = tilesForBbox(smallBox, 16, 16).length;
	assert.ok(z16 >= z12);
});

test('estimateTileCount matches the enumerated length', () => {
	assert.equal(
		estimateTileCount(smallBox, 12, 16),
		tilesForBbox(smallBox, 12, 16).length,
	);
});

test('the count cap throws before enumerating a too-large pack', () => {
	// A continent-sized bbox at the default deep band blows past the cap.
	const huge: TileBbox = { minLat: 0, minLng: 0, maxLat: 60, maxLng: 60 };
	assert.throws(() => tilesForBbox(huge, DEFAULT_MIN_ZOOM, DEFAULT_MAX_ZOOM));
});

test('a custom maxTiles cap is honoured', () => {
	assert.throws(() => tilesForBbox(smallBox, 12, 16, 1));
});

test('a degenerate point bbox yields exactly one tile per zoom', () => {
	const point: TileBbox = { minLat: 47.37, minLng: 8.54, maxLat: 47.37, maxLng: 8.54 };
	assert.equal(tilesForBbox(point, 14, 14).length, 1);
	assert.equal(tilesForBbox(point, 12, 16).length, 5);
});

test('swapped min/max corners are normalised, not empty', () => {
	const swapped: TileBbox = { minLat: 47.39, minLng: 8.56, maxLat: 47.36, maxLng: 8.53 };
	assert.deepEqual(tilesForBbox(swapped, 14, 14), tilesForBbox(smallBox, 14, 14));
});
