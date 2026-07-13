import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	haversineMetres,
	buildTrackIndex,
	nearestIndex,
} from './nearest_track_point';

type Coord = [number, number];

function bruteForce(coords: Coord[], lng: number, lat: number): number {
	let bestIdx = 0;
	let bestD = Infinity;
	for (let i = 0; i < coords.length; i++) {
		const d = haversineMetres([lng, lat], coords[i]);
		if (d < bestD) {
			bestD = d;
			bestIdx = i;
		}
	}
	return bestIdx;
}

// Deterministic LCG so the fuzz cases are reproducible.
function rng(seed: number): () => number {
	let s = seed >>> 0;
	return () => {
		s = (s * 1664525 + 1013904223) >>> 0;
		return s / 0x100000000;
	};
}

test('haversineMetres matches a known distance', () => {
	// ~1 degree of latitude ≈ 111.2 km.
	const d = haversineMetres([0, 0], [0, 1]);
	assert.ok(Math.abs(d - 111195) < 200, `got ${d}`);
});

test('empty and tiny tracks are handled', () => {
	assert.equal(nearestIndex(buildTrackIndex([]), 0, 0), 0);
	const one: Coord[] = [[10, 20]];
	assert.equal(nearestIndex(buildTrackIndex(one), 11, 21), 0);
	const two: Coord[] = [
		[0, 0],
		[0, 1],
	];
	assert.equal(nearestIndex(buildTrackIndex(two), 0, 0.9), 1);
	assert.equal(nearestIndex(buildTrackIndex(two), 0, 0.1), 0);
});

test('small track uses the linear path and matches brute force', () => {
	const coords: Coord[] = [];
	for (let i = 0; i < 500; i++) coords.push([-111 + i * 0.001, 38 + Math.sin(i / 10) * 0.01]);
	const idx = buildTrackIndex(coords);
	assert.equal(idx.grid, null); // below LINEAR_SCAN_MAX
	const r = rng(1);
	for (let k = 0; k < 300; k++) {
		const lng = -111.1 + r() * 0.7;
		const lat = 37.99 + r() * 0.03;
		assert.equal(nearestIndex(idx, lng, lat), bruteForce(coords, lng, lat));
	}
});

test('ultra-scale track uses the grid and stays exact vs brute force', () => {
	// 40k points (well past LINEAR_SCAN_MAX) tracing a serpentine path.
	const coords: Coord[] = [];
	for (let i = 0; i < 40000; i++) {
		const t = i / 40000;
		coords.push([-111.5 + t * 1.0, 38 + Math.sin(t * 40) * 0.15]);
	}
	const idx = buildTrackIndex(coords);
	assert.notEqual(idx.grid, null);
	const r = rng(7);
	for (let k = 0; k < 500; k++) {
		const lng = -111.6 + r() * 1.2;
		const lat = 37.7 + r() * 0.6;
		assert.equal(
			nearestIndex(idx, lng, lat),
			bruteForce(coords, lng, lat),
			`mismatch at (${lng},${lat})`
		);
	}
});

test('self-intersecting looped track stays exact (where stride/refine would fail)', () => {
	// Two overlapping loops + an out-and-back so distinct index ranges
	// sit spatially adjacent — the case a coarsen-then-refine scan
	// misses. >LINEAR_SCAN_MAX so the grid path is exercised.
	const coords: Coord[] = [];
	const n = 25000;
	for (let i = 0; i < n; i++) {
		const a = (i / n) * Math.PI * 6; // three loops
		coords.push([-110 + Math.cos(a) * 0.2, 40 + Math.sin(a) * 0.2]);
	}
	const idx = buildTrackIndex(coords);
	assert.notEqual(idx.grid, null);
	const r = rng(42);
	for (let k = 0; k < 500; k++) {
		const lng = -110.3 + r() * 0.6;
		const lat = 39.7 + r() * 0.6;
		assert.equal(nearestIndex(idx, lng, lat), bruteForce(coords, lng, lat));
	}
});

test('taps far outside the bbox still return the brute-force nearest', () => {
	const coords: Coord[] = [];
	for (let i = 0; i < 30000; i++) coords.push([-111 + i * 0.00003, 38 + i * 0.00002]);
	const idx = buildTrackIndex(coords);
	assert.notEqual(idx.grid, null);
	const far: Coord[] = [
		[-200, 80],
		[100, -80],
		[-111.5, 37],
		[0, 0],
	];
	for (const [lng, lat] of far) {
		assert.equal(nearestIndex(idx, lng, lat), bruteForce(coords, lng, lat), `far tap ${lng},${lat}`);
	}
});

test('degenerate collinear track falls back cleanly', () => {
	// All-same latitude, many points — the lat axis is zero-span.
	const coords: Coord[] = [];
	for (let i = 0; i < 30000; i++) coords.push([-111 + i * 0.00002, 40]);
	const idx = buildTrackIndex(coords);
	const r = rng(3);
	for (let k = 0; k < 200; k++) {
		const lng = -111.1 + r() * 0.8;
		const lat = 39.99 + r() * 0.02;
		assert.equal(nearestIndex(idx, lng, lat), bruteForce(coords, lng, lat));
	}
});
