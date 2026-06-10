import { test } from 'node:test';
import assert from 'node:assert/strict';

import { pickBestPolygonLoop, type PolygonCandidate } from './loop_select';
import { areaEfficiency } from './select';

const LAT0 = 40;
const M_PER_DEG_LAT = 111320;
const M_PER_DEG_LNG = 111320 * Math.cos((LAT0 * Math.PI) / 180);

/// A closed square of the given side in metres, anchored at (lng0, LAT0).
/// areaEfficiency ≈ π/4 ≈ 0.785 (a round loop), perimeter ≈ 4·side.
function square(sideM: number, lng0 = -77): [number, number][] {
	const dLng = sideM / M_PER_DEG_LNG;
	const dLat = sideM / M_PER_DEG_LAT;
	return [
		[lng0, LAT0],
		[lng0 + dLng, LAT0],
		[lng0 + dLng, LAT0 + dLat],
		[lng0, LAT0 + dLat],
		[lng0, LAT0],
	];
}

/// A collinear out-and-back of total length lenM — zero enclosed area, so
/// areaEfficiency is 0 (the loop-poor / spur case).
function spur(lenM: number, lng0 = -77): [number, number][] {
	const half = lenM / 2;
	const dLng = half / M_PER_DEG_LNG;
	return [
		[lng0, LAT0],
		[lng0 + dLng, LAT0],
		[lng0, LAT0],
	];
}

const OPTS = { spurFloor: 0.12, maxSnapM: 250, bandFraction: 0.15 };

function squareCandidate(sideM: number, maxSnapM = 0, lng0 = -77): PolygonCandidate {
	return { coordinates: square(sideM, lng0), distanceM: 4 * sideM, maxSnapM };
}

test('a spur (zero-area out-and-back) is rejected by the spur floor', () => {
	const cand: PolygonCandidate = {
		coordinates: spur(5000),
		distanceM: 5000,
		maxSnapM: 0,
	};
	assert.ok(areaEfficiency(cand) < OPTS.spurFloor);
	assert.equal(pickBestPolygonLoop([cand], 5000, OPTS), null);
});

test('a candidate whose via-point snapped too far is rejected', () => {
	// On-target, perfectly round, but snapped 300 m > maxSnapM (250).
	const cand = squareCandidate(1250, 300);
	assert.ok(areaEfficiency(cand) >= OPTS.spurFloor);
	assert.equal(pickBestPolygonLoop([cand], 5000, OPTS), null);
});

test('in-band: the roundest loop wins', () => {
	const target = 5000;
	// Both within ±15% of 5 km. The square is round (~0.785); the rectangle is
	// thinner so its areaEfficiency is lower — the square must win even though
	// the rectangle is marginally closer on distance.
	const round = squareCandidate(1250); // 5000 m exactly
	const dLng = 2200 / M_PER_DEG_LNG;
	const dLat = 300 / M_PER_DEG_LAT;
	const thin: PolygonCandidate = {
		coordinates: [
			[-77, LAT0],
			[-77 + dLng, LAT0],
			[-77 + dLng, LAT0 + dLat],
			[-77, LAT0 + dLat],
			[-77, LAT0],
		],
		distanceM: 5000, // 2·(2200+300)
		maxSnapM: 0,
	};
	assert.ok(areaEfficiency(thin) >= OPTS.spurFloor);
	assert.ok(areaEfficiency(round) > areaEfficiency(thin));
	const best = pickBestPolygonLoop([thin, round], target, OPTS);
	assert.equal(best, round);
});

test('out-of-band: the closest-to-target loop wins even if less round', () => {
	const target = 5000;
	// Both out of band (±15% → [4250, 5750]). The 7 km loop is rounder (a true
	// square) but the 6 km loop is closer to target, so closeness wins.
	const closer = squareCandidate(1500); // 6000 m, |Δ| = 1000
	const farther = squareCandidate(1750); // 7000 m, |Δ| = 2000
	assert.ok(Math.abs(closer.distanceM - target) > OPTS.bandFraction * target);
	assert.ok(Math.abs(farther.distanceM - target) > OPTS.bandFraction * target);
	const best = pickBestPolygonLoop([farther, closer], target, OPTS);
	assert.equal(best, closer);
});

test('all spurs → null (loop-poor location)', () => {
	const cands: PolygonCandidate[] = [
		{ coordinates: spur(5000), distanceM: 5000, maxSnapM: 0 },
		{ coordinates: spur(4000), distanceM: 4000, maxSnapM: 0 },
		{ coordinates: spur(6000), distanceM: 6000, maxSnapM: 0 },
	];
	assert.equal(pickBestPolygonLoop(cands, 5000, OPTS), null);
});
