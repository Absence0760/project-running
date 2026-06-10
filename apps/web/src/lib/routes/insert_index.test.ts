import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { nearestInsertIndex } from './insert_index';

// L-shaped route used across the segment-selection cases:
//   A(0,0) ──long── B(0, 0.20) ─short─ C(0, 0.22)
// A→B spans 0.20° of longitude (~22 km at the equator); B→C only 0.02°.
const A = { lat: 0, lng: 0 };
const B = { lat: 0, lng: 0.2 };
const C = { lat: 0, lng: 0.22 };

test('fewer than two waypoints → append (returns length)', () => {
	assert.equal(nearestInsertIndex([], { lat: 0, lng: 0 }), 0);
	assert.equal(nearestInsertIndex([A], { lat: 1, lng: 1 }), 1);
});

test('click on the first segment inserts at index 1', () => {
	// Dead-centre of A→B.
	assert.equal(nearestInsertIndex([A, B, C], { lat: 0, lng: 0.1 }), 1);
});

test('click on the short last segment inserts at index 2', () => {
	// Between B and C.
	assert.equal(nearestInsertIndex([A, B, C], { lat: 0, lng: 0.21 }), 2);
});

test('click near the FAR end of a long segment inserts into THAT segment, not the short neighbour', () => {
	// THE REGRESSION: P sits right on A→B, just shy of B (lng 0.19).
	// True point-to-segment distance to A→B is ~0 (P is on the line),
	// so the correct insert index is 1. The old midpoint heuristic
	// measured distance to each segment's MIDPOINT — midpoint(A,B) is
	// at lng 0.10 (~10 km away) while midpoint(B,C) is at lng 0.21
	// (~1 km away), so it wrongly chose the B→C segment (index 2).
	const p = { lat: 0, lng: 0.19 };
	assert.equal(nearestInsertIndex([A, B, C], p), 1);

	// Prove the heuristic this replaced would have mis-picked here:
	const midpointPick = pickByMidpoint([A, B, C], p);
	assert.equal(midpointPick, 2, 'sanity: the old midpoint heuristic chose index 2');
	assert.notEqual(midpointPick, nearestInsertIndex([A, B, C], p));
});

test('a point off to the side picks the segment it is perpendicular to', () => {
	// Slightly north of the midpoint of A→B — still nearest A→B.
	assert.equal(nearestInsertIndex([A, B, C], { lat: 0.0005, lng: 0.1 }), 1);
});

test('ties resolve to the earliest segment (strict-less-than keeps the first best)', () => {
	// Equidistant from two segments of a symmetric V — the first one wins.
	const left = { lat: 0, lng: 0 };
	const apex = { lat: 0.1, lng: 0.1 };
	const right = { lat: 0, lng: 0.2 };
	// A point on the axis of symmetry, below the apex.
	const idx = nearestInsertIndex([left, apex, right], { lat: 0, lng: 0.1 });
	// Both segments are equidistant; strict `<` keeps the first (index 1).
	assert.equal(idx, 1);
});

// Reference implementation of the OLD midpoint heuristic, kept ONLY so
// the regression test can demonstrate the divergence on the failing case.
function pickByMidpoint(
	waypoints: { lat: number; lng: number }[],
	p: { lat: number; lng: number },
): number {
	if (waypoints.length < 2) return waypoints.length;
	const haversineM = (a: { lat: number; lng: number }, b: { lat: number; lng: number }) => {
		const R = 6371000;
		const toRad = (d: number) => (d * Math.PI) / 180;
		const dLat = toRad(b.lat - a.lat);
		const dLng = toRad(b.lng - a.lng);
		const s = Math.sin(dLat / 2) ** 2 + Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
		return R * 2 * Math.atan2(Math.sqrt(s), Math.sqrt(1 - s));
	};
	let bestIdx = waypoints.length;
	let bestDist = Infinity;
	for (let i = 0; i < waypoints.length - 1; i++) {
		const a = waypoints[i];
		const b = waypoints[i + 1];
		const mid = { lat: (a.lat + b.lat) / 2, lng: (a.lng + b.lng) / 2 };
		const d = haversineM(p, mid);
		if (d < bestDist) {
			bestDist = d;
			bestIdx = i + 1;
		}
	}
	return bestIdx;
}
