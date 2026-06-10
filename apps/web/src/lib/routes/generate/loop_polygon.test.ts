import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	candidatePlacements,
	DEFAULT_PLACEMENT_PARAMS,
	viaPoints,
	type PlacementParams,
} from './loop_polygon';

const M_PER_DEG_LAT = 111320;

function haversineM(
	a: { lat: number; lng: number },
	b: { lat: number; lng: number },
): number {
	const R = 6371000;
	const dLat = ((b.lat - a.lat) * Math.PI) / 180;
	const dLng = ((b.lng - a.lng) * Math.PI) / 180;
	const lat1 = (a.lat * Math.PI) / 180;
	const lat2 = (b.lat * Math.PI) / 180;
	const h =
		Math.sin(dLat / 2) ** 2 +
		Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
	return 2 * R * Math.asin(Math.sqrt(h));
}

test('viaPoints returns k points', () => {
	const pts = viaPoints({ lat: 38.88, lng: -77.1 }, 600, 3, 0);
	assert.equal(pts.length, 3);
	const four = viaPoints({ lat: 38.88, lng: -77.1 }, 600, 4, 0);
	assert.equal(four.length, 4);
});

test('rotation 0 puts the first point due north', () => {
	const start = { lat: 38.88, lng: -77.1 };
	const radiusM = 600;
	const [first] = viaPoints(start, radiusM, 3, 0);
	// Due north: longitude unchanged, latitude offset by radius/mPerDegLat.
	assert.ok(Math.abs(first.lng - start.lng) < 1e-9, 'lng unchanged due north');
	assert.ok(first.lat > start.lat, 'first point is north of start');
	assert.ok(
		Math.abs(first.lat - (start.lat + radiusM / M_PER_DEG_LAT)) < 1e-9,
		'north offset matches radius',
	);
});

test('rotation 90 puts the first point due east', () => {
	const start = { lat: 38.88, lng: -77.1 };
	const [first] = viaPoints(start, 600, 3, 90);
	assert.ok(Math.abs(first.lat - start.lat) < 1e-9, 'lat unchanged due east');
	assert.ok(first.lng > start.lng, 'first point is east of start');
});

test('every via-point sits at radiusM from the start', () => {
	const start = { lat: 51.5, lng: -0.12 };
	const radiusM = 750;
	const pts = viaPoints(start, radiusM, 4, 37);
	for (const p of pts) {
		const d = haversineM(start, p);
		assert.ok(Math.abs(d - radiusM) < radiusM * 0.01, `distance ${d} ≈ ${radiusM}`);
	}
});

test('points are evenly spaced around the ring (equal chord lengths)', () => {
	const start = { lat: 51.5, lng: -0.12 };
	const pts = viaPoints(start, 750, 4, 17);
	const chords: number[] = [];
	for (let i = 0; i < pts.length; i++) {
		chords.push(haversineM(pts[i], pts[(i + 1) % pts.length]));
	}
	for (let i = 1; i < chords.length; i++) {
		assert.ok(
			Math.abs(chords[i] - chords[0]) < chords[0] * 0.01,
			`chord ${chords[i]} ≈ ${chords[0]}`,
		);
	}
});

test('cos(lat) correction keeps the ring circular far from the equator', () => {
	// At 60°N a degree of longitude is half a degree of latitude. Without the
	// correction the east-west span would be double; the north and east points
	// must be equidistant from the start.
	const start = { lat: 60, lng: 10 };
	const north = viaPoints(start, 1000, 4, 0)[0];
	const east = viaPoints(start, 1000, 4, 90)[0];
	assert.ok(
		Math.abs(haversineM(start, north) - haversineM(start, east)) < 10,
		'north and east via-points are equidistant',
	);
});

test('rotation shifts every point by the same bearing', () => {
	const start = { lat: 38.88, lng: -77.1 };
	const a = viaPoints(start, 600, 3, 0);
	const b = viaPoints(start, 600, 3, 120);
	// Rotating by 360/k lands point b[0] on a[1] (the ring is k-fold symmetric).
	assert.ok(Math.abs(b[0].lat - a[1].lat) < 1e-9);
	assert.ok(Math.abs(b[0].lng - a[1].lng) < 1e-9);
});

test('candidatePlacements grid size = K × rotationCount × radiusFractions', () => {
	const grid = candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS);
	const expected =
		DEFAULT_PLACEMENT_PARAMS.kValues.length *
		DEFAULT_PLACEMENT_PARAMS.rotationCount *
		DEFAULT_PLACEMENT_PARAMS.radiusFractions.length;
	assert.equal(expected, 120);
	assert.equal(grid.length, expected);
});

test('candidatePlacements radiusM = targetM × fraction', () => {
	const grid = candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS);
	for (const c of grid) {
		const fraction = c.radiusM / 5000;
		assert.ok(
			DEFAULT_PLACEMENT_PARAMS.radiusFractions.some((f) => Math.abs(f - fraction) < 1e-9),
			`radius fraction ${fraction} is one of the params`,
		);
	}
	assert.ok(grid.some((c) => Math.abs(c.radiusM - 5000 * 0.12) < 1e-9));
	assert.ok(grid.some((c) => Math.abs(c.radiusM - 5000 * 0.16) < 1e-9));
});

test('candidatePlacements rotations are evenly spaced over [0, 360)', () => {
	const grid = candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS);
	const rotations = [...new Set(grid.map((c) => c.rotationDeg))].sort((a, b) => a - b);
	assert.equal(rotations.length, DEFAULT_PLACEMENT_PARAMS.rotationCount);
	assert.equal(rotations[0], 0);
	assert.equal(rotations[1], 30);
	assert.ok(rotations[rotations.length - 1] < 360);
});

test('candidatePlacements covers every k and emits k as the outer loop', () => {
	const grid = candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS);
	assert.deepEqual(
		[...new Set(grid.map((c) => c.k))].sort((a, b) => a - b),
		[3, 4],
	);
	// k is the outer loop: the first block is all k=3, the last is all k=4.
	const perK = DEFAULT_PLACEMENT_PARAMS.rotationCount * DEFAULT_PLACEMENT_PARAMS.radiusFractions.length;
	assert.ok(grid.slice(0, perK).every((c) => c.k === 3));
	assert.ok(grid.slice(perK).every((c) => c.k === 4));
});

test('viaPoints is deterministic', () => {
	const start = { lat: 38.88, lng: -77.1 };
	assert.deepEqual(viaPoints(start, 600, 3, 45), viaPoints(start, 600, 3, 45));
});

test('candidatePlacements is deterministic', () => {
	assert.deepEqual(
		candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS),
		candidatePlacements(5000, DEFAULT_PLACEMENT_PARAMS),
	);
});

test('candidatePlacements honours custom params', () => {
	const params: PlacementParams = {
		kValues: [3],
		rotationCount: 4,
		radiusFractions: [0.1, 0.2],
		spurFloor: 0.12,
		maxSnapM: 250,
		bandFraction: 0.15,
	};
	const grid = candidatePlacements(1000, params);
	assert.equal(grid.length, 1 * 4 * 2);
	assert.deepEqual(
		[...new Set(grid.map((c) => c.rotationDeg))].sort((a, b) => a - b),
		[0, 90, 180, 270],
	);
});
