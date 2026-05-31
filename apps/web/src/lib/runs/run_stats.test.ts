import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	movingTimeSeconds,
	elevationGainMetres,
	computeRealSplits,
} from './run_stats';
import type { TrackPoint } from '../types';

// Synthetic track helper: emits a meridian-aligned sequence at a chosen
// pace + cadence so haversine matches `i * stepM` to within ~0.5 m.
const lat = 0;
function track(stepM: number, intervalS: number, n: number, options: {
	startTs?: string;
	startEle?: number;
	eleStep?: number;
} = {}): TrackPoint[] {
	const startTs = options.startTs ?? '2026-04-01T07:00:00Z';
	const startEle = options.startEle;
	const eleStep = options.eleStep ?? 0;
	const t0 = Date.parse(startTs);
	const metresPerDegLng = 111_320;
	const out: TrackPoint[] = [];
	for (let i = 0; i < n; i++) {
		const p: TrackPoint = {
			lat,
			lng: (i * stepM) / metresPerDegLng,
			ts: new Date(t0 + i * intervalS * 1000).toISOString(),
		};
		if (startEle != null) p.ele = startEle + i * eleStep;
		out.push(p);
	}
	return out;
}

test('movingTimeSeconds — empty / single-point track is zero', () => {
	assert.equal(movingTimeSeconds(null), 0);
	assert.equal(movingTimeSeconds(undefined), 0);
	assert.equal(movingTimeSeconds([]), 0);
	assert.equal(movingTimeSeconds([{ lat: 0, lng: 0, ts: '2026-04-01T07:00:00Z' }]), 0);
});

test('movingTimeSeconds — counts segments at or above threshold', () => {
	// 5 m every 1 s = 5 m/s — far above the 0.5 m/s default.
	const t = track(5, 1, 6);
	// 5 segments × 1 s each = 5 s.
	assert.equal(movingTimeSeconds(t), 5);
});

test('movingTimeSeconds — drops sub-threshold (stopped) segments', () => {
	// 0.1 m every 1 s = 0.1 m/s — well below 0.5 m/s.
	const stopped = track(0.1, 1, 11);
	assert.equal(movingTimeSeconds(stopped), 0);
});

test('movingTimeSeconds — mixed running + long stop counts only the running', () => {
	// First three points: 5 m/s for 2 s. Then a 60 s pause at the same place.
	// Then four more points at 5 m/s for 3 s. Total moving = 2 + 3 = 5 s.
	const pts: TrackPoint[] = [
		{ lat: 0, lng: 0, ts: '2026-04-01T07:00:00Z' },
		{ lat: 0, lng: 5 / 111_320, ts: '2026-04-01T07:00:01Z' },
		{ lat: 0, lng: 10 / 111_320, ts: '2026-04-01T07:00:02Z' },
		{ lat: 0, lng: 10 / 111_320, ts: '2026-04-01T07:01:02Z' }, // 60 s stop
		{ lat: 0, lng: 15 / 111_320, ts: '2026-04-01T07:01:03Z' },
		{ lat: 0, lng: 20 / 111_320, ts: '2026-04-01T07:01:04Z' },
		{ lat: 0, lng: 25 / 111_320, ts: '2026-04-01T07:01:05Z' },
	];
	assert.equal(movingTimeSeconds(pts), 5);
});

test('movingTimeSeconds — custom minSpeedMps overrides the default', () => {
	// 0.6 m/s — below a 1 m/s threshold but above 0.5 m/s default.
	const t = track(0.6, 1, 11);
	assert.equal(movingTimeSeconds(t), 10); // counts at default
	assert.equal(movingTimeSeconds(t, 1.0), 0); // excluded at 1 m/s
});

test('movingTimeSeconds — same-timestamp pairs (dt == 0) are skipped', () => {
	const ts = '2026-04-01T07:00:00Z';
	const pts: TrackPoint[] = [
		{ lat: 0, lng: 0, ts },
		{ lat: 0, lng: 1 / 111_320, ts }, // same timestamp
		{ lat: 0, lng: 2 / 111_320, ts: '2026-04-01T07:00:01Z' },
	];
	// First pair (dt=0) skipped, second pair (1 m / 1 s = 1 m/s) counted.
	assert.equal(movingTimeSeconds(pts), 1);
});

test('movingTimeSeconds — points without ts are skipped', () => {
	const pts: TrackPoint[] = [
		{ lat: 0, lng: 0, ts: '2026-04-01T07:00:00Z' },
		{ lat: 0, lng: 5 / 111_320 }, // missing ts
		{ lat: 0, lng: 10 / 111_320, ts: '2026-04-01T07:00:02Z' },
	];
	// First pair has no ts on b → skip. Second pair has no ts on a → skip.
	assert.equal(movingTimeSeconds(pts), 0);
});

