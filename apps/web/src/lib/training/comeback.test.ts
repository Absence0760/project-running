import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	LAYOFF_MAX_DAYS,
	LAYOFF_MIN_DAYS,
	RETURN_WEEK_SHARE,
	comebackLoad,
	shouldSurfaceComeback,
} from './comeback';
import { CHRONIC_WINDOW_WEEKS, MIN_ACTIVE_WEEKS } from './plan_ramp';
import { selfLoad, shouldSurfaceSelfLoad } from './self_load';
import { kLayoffResetDays } from './training_load';

const NOW = Date.parse('2026-08-14T12:00:00Z');
const DAY_MS = 86_400_000;

function run(daysAgo: number, distanceM: number, activityType = 'run') {
	return {
		started_at: new Date(NOW - daysAgo * DAY_MS).toISOString(),
		distance_m: distanceM,
		activity_type: activityType,
	};
}

/// A runner who trained 40 km a week for four weeks, took `layoffDays` off,
/// and has just logged `thisWeekM` in the last seven days.
function comebackRunner(layoffDays: number, thisWeekM: number, baseWeeklyM = 40_000) {
	const lastBefore = 1 + layoffDays;
	return [
		run(1, thisWeekM),
		run(lastBefore, baseWeeklyM),
		run(lastBefore + 7, baseWeeklyM),
		run(lastBefore + 14, baseWeeklyM),
		run(lastBefore + 21, baseWeeklyM),
	];
}

test('the layoff threshold is the fitness-reset one, not a second number', () => {
	assert.equal(LAYOFF_MIN_DAYS, kLayoffResetDays);
});

test('a gentle first week back is graded easing_in', () => {
	const load = comebackLoad(comebackRunner(70, 12_000), NOW);
	assert.equal(load.verdict, 'easing_in');
	assert.equal(load.thisWeekM, 12_000);
	assert.equal(load.preLayoffWeeklyM, 160_000 / CHRONIC_WINDOW_WEEKS);
	assert.ok(Math.abs(load.share - 0.3) < 1e-9);
	assert.equal(load.layoffDays, 70);
	assert.equal(load.layoffWeeks, 10);
});

test('a big first week back is graded steep', () => {
	const load = comebackLoad(comebackRunner(70, 36_000), NOW);
	assert.equal(load.verdict, 'steep');
	assert.ok(Math.abs(load.share - 0.9) < 1e-9);
});

test('the steep threshold is exclusive — exactly half the old base still eases in', () => {
	const half = RETURN_WEEK_SHARE * 40_000;
	assert.equal(comebackLoad(comebackRunner(70, half), NOW).verdict, 'easing_in');
	assert.equal(comebackLoad(comebackRunner(70, half + 1), NOW).verdict, 'steep');
});

test('layoff weeks round to nearest so a break is never understated', () => {
	// 45 days is 6.43 weeks; flooring would report 6 and undersell the break.
	assert.equal(comebackLoad(comebackRunner(45, 12_000), NOW).layoffWeeks, 6);
	assert.equal(comebackLoad(comebackRunner(52, 12_000), NOW).layoffWeeks, 7);
});

test('a rest week shorter than the layoff threshold is not a comeback', () => {
	const load = comebackLoad(comebackRunner(LAYOFF_MIN_DAYS - 2, 30_000), NOW);
	assert.equal(load.verdict, 'insufficient');
});

test('a break long enough to reset fitness is a comeback', () => {
	const load = comebackLoad(comebackRunner(LAYOFF_MIN_DAYS, 30_000), NOW);
	assert.notEqual(load.verdict, 'insufficient');
});

test('a base too stale to anchor against says nothing rather than reassuring', () => {
	const stale = comebackLoad(comebackRunner(LAYOFF_MAX_DAYS + 1, 30_000), NOW);
	assert.equal(stale.verdict, 'insufficient');
	assert.equal(stale.share, 0);
	assert.equal(stale.layoffDays, 0);
	const fresh = comebackLoad(comebackRunner(LAYOFF_MAX_DAYS, 30_000), NOW);
	assert.notEqual(fresh.verdict, 'insufficient');
});

test('a single run before the break is not a base to come back to', () => {
	const load = comebackLoad([run(1, 30_000), run(71, 40_000)], NOW);
	assert.equal(load.verdict, 'insufficient');
});

test('the pre-break base needs MIN_ACTIVE_WEEKS of its own windows', () => {
	const twoWeeks = [run(1, 30_000), run(71, 40_000), run(78, 40_000)];
	assert.equal(comebackLoad(twoWeeks, NOW).verdict, 'insufficient');
	assert.equal(MIN_ACTIVE_WEEKS, 3);
	const threeWeeks = [...twoWeeks, run(85, 40_000)];
	assert.notEqual(comebackLoad(threeWeeks, NOW).verdict, 'insufficient');
});

