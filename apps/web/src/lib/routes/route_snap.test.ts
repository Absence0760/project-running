import assert from 'node:assert/strict';
import { test } from 'node:test';

import { snapToPolyline } from './route_snap';

// A roughly 1 km west→east segment at the equator-ish latitude 51.5, plus a
// second leg turning north. Distances use haversine so the exact metres are
// approximate; assertions use tolerances.
const LINE: [number, number][] = [
	[-0.12, 51.5],
	[-0.1, 51.5], // ~1.39 km east
	[-0.1, 51.51] // ~1.11 km north
];

test('returns null when the polyline has fewer than two points', () => {
	assert.equal(snapToPolyline({ lng: 0, lat: 0 }, []), null);
	assert.equal(snapToPolyline({ lng: 0, lat: 0 }, [[-0.12, 51.5]]), null);
});

test('returns null for a non-finite input point', () => {
	assert.equal(snapToPolyline({ lng: NaN, lat: 51.5 }, LINE), null);
	assert.equal(snapToPolyline({ lng: -0.11, lat: Infinity }, LINE), null);
});

test('snaps a point above the first segment straight down onto the line', () => {
	// A point north of the horizontal first leg snaps to the same lng, on
	// the line's latitude.
	const r = snapToPolyline({ lng: -0.11, lat: 51.502 }, LINE);
	assert.ok(r);
	assert.equal(r!.segmentIndex, 0);
	assert.ok(Math.abs(r!.lng - -0.11) < 1e-6, `lng ${r!.lng}`);
	assert.ok(Math.abs(r!.lat - 51.5) < 1e-6, `lat ${r!.lat}`);
	// t is the fraction along the first leg: -0.11 is halfway between
	// -0.12 and -0.10.
	assert.ok(Math.abs(r!.t - 0.5) < 0.01, `t ${r!.t}`);
	// Offset ≈ 0.002° latitude ≈ 222 m.
	assert.ok(r!.offsetM > 180 && r!.offsetM < 260, `offset ${r!.offsetM}`);
});

test('clamps to the start vertex for a point before the line begins', () => {
	const r = snapToPolyline({ lng: -0.13, lat: 51.5 }, LINE);
	assert.ok(r);
	assert.equal(r!.segmentIndex, 0);
	assert.equal(r!.t, 0);
	assert.ok(Math.abs(r!.lng - -0.12) < 1e-9);
	assert.ok(Math.abs(r!.alongM) < 1e-6, `alongM ${r!.alongM}`);
});

test('clamps to the end vertex for a point past the line end', () => {
	const r = snapToPolyline({ lng: -0.1, lat: 51.52 }, LINE);
	assert.ok(r);
	assert.equal(r!.segmentIndex, 1);
	assert.equal(r!.t, 1);
	assert.ok(Math.abs(r!.lat - 51.51) < 1e-9);
});

test('picks the nearer segment when two are in range', () => {
	// A point near the corner but closer to the vertical second leg.
	const r = snapToPolyline({ lng: -0.099, lat: 51.505 }, LINE);
	assert.ok(r);
	assert.equal(r!.segmentIndex, 1);
});

test('alongM accumulates across segments', () => {
	// A point projecting onto the middle of the second (vertical) leg: its
	// along-distance is the whole first leg plus half the second.
	const r = snapToPolyline({ lng: -0.1, lat: 51.505 }, LINE);
	assert.ok(r);
	assert.equal(r!.segmentIndex, 1);
	assert.ok(Math.abs(r!.t - 0.5) < 0.02, `t ${r!.t}`);
	// First leg ~1.39 km + half of second leg ~0.55 km ≈ 1.9–2.0 km.
	assert.ok(r!.alongM > 1800 && r!.alongM < 2050, `alongM ${r!.alongM}`);
});

test('a point already on the line snaps to itself with ~zero offset', () => {
	const r = snapToPolyline({ lng: -0.11, lat: 51.5 }, LINE);
	assert.ok(r);
	assert.ok(r!.offsetM < 1, `offset ${r!.offsetM}`);
	assert.ok(Math.abs(r!.lat - 51.5) < 1e-6);
});

test('tolerates duplicate consecutive vertices without dividing by zero', () => {
	const dup: [number, number][] = [
		[-0.12, 51.5],
		[-0.12, 51.5],
		[-0.1, 51.5]
	];
	const r = snapToPolyline({ lng: -0.11, lat: 51.501 }, dup);
	assert.ok(r);
	assert.ok(Number.isFinite(r!.alongM));
	assert.ok(Number.isFinite(r!.t));
});

test('snapped point is bit-stable for the same input (idempotent)', () => {
	const a = snapToPolyline({ lng: -0.105, lat: 51.503 }, LINE);
	const b = snapToPolyline({ lng: -0.105, lat: 51.503 }, LINE);
	assert.deepEqual(a, b);
});
