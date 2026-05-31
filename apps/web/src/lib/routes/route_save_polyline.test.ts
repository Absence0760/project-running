import { test } from 'node:test';
import assert from 'node:assert/strict';

import { pickSavePolyline } from './route_save_polyline';

test('pickSavePolyline returns the snapped polyline when Calculate Route succeeded', () => {
	const clicks = [
		{ lat: 38.9, lng: -77.0 },
		{ lat: 38.91, lng: -77.01 },
	];
	const coords: [number, number][] = [
		[-77.0, 38.9],
		[-77.001, 38.901],
		[-77.002, 38.902],
		[-77.005, 38.905],
		[-77.01, 38.91],
	];
	const result = pickSavePolyline(clicks, coords);
	assert.equal(result.length, 5);
	assert.deepEqual(result[0], { lat: 38.9, lng: -77.0 });
	assert.deepEqual(result[4], { lat: 38.91, lng: -77.01 });
});

test('pickSavePolyline preserves [lng, lat] → {lat, lng} ordering', () => {
	// Regression guard: the [lng, lat] convention from MapLibre / GeoJSON
	// flipped vs the {lat, lng} convention from supabase rows is the
	// thing most likely to silently break the thumbnails. If this test
	// fails by swapping fields, every saved route puts itself in the
	// wrong hemisphere.
	const coords: [number, number][] = [[-77.0, 38.9], [-77.1, 38.91]];
	const result = pickSavePolyline([], coords);
	assert.equal(result[0].lat, 38.9);
	assert.equal(result[0].lng, -77.0);
	assert.equal(result[1].lat, 38.91);
	assert.equal(result[1].lng, -77.1);
});

test('pickSavePolyline falls back to click points when no snapped route exists', () => {
	const clicks = [
		{ lat: 38.9, lng: -77.0 },
		{ lat: 38.91, lng: -77.01 },
	];
	const result = pickSavePolyline(clicks, []);
	assert.equal(result.length, 2);
	assert.deepEqual(result, clicks);
});

test('pickSavePolyline falls back when only a single coord is present', () => {
	// A 1-point "polyline" is degenerate. Prefer the clicks (which are
	// guaranteed to be >= 2 by the Save button gate).
	const clicks = [
		{ lat: 38.9, lng: -77.0 },
		{ lat: 38.91, lng: -77.01 },
	];
	const result = pickSavePolyline(clicks, [[-77.0, 38.9]]);
	assert.equal(result.length, 2);
	assert.deepEqual(result, clicks);
});