test('a week with no running is not graded as a gentle return', () => {
	const idle = comebackRunner(70, 12_000).slice(1);
	assert.equal(comebackLoad(idle, NOW).verdict, 'insufficient');
});

test('a runner who never stopped is not on a comeback', () => {
	const steady = [run(1, 40_000), run(8, 40_000), run(15, 40_000), run(22, 40_000)];
	assert.equal(comebackLoad(steady, NOW).verdict, 'insufficient');
});

test('an empty history says nothing', () => {
	assert.equal(comebackLoad([], NOW).verdict, 'insufficient');
});

test('a run stamped in the future does not inflate the break it appears to open', () => {
	// A clock 40 days ahead puts today's run in the future; the hole between it
	// and the runner's last real session reads as 70 days unclamped, and 30 —
	// the break they actually took — once the stamp is pulled back to now.
	const runs = [run(-40, 10_000), run(30, 40_000), run(37, 40_000), run(44, 40_000), run(51, 40_000)];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.layoffDays, 30);
	assert.equal(load.thisWeekM, 10_000);
});

test('the two load cards are mutually exclusive by construction', () => {
	const cases = [
		comebackRunner(70, 36_000),
		comebackRunner(70, 12_000),
		comebackRunner(LAYOFF_MIN_DAYS - 2, 30_000),
		[run(1, 40_000), run(8, 40_000), run(15, 40_000), run(22, 40_000)],
		// Back for three consecutive weeks: the ratio can carry the question
		// again, so the comeback card must stand down.
		[run(1, 30_000), run(8, 20_000), run(15, 10_000), run(80, 40_000), run(87, 40_000), run(94, 40_000)],
		[],
	];
	for (const runs of cases) {
		const ratio = shouldSurfaceSelfLoad(selfLoad(runs, NOW));
		const comeback = shouldSurfaceComeback(comebackLoad(runs, NOW));
		assert.ok(!(ratio && comeback), 'both load cards surfaced for the same history');
	}
});

test('a returned runner with three active weeks is handed back to the ratio card', () => {
	const runs = [
		run(1, 30_000),
		run(8, 20_000),
		run(15, 10_000),
		run(80, 40_000),
		run(87, 40_000),
		run(94, 40_000),
	];
	assert.equal(comebackLoad(runs, NOW).verdict, 'insufficient');
	assert.ok(shouldSurfaceSelfLoad(selfLoad(runs, NOW)));
});

test('the most recent break is the one graded, not an older one', () => {
	const runs = [
		run(1, 30_000),
		run(41, 40_000),
		run(48, 40_000),
		run(55, 40_000),
		run(62, 40_000),
		// An older, longer break sits behind a full pre-break base.
		run(400, 90_000),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.layoffDays, 40);
	assert.equal(load.preLayoffWeeklyM, 160_000 / CHRONIC_WINDOW_WEEKS);
});

test('cycling is not running volume on either side of the break', () => {
	const runs = [
		run(1, 12_000),
		run(2, 60_000, 'cycle'),
		run(71, 40_000),
		run(78, 40_000),
		run(85, 40_000),
		run(86, 100_000, 'cycle'),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.thisWeekM, 12_000);
	assert.equal(load.preLayoffWeeklyM, 120_000 / CHRONIC_WINDOW_WEEKS);
});

test('unparseable and non-positive rows are dropped rather than read as a break', () => {
	const runs = [
		run(1, 12_000),
		{ started_at: 'not-a-date', distance_m: 50_000, activity_type: 'run' },
		{ started_at: new Date(NOW - 35 * DAY_MS).toISOString(), distance_m: 0, activity_type: 'run' },
		run(71, 40_000),
		run(78, 40_000),
		run(85, 40_000),
	];
	const load = comebackLoad(runs, NOW);
	assert.equal(load.verdict, 'easing_in');
	assert.equal(load.layoffDays, 70);
});

test('shouldSurfaceComeback narrows to the verdicts the card has copy for', () => {
	const load = comebackLoad(comebackRunner(70, 36_000), NOW);
	assert.ok(shouldSurfaceComeback(load));
	if (shouldSurfaceComeback(load)) {
		const verdict: 'easing_in' | 'steep' = load.verdict;
		assert.equal(verdict, 'steep');
	}
	assert.equal(shouldSurfaceComeback(comebackLoad([], NOW)), false);
});
