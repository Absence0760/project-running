import { test } from 'node:test';
import assert from 'node:assert/strict';

import { selfLoad, shouldSurfaceSelfLoad } from './self_load';
import { CHRONIC_WINDOW_WEEKS, MIN_ACTIVE_WEEKS, recentRunVolume } from './plan_ramp';
import { ACWR_ELEVATED_MAX, ACWR_LOW_MAX, ACWR_OPTIMAL_MAX, acwr } from './coach_load';

const NOW = Date.parse('2026-08-14T12:00:00Z');
const DAY_MS = 86_400_000;

/// A run `daysAgo` days back carrying `distanceM` metres.
function run(daysAgo: number, distanceM: number, activityType = 'run') {
	return {
		started_at: new Date(NOW - daysAgo * DAY_MS).toISOString(),
		distance_m: distanceM,
		activity_type: activityType,
	};
}

/// One run in each of the four chronic windows, so `activeWeeks` clears the
/// gate; the acute window's distance is the caller's to choose.
function withBase(acuteM: number, weeklyM = 40_000) {
	return [
		run(1, acuteM),
		run(8, weeklyM),
		run(15, weeklyM),
		run(22, weeklyM),
	];
}

test('a steady month sits in the optimal band', () => {
	const load = selfLoad(withBase(40_000), NOW);
	assert.equal(load.band, 'optimal');
	assert.equal(load.trend, 'steady');
	assert.ok(Math.abs(load.ratio - 1) < 1e-9);
	assert.equal(load.acuteM, 40_000);
	assert.equal(load.chronicWeeklyM, 160_000 / CHRONIC_WINDOW_WEEKS);
});

test('a spike week is graded high and reads as ramping', () => {
	const load = selfLoad(withBase(120_000, 40_000), NOW);
	// The chronic window includes the acute week: (120 + 3*40)/4 = 60 km/wk.
	assert.equal(load.chronicWeeklyM, 60_000);
	assert.ok(Math.abs(load.ratio - 2) < 1e-9);
	assert.equal(load.band, 'high');
	assert.equal(load.trend, 'ramping');
});

test('a down week is graded low and reads as tapering', () => {
	const load = selfLoad(withBase(10_000, 40_000), NOW);
	assert.equal(load.band, 'low');
	assert.equal(load.trend, 'tapering');
	assert.ok(load.ratio < ACWR_LOW_MAX);
});

test('the band edges are the coach roster edges, not a second set', () => {
	// Drive the ratio to each boundary and check the label flips where
	// coach_load says it does — the whole point of composing rather than
	// re-deriving. The chronic average includes the acute week, so hitting a
	// target ratio r against a base W needs an acute of 3rW/(4-r):
	// r = 4A/(A+3W)  =>  A = 3rW/(4 - r).
	const W = 40_000;
	const acuteFor = (r: number) => (3 * r * W) / (4 - r);
	const at = (r: number) => selfLoad(withBase(acuteFor(r), W), NOW).band;
	// Sanity-check the inversion itself before trusting the boundaries.
	assert.ok(Math.abs(selfLoad(withBase(acuteFor(1.2), W), NOW).ratio - 1.2) < 1e-9);

	// Probed either side of each edge rather than exactly on it: the acute
	// distance that lands on a boundary is irrational through this inversion,
	// so a float round-trip settles a hair below and the on-edge case tests
	// binary rounding, not the policy.
	for (const [edge, below, above] of [
		[ACWR_LOW_MAX, 'low', 'optimal'],
		[ACWR_OPTIMAL_MAX, 'optimal', 'elevated'],
		[ACWR_ELEVATED_MAX, 'elevated', 'high'],
	] as const) {
		assert.equal(at(edge - 0.01), below, `just below ${edge}`);
		assert.equal(at(edge + 0.01), above, `just above ${edge}`);
	}
});

test('a thin history is refused rather than graded', () => {
	// One big run in an otherwise empty month is exactly the shape that
	// manufactures a terrifying ratio out of a runner who has barely trained.
	const load = selfLoad([run(1, 30_000)], NOW);
	assert.equal(load.band, 'insufficient');
	assert.equal(load.ratio, 0);
	assert.equal(shouldSurfaceSelfLoad(load), false);
});