test('elevationGainMetres — sums positive deltas only', () => {
	const pts: TrackPoint[] = [
		{ lat: 0, lng: 0, ele: 100 },
		{ lat: 0, lng: 0.001, ele: 110 }, // +10
		{ lat: 0, lng: 0.002, ele: 105 }, // -5 ignored
		{ lat: 0, lng: 0.003, ele: 130 }, // +25
	];
	assert.equal(elevationGainMetres(pts), 35);
});

test('elevationGainMetres — null / undefined elevations skipped', () => {
	const pts: TrackPoint[] = [
		{ lat: 0, lng: 0, ele: 100 },
		{ lat: 0, lng: 0.001 }, // missing ele
		{ lat: 0, lng: 0.002, ele: 110 },
	];
	assert.equal(elevationGainMetres(pts), 0);
});

test('elevationGainMetres — empty / single-point input returns 0', () => {
	assert.equal(elevationGainMetres([]), 0);
	assert.equal(elevationGainMetres(null), 0);
	assert.equal(elevationGainMetres(undefined), 0);
	assert.equal(elevationGainMetres([{ lat: 0, lng: 0, ele: 100 }]), 0);
});

test('computeRealSplits — short track returns no splits', () => {
	assert.deepEqual(computeRealSplits([]), []);
	assert.deepEqual(computeRealSplits([{ lat: 0, lng: 0, ts: '2026-04-01T07:00:00Z' }]), []);
});

test('computeRealSplits — track without timestamps yields no splits', () => {
	const pts: TrackPoint[] = Array.from({ length: 50 }, (_, i) => ({
		lat: 0,
		lng: (i * 100) / 111_320,
	}));
	assert.deepEqual(computeRealSplits(pts), []);
});

test('computeRealSplits — even-paced 3 km run produces three full splits at the right pace', () => {
	// 3000 m at 5 m/s → 600 s. Sample every 10 m (one fix per 2 s).
	const pts = track(10, 2, 301);
	const splits = computeRealSplits(pts);
	// Three full kilometres + a final partial under 50 m → no trailing entry.
	assert.equal(splits.length, 3);
	for (const s of splits) {
		// Pace should be ~200 s/km (5 m/s × 1 km = 200 s/km). Allow ±2 s
		// for the haversine vs flat-distance approximation.
		assert.ok(Math.abs(s.pace_s - 200) <= 2, `pace ${s.pace_s} not near 200`);
		// Each split's distance is ~1000 m. The km boundary fires on the
		// first step that crosses 1000 m of cumDist, so split 1 can
		// overshoot by up to one sample (~10 m); subsequent splits take
		// the overshoot as their new starting cumDist, so the slack is
		// roughly the same in either direction.
		assert.ok(Math.abs(s.distance_m - 1000) <= 15, `dist ${s.distance_m}`);
	}
	assert.deepEqual(
		splits.map((s) => s.km),
		[1, 2, 3],
	);
});

test('computeRealSplits — final partial split is emitted when remainder > 50 m', () => {
	// 1500 m → one full km plus a 500 m tail.
	const pts = track(10, 2, 151);
	const splits = computeRealSplits(pts);
	assert.equal(splits.length, 2);
	assert.equal(splits[0].km, 1);
	assert.equal(splits[1].km, 2);
	assert.ok(splits[1].distance_m >= 450 && splits[1].distance_m <= 550);
});

test('computeRealSplits — final partial under 50 m is dropped', () => {
	// 1030 m → one full km plus a 30 m tail (below 50 m threshold).
	const pts = track(10, 2, 104);
	const splits = computeRealSplits(pts);
	assert.equal(splits.length, 1);
	assert.equal(splits[0].km, 1);
});

test('computeRealSplits — elevation gain or loss carried per split', () => {
	// Climb 10 m per fix over 1100 m → +1100 m of elevation across the run.
	// First split should report ~+1000 m of net elevation (start vs end of km 1).
	const pts = track(10, 2, 110, { startEle: 100, eleStep: 10 });
	const splits = computeRealSplits(pts);
	assert.ok(splits.length >= 1);
	// Net = endEle - startEle of the split. Each fix climbs 10 m, ~100
	// fixes per km → ~+1000 m net.
	assert.ok(splits[0].elevation_m != null);
	assert.ok(Math.abs(splits[0].elevation_m! - 1000) <= 20);
});

test('computeRealSplits — track without elevation leaves elevation_m null', () => {
	const pts = track(10, 2, 105);
	const splits = computeRealSplits(pts);
	for (const s of splits) {
		assert.equal(s.elevation_m, null);
	}
});
