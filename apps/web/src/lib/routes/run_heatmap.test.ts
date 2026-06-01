import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	buildHeatCells,
	heatBounds,
	toHeatGeoJSON,
	toTrackLinesGeoJSON,
	DEFAULT_GRID_DEG,
	MAX_CELL_WEIGHT,
} from './run_heatmap';

test('collapses many points within one grid cell into a single weighted cell', () => {
	// 10 points within ~10 m of each other → one cell, weight 10.
	const track = Array.from({ length: 10 }, (_, i) => ({
		lat: 51.5 + i * 0.00001,
		lng: -0.12 + i * 0.00001,
	}));
	const cells = buildHeatCells([track]);
	assert.equal(cells.length, 1);
	assert.equal(cells[0].weight, 10);
});

test('repeated routes accumulate weight in shared cells', () => {
	const track = [
		{ lat: 40.0, lng: -75.0 },
		{ lat: 40.001, lng: -75.0 },
	];
	const single = buildHeatCells([track]);
	const tripled = buildHeatCells([track, track, track]);
	// Same cell footprint, 3x the weight.
	assert.equal(single.length, tripled.length);
	const sumSingle = single.reduce((s, c) => s + c.weight, 0);
	const sumTripled = tripled.reduce((s, c) => s + c.weight, 0);
	assert.equal(sumTripled, sumSingle * 3);
});

test('distinct locations produce distinct cells', () => {
	const cells = buildHeatCells([
		[{ lat: 51.5, lng: -0.12 }],
		[{ lat: 48.85, lng: 2.35 }],
	]);
	assert.equal(cells.length, 2);
});

test('clamps a single cells weight at MAX_CELL_WEIGHT', () => {
	const track = Array.from({ length: MAX_CELL_WEIGHT + 200 }, () => ({
		lat: 34.05,
		lng: -118.24,
	}));
	const cells = buildHeatCells([track]);
	assert.equal(cells.length, 1);
	assert.equal(cells[0].weight, MAX_CELL_WEIGHT);
});

test('drops invalid / out-of-range points', () => {
	const cells = buildHeatCells([
		[
			{ lat: NaN, lng: 0 },
			{ lat: 0, lng: Infinity },
			{ lat: 200, lng: 0 },
			{ lat: 0, lng: -400 },
			{ lat: 45, lng: 9 }, // the only valid one
		] as never,
	]);
	assert.equal(cells.length, 1);
	assert.equal(cells[0].weight, 1);
});

test('empty / all-invalid input yields no cells and null bounds', () => {
	assert.deepEqual(buildHeatCells([]), []);
	assert.deepEqual(buildHeatCells([[]]), []);
	assert.equal(heatBounds([]), null);
});

test('heatBounds spans the cell extent as [[w,s],[e,n]]', () => {
	const cells = buildHeatCells([
		[
			{ lat: 10, lng: 20 },
			{ lat: 30, lng: 40 },
		],
	]);
	const b = heatBounds(cells)!;
	assert.ok(b);
	const [[w, s], [e, n]] = b;
	// Cells snap to grid centres, so each edge can sit within one grid
	// step of the raw extent.
	const tol = DEFAULT_GRID_DEG;
	assert.ok(Math.abs(w - 20) <= tol && Math.abs(s - 10) <= tol);
	assert.ok(Math.abs(e - 40) <= tol && Math.abs(n - 30) <= tol);
	assert.ok(w <= e && s <= n);
});

test('invalid gridDeg falls back to the default', () => {
	const track = [{ lat: 1, lng: 1 }];
	assert.deepEqual(buildHeatCells([track], 0), buildHeatCells([track], DEFAULT_GRID_DEG));
	assert.deepEqual(buildHeatCells([track], -5), buildHeatCells([track], DEFAULT_GRID_DEG));
});

test('toHeatGeoJSON emits one weighted point feature per cell', () => {
	const cells = buildHeatCells([
		[
			{ lat: 1, lng: 1 },
			{ lat: 1, lng: 1 },
			{ lat: 2, lng: 2 },
		],
	]);
	const fc = toHeatGeoJSON(cells);
	assert.equal(fc.type, 'FeatureCollection');
	assert.equal(fc.features.length, cells.length);
	for (const f of fc.features) {
		assert.equal(f.geometry.type, 'Point');
		assert.equal(f.geometry.coordinates.length, 2);
		assert.ok(typeof f.properties.weight === 'number' && f.properties.weight >= 1);
	}
});

test('toTrackLinesGeoJSON emits one LineString per track in [lng,lat] order', () => {
	const fc = toTrackLinesGeoJSON([
		[
			{ lat: 1, lng: 2 },
			{ lat: 3, lng: 4 },
		],
		[
			{ lat: 5, lng: 6 },
			{ lat: 7, lng: 8 },
			{ lat: 9, lng: 10 },
		],
	]);
	assert.equal(fc.type, 'FeatureCollection');
	assert.equal(fc.features.length, 2);
	assert.equal(fc.features[0].geometry.type, 'LineString');
	// [lng, lat] order — GeoJSON convention.
	assert.deepEqual(fc.features[0].geometry.coordinates, [
		[2, 1],
		[4, 3],
	]);
	assert.equal(fc.features[1].geometry.coordinates.length, 3);
});

test('toTrackLinesGeoJSON drops invalid points and skips sub-2-point tracks', () => {
	const fc = toTrackLinesGeoJSON([
		// One valid point left after filtering → no feature.
		[
			{ lat: NaN, lng: 0 },
			{ lat: 45, lng: 9 },
		] as never,
		// Two valid points survive the filter → one feature.
		[
			{ lat: 200, lng: 0 },
			{ lat: 10, lng: 20 },
			{ lat: 11, lng: 21 },
		] as never,
		[], // empty → no feature
	]);
	assert.equal(fc.features.length, 1);
	assert.deepEqual(fc.features[0].geometry.coordinates, [
		[20, 10],
		[21, 11],
	]);
});

test('toTrackLinesGeoJSON returns an empty collection for empty input', () => {
	assert.deepEqual(toTrackLinesGeoJSON([]), {
		type: 'FeatureCollection',
		features: [],
	});
});
