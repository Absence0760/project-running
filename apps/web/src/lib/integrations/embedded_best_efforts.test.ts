// Embedded best-effort computation for imported runs. Pre-fix no importer
// wrote metadata.fastest_{5k,10k,...}_s, so a fast sub-distance inside a long
// imported run never reached personal_records (the 20260529000002 trigger
// reads those keys). Keep in lockstep with Dart's fastestWindowOf
// (apps/mobile_android/lib/run_stats.dart) + the Deno twin in
// apps/backend/supabase/functions/_shared/strava.ts.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { TrackPoint } from '../types';
import { EMBEDDED_BEST_DISTANCES, computeEmbeddedBests, fastestWindowSeconds } from './garmin-fit';

const M_PER_DEG = 6371000 * (Math.PI / 180);

/// Even track at the equator: `segments` steps of `stepM` metres, `stepS`
/// seconds apart.
function evenTrack(segments: number, stepM: number, stepS: number, startIso = '2026-01-01T09:00:00Z'): TrackPoint[] {
	const stepDeg = stepM / M_PER_DEG;
	const startMs = Date.parse(startIso);
	const out: TrackPoint[] = [];
	for (let i = 0; i <= segments; i++) {
		out.push({ lat: 0, lng: i * stepDeg, ts: new Date(startMs + i * stepS * 1000).toISOString() });
	}
	return out;
}

test('EMBEDDED_BEST_DISTANCES matches the migration reader + Dart keys', () => {
	assert.deepEqual(EMBEDDED_BEST_DISTANCES, [
		['fastest_5k_s', 5000],
		['fastest_10k_s', 10000],
		['fastest_half_marathon_s', 21097.5],
		['fastest_marathon_s', 42195],
	]);
});

test('computeEmbeddedBests — fewer than 3 points writes nothing', () => {
	assert.deepEqual(computeEmbeddedBests(evenTrack(1, 100, 30)), {});
});

test('computeEmbeddedBests — a sub-5km track has no bests', () => {
	assert.deepEqual(computeEmbeddedBests(evenTrack(40, 100, 30)), {}); // 4 km
});

test('computeEmbeddedBests — even 6 km run yields ~total-time 5k, no 10k', () => {
	const bests = computeEmbeddedBests(evenTrack(60, 100, 30)); // 6 km @ 5:00/km
	assert.ok(bests.fastest_5k_s >= 1495 && bests.fastest_5k_s <= 1505, `got ${bests.fastest_5k_s}`);
	assert.equal(bests.fastest_10k_s, undefined);
});

test('computeEmbeddedBests — a fast 5k inside a long run is detected', () => {
	// First 5 km fast (100 m / 20 s), last 5 km slow (100 m / 40 s).
	const stepDeg = 100 / M_PER_DEG;
	const startMs = Date.parse('2026-01-01T09:00:00Z');
	const track: TrackPoint[] = [{ lat: 0, lng: 0, ts: new Date(startMs).toISOString() }];
	let t = startMs;
	for (let i = 1; i <= 100; i++) {
		t += (i <= 50 ? 20 : 40) * 1000;
		track.push({ lat: 0, lng: i * stepDeg, ts: new Date(t).toISOString() });
	}
	const bests = computeEmbeddedBests(track);
	// Embedded fast 5k (~1000 s) beats the whole-run-scaled pace (1500 s).
	assert.ok(bests.fastest_5k_s >= 995 && bests.fastest_5k_s <= 1005, `got ${bests.fastest_5k_s}`);
	assert.ok(bests.fastest_10k_s >= 2990 && bests.fastest_10k_s <= 3010, `got ${bests.fastest_10k_s}`);
	assert.equal(bests.fastest_half_marathon_s, undefined);
});

test('computeEmbeddedBests — a track with no timestamps writes nothing (no fake bests)', () => {
	const stepDeg = 100 / M_PER_DEG;
	const track: TrackPoint[] = Array.from({ length: 61 }, (_, i) => ({ lat: 0, lng: i * stepDeg }));
	assert.deepEqual(computeEmbeddedBests(track), {});
});

test('fastestWindowSeconds — null when the track is shorter than the window', () => {
	assert.equal(fastestWindowSeconds(evenTrack(10, 100, 30), 5000), null);
});
