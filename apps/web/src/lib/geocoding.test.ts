import { test } from 'node:test';
import assert from 'node:assert/strict';

import { bboxRadius, haversineM } from './geocoding_math';

test('bboxRadius for the state of Virginia bbox returns roughly half its diagonal', () => {
	// Approximate MapTiler bbox for "Virginia, United States".
	const bbox: [number, number, number, number] = [-83.675, 36.541, -75.166, 39.466];
	const center = { lng: -78.6569, lat: 37.4316 };
	const r = bboxRadius(bbox, center);
	// Virginia is ~700km wide and ~300km tall — radius from centroid
	// to a corner should land in the 400-500km band.
	assert.ok(r > 350_000, `expected > 350km, got ${r}`);
	assert.ok(r < 550_000, `expected < 550km, got ${r}`);
});

test('bboxRadius for a city-scale bbox returns roughly the city diagonal', () => {
	// Approximate MapTiler bbox for "Richmond, Virginia".
	const bbox: [number, number, number, number] = [-77.59, 37.45, -77.39, 37.61];
	const center = { lng: -77.49, lat: 37.54 };
	const r = bboxRadius(bbox, center);
	assert.ok(r > 8_000, `expected > 8km, got ${r}`);
	assert.ok(r < 25_000, `expected < 25km, got ${r}`);
});

test('haversineM returns 0 for identical points', () => {
	const p = { lng: -77.0, lat: 38.9 };
	assert.equal(haversineM(p, p), 0);
});

test('haversineM is symmetric', () => {
	const a = { lng: -77.0, lat: 38.9 };
	const b = { lng: -77.1, lat: 38.91 };
	assert.equal(haversineM(a, b).toFixed(2), haversineM(b, a).toFixed(2));
});

test('haversineM ballparks the Washington DC ↔ Richmond distance correctly', () => {
	// DC ≈ (38.90, -77.04), Richmond ≈ (37.54, -77.43) — ~150km apart.
	const dc = { lng: -77.04, lat: 38.90 };
	const richmond = { lng: -77.43, lat: 37.54 };
	const d = haversineM(dc, richmond);
	assert.ok(d > 140_000 && d < 170_000, `expected ~150km, got ${d}`);
});
