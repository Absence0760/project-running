import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import {
	movingTimeSeconds,
	computeRealSplits,
	haversineMetres,
	SPLIT_TAIL_MIN_M,
} from './run_stats';
import { stripComments } from '../core/strip_comments';
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

test('the run-detail page reads its vert through the one elevation rule', () => {
	// Source-level, because the page is a `.svelte` file and cannot be executed
	// here. `run_stats` used to export a rounded adapter over
	// `computeElevationGain`, and before that its own ungated sum — which
	// reported 143 m of climb on a flat half-hour and made a run's vert change
	// the moment the runner tapped "save as route" (decisions § 981). With the
	// adapter gone the page holds the only remaining place a second rule could
	// reappear (decisions § 1004).
	const page = stripComments(
		readFileSync(resolve(import.meta.dirname, '../../routes/runs/[id]/+page.svelte'), 'utf-8'),
	);
	const derived = page
		.split('\n')
		.find((l) => l.includes('realElevationGain') && l.includes('$derived'));
	assert.ok(derived, 'the run-detail page no longer derives realElevationGain');
	assert.match(
		derived,
		/computeElevationGain\(/,
		'the run-detail page must take its elevation gain from computeElevationGain, ' +
			'which is the same rule the route summary and the Dart twin use.',
	);
	assert.match(
		page,
		/import \{[^}]*\bcomputeElevationGain\b[^}]*\} from '\$lib\/routes\/route_simplify'/,
		'imported from the module that owns the rule, not re-exported through another',
	);
	assert.doesNotMatch(
		page,
		/elevationGainMetres/,
		'the rounded adapter was deleted — the page calls the rule directly',
	);
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

test('computeRealSplits — first split is timed even when track[0] lacks a timestamp', () => {
	// First GPS fix lands before the clock is stamped: point 0 has no ts,
	// every later point is timed. The first split must still report the real
	// pace, not 0:00 from a NaN start anchor.
	const pts = track(10, 2, 301);
	delete pts[0].ts;
	const splits = computeRealSplits(pts);
	assert.equal(splits.length, 3);
	assert.ok(splits[0].pace_s > 0, `first split pace was ${splits[0].pace_s}`);
	assert.ok(Math.abs(splits[0].pace_s - 200) <= 4, `first split pace ${splits[0].pace_s} not near 200`);
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

test('computeRealSplits — mile tick produces mile-long splits, pace stays sec/km', () => {
	// ~1610 m at 5 m/s. A km tick gives one full km + a ~600 m tail; a
	// mile tick (1609.344 m) gives a single ~1609 m split with no tail.
	const pts = track(10, 2, 162);
	const kmSplits = computeRealSplits(pts);
	const miSplits = computeRealSplits(pts, 1609.344);
	assert.equal(kmSplits.length, 2);
	assert.equal(miSplits.length, 1);
	assert.ok(Math.abs(miSplits[0].distance_m - 1609) <= 20, `dist ${miSplits[0].distance_m}`);
	// pace_s is canonical seconds-per-km regardless of tick length — the
	// caller converts to /mi for display. 5 m/s → ~200 s/km either way.
	assert.ok(Math.abs(miSplits[0].pace_s - 200) <= 2, `pace ${miSplits[0].pace_s}`);
});

test('computeRealSplits — a multi-boundary GPS gap yields correctly-sized splits, not slivers', () => {
	// A sparse / imported track: dense to 500 m, then a single 2500 m
	// fix-to-fix gap (a tunnel, a canyon/forest signal loss, or a downsampled
	// Strava/Garmin import), then on to 4000 m. That one gap segment straddles
	// the 1 km, 2 km and 3 km boundaries. Before the fix this emitted one
	// oversized "km 1" (~3000 m) followed by zero-distance slivers for km 2 and
	// km 3; now it must be four ~1 km splits, each timed by interpolation.
	const deg = (m: number) => m / 111320;
	const base = Date.parse('2026-04-01T07:00:00Z');
	const at = (m: number, s: number): TrackPoint => ({
		lat: deg(m),
		lng: 0,
		ts: new Date(base + s * 1000).toISOString(),
	});
	// Even 300 s/km throughout (including across the gap), so every correct
	// split is ~1000 m at ~300 s/km.
	const pts: TrackPoint[] = [at(0, 0), at(500, 150), at(3000, 900), at(4000, 1200)];
	const splits = computeRealSplits(pts, 1000);
	assert.equal(splits.length, 4, `expected 4 splits, got ${splits.length}`);
	assert.deepEqual(
		splits.map((s) => s.km),
		[1, 2, 3, 4]
	);
	for (const s of splits) {
		assert.ok(
			s.distance_m >= 990 && s.distance_m <= 1010,
			`split ${s.km} is a sliver / oversized: ${s.distance_m} m`
		);
		assert.ok(Math.abs(s.pace_s - 300) <= 2, `split ${s.km} pace ${s.pace_s} not ~300`);
	}
});

test('computeRealSplits — track without elevation leaves elevation_m null', () => {
	const pts = track(10, 2, 105);
	const splits = computeRealSplits(pts);
	for (const s of splits) {
		assert.equal(s.elevation_m, null);
	}
});

test('haversineMetres clamps instead of returning NaN near antipodal', () => {
	// Mirror of the Dart twin. Rounding pushes `a` a hair above 1 for a
	// near-antipodal pair, and the unclamped atan2 form then returns NaN, which
	// propagates silently through moving time, splits and segment distances.
	const d = haversineMetres(-87.5, 0, 87.5, 180);
	assert.ok(Number.isFinite(d));
	assert.ok(Math.abs(d - 20015086.796) < 1);
});

test('haversineMetres agrees with the Dart twin on ordinary distances', () => {
	const d = haversineMetres(51.5, -0.1, 51.6, -0.2);
	assert.ok(Math.abs(d - 13093.993) < 0.01);
});

test('computeRealSplits — the dropped tail is bounded by the named floor', () => {
	// The split table's own total is allowed to fall short of the run's headline
	// distance, and by how much is the whole content of the rule: a wrong pace
	// on a named row is worse than a total under one percent light. Anchored to
	// the constant rather than to 50 so the bound and the rule move together.
	for (const tail of [0, 10, 30, SPLIT_TAIL_MIN_M, SPLIT_TAIL_MIN_M + 40]) {
		const pts = track(10, 2, 101 + tail / 10);
		const splits = computeRealSplits(pts);
		const summed = splits.reduce((a, sp) => a + sp.distance_m, 0);
		const covered = haversineMetres(
			pts[0].lat,
			pts[0].lng,
			pts[pts.length - 1].lat,
			pts[pts.length - 1].lng,
		);
		assert.ok(
			covered - summed <= SPLIT_TAIL_MIN_M + 1,
			`a ${tail} m tail left ${covered - summed} m unaccounted for`,
		);
		assert.ok(summed <= covered + 1, 'the splits may never total more than the track');
	}
});