test('the active-week gate is exactly MIN_ACTIVE_WEEKS, inclusive', () => {
	const justUnder = [run(1, 40_000), run(8, 40_000)]; // 2 active weeks
	assert.equal(selfLoad(justUnder, NOW).activeWeeks, MIN_ACTIVE_WEEKS - 1);
	assert.equal(selfLoad(justUnder, NOW).band, 'insufficient');

	const justEnough = [run(1, 40_000), run(8, 40_000), run(15, 40_000)];
	assert.equal(selfLoad(justEnough, NOW).activeWeeks, MIN_ACTIVE_WEEKS);
	assert.notEqual(selfLoad(justEnough, NOW).band, 'insufficient');
});

test('no runs at all is insufficient, never a reassuring "low"', () => {
	const load = selfLoad([], NOW);
	assert.equal(load.band, 'insufficient');
	assert.equal(load.acuteM, 0);
	assert.equal(load.chronicWeeklyM, 0);
	assert.equal(shouldSurfaceSelfLoad(load), false);
});

test('a rest week on a real base is graded, not refused', () => {
	// Zero acute distance against a genuine chronic base is a meaningful
	// reading — a taper — not missing data.
	const load = selfLoad([run(8, 40_000), run(15, 40_000), run(22, 40_000)], NOW);
	assert.equal(load.acuteM, 0);
	assert.equal(load.band, 'low');
	assert.equal(load.trend, 'tapering');
	assert.equal(shouldSurfaceSelfLoad(load), true);
});

test('cycling is not running volume, on either side of the ratio', () => {
	const withRide = [...withBase(40_000), run(2, 100_000, 'cycle'), run(9, 100_000, 'cycle')];
	assert.deepEqual(selfLoad(withRide, NOW), selfLoad(withBase(40_000), NOW));
});

test('a DNF still counts the distance the runner covered', () => {
	// Deliberately divergent from the coach roster, which excludes DNFs.
	// Nothing rewrites distance_m when the flag is set, so the load was
	// absorbed; dropping it would under-report a spike, which is the
	// dangerous direction for a safety signal (decisions § 592).
	const dnf = [{ ...run(1, 80_000), is_dnf: true }, run(8, 40_000), run(15, 40_000), run(22, 40_000)];
	const load = selfLoad(dnf, NOW);
	assert.equal(load.acuteM, 80_000);
	assert.equal(load.band, 'high');
});

test('the distance ratio equals the coach roster stress ratio', () => {
	// The roster divides km*10 stress sums; this divides metres. The proxy is
	// linear in distance, so the quotient is identical — which is why the
	// constant is not duplicated here. If someone makes the roster's stress
	// non-linear, this equality breaks and this test is the warning.
	const runs = withBase(52_000, 37_000);
	const load = selfLoad(runs, NOW);
	const recent = recentRunVolume(runs, NOW);
	const stress = (metres: number) => (metres / 1000) * 10;
	assert.ok(
		Math.abs(load.ratio - acwr(stress(recent.acuteM), stress(recent.weeklyM))) < 1e-9,
	);
});

test('a run stamped in the future counts as this week, not as a dropped row', () => {
	const ahead = [run(-1, 40_000), run(8, 40_000), run(15, 40_000), run(22, 40_000)];
	assert.equal(selfLoad(ahead, NOW).acuteM, 40_000);
});

test('runs older than the chronic window do not dilute the base', () => {
	const stale = [...withBase(40_000), run(40, 200_000), run(90, 200_000)];
	assert.deepEqual(selfLoad(stale, NOW), selfLoad(withBase(40_000), NOW));
});

test('shouldSurfaceSelfLoad admits every gradeable band', () => {
	for (const acuteM of [10_000, 40_000, 55_000, 80_000]) {
		const load = selfLoad(withBase(acuteM), NOW);
		assert.notEqual(load.band, 'insufficient');
		assert.equal(shouldSurfaceSelfLoad(load), true, String(acuteM));
	}
});

test('shouldSurfaceSelfLoad narrows the band to the ones a caller has copy for', () => {
	// The predicate is what makes an unlabelled band a compile error rather
	// than a missing-i18n-key render, so pin that it is genuinely narrowing
	// and not just returning true.
	const load = selfLoad(withBase(40_000), NOW);
	if (!shouldSurfaceSelfLoad(load)) {
		assert.fail('a graded month should surface');
	}
	const band: 'low' | 'optimal' | 'elevated' | 'high' = load.band;
	assert.equal(band, 'optimal');
});
