import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	CHRONIC_WINDOW_WEEKS,
	MIN_ACTIVE_WEEKS,
	openingWeekVolumeM,
	peakWeekVolumeM,
	planRampCheck,
	recentRunVolume,
	shouldSurfaceRampNote,
	type RunForVolume,
} from './plan_ramp';

const DAY_MS = 86_400_000;
const NOW = Date.parse('2026-08-13T09:00:00.000Z');

function run(daysAgo: number, distanceM: number, activityType = 'run'): RunForVolume {
	return {
		started_at: new Date(NOW - daysAgo * DAY_MS).toISOString(),
		distance_m: distanceM,
		activity_type: activityType,
	};
}

/// One run in each of the four trailing windows, so the active-weeks gate
/// passes and the chronic average is exactly `perWeekM`.
function fourActiveWeeks(perWeekM: number): RunForVolume[] {
	return [run(1, perWeekM), run(8, perWeekM), run(15, perWeekM), run(22, perWeekM)];
}

// ─────────────────────── recentRunVolume ───────────────────────

test('recentRunVolume: totals the window and divides by its width', () => {
	const v = recentRunVolume(fourActiveWeeks(20_000), NOW);
	assert.equal(v.weeklyM, 20_000);
	assert.equal(v.activeWeeks, 4);
});

test('recentRunVolume: no runs is a zero base with no active weeks', () => {
	const v = recentRunVolume([], NOW);
	assert.equal(v.weeklyM, 0);
	assert.equal(v.activeWeeks, 0);
});

test('recentRunVolume: runs older than the window are excluded', () => {
	// 28 days ago is the first instant outside the four 7-day windows.
	const v = recentRunVolume([run(28, 50_000), run(3, 10_000)], NOW);
	assert.equal(v.weeklyM, 10_000 / CHRONIC_WINDOW_WEEKS);
	assert.equal(v.activeWeeks, 1);
});

test('recentRunVolume: the last instant inside the window still counts', () => {
	const v = recentRunVolume([{ started_at: new Date(NOW - 28 * DAY_MS + 1).toISOString(), distance_m: 8000 }], NOW);
	assert.equal(v.activeWeeks, 1);
	assert.equal(v.weeklyM, 2000);
});

test('recentRunVolume: several runs in one window count once toward active weeks', () => {
	const v = recentRunVolume([run(1, 5000), run(2, 5000), run(3, 5000)], NOW);
	assert.equal(v.activeWeeks, 1);
	assert.equal(v.weeklyM, 15_000 / CHRONIC_WINDOW_WEEKS);
});

test('recentRunVolume: cycling is not running volume', () => {
	const v = recentRunVolume([run(1, 60_000, 'cycle'), run(2, 8000)], NOW);
	assert.equal(v.weeklyM, 2000);
	assert.equal(v.activeWeeks, 1);
});

test('recentRunVolume: walks, hikes and treadmill runs are load and do count', () => {
	const v = recentRunVolume([run(1, 4000, 'walk'), run(2, 6000, 'hike'), run(3, 10_000)], NOW);
	assert.equal(v.weeklyM, 5000);
});

test('recentRunVolume: missing / non-finite / non-positive distances are skipped', () => {
	const v = recentRunVolume(
		[
			{ started_at: new Date(NOW - DAY_MS).toISOString(), distance_m: null },
			{ started_at: new Date(NOW - DAY_MS).toISOString(), distance_m: NaN },
			{ started_at: new Date(NOW - DAY_MS).toISOString(), distance_m: 0 },
			run(1, 12_000),
		],
		NOW,
	);
	assert.equal(v.weeklyM, 3000);
	assert.equal(v.activeWeeks, 1);
});

test('recentRunVolume: an unparseable timestamp is skipped, not bucketed at zero', () => {
	const v = recentRunVolume([{ started_at: 'not-a-date', distance_m: 10_000 }], NOW);
	assert.equal(v.weeklyM, 0);
	assert.equal(v.activeWeeks, 0);
});

test('recentRunVolume: a future-stamped run counts as this week, not dropped', () => {
	// A device clock running an hour fast must not lose the run just finished.
	const v = recentRunVolume([{ started_at: new Date(NOW + 3600_000).toISOString(), distance_m: 8000 }], NOW);
	assert.equal(v.activeWeeks, 1);
	assert.equal(v.weeklyM, 2000);
});

// ─────────────────────── openingWeekVolumeM ───────────────────────

test('openingWeekVolumeM: takes the lowest week_index, not the first element', () => {
	assert.equal(
		openingWeekVolumeM([
			{ week_index: 2, target_volume_m: 40_000 },
			{ week_index: 0, target_volume_m: 25_000 },
			{ week_index: 1, target_volume_m: 30_000 },
		]),
		25_000,
	);
});

test('openingWeekVolumeM: empty plan is zero', () => {
	assert.equal(openingWeekVolumeM([]), 0);
});

test('openingWeekVolumeM: non-finite rows are ignored', () => {
	assert.equal(
		openingWeekVolumeM([
			{ week_index: NaN, target_volume_m: 99_000 },
			{ week_index: 0, target_volume_m: 25_000 },
		]),
		25_000,
	);
});
// ─────────────────────── peakWeekVolumeM ───────────────────────

test('peakWeekVolumeM: takes the heaviest week', () => {
	assert.equal(
		peakWeekVolumeM([
			{ target_volume_m: 25_000 },
			{ target_volume_m: 59_000 },
			{ target_volume_m: 32_000 },
		]),
		59_000,
	);
});

test('peakWeekVolumeM: empty plan is zero', () => {
	assert.equal(peakWeekVolumeM([]), 0);
});

test('peakWeekVolumeM: non-finite rows are ignored', () => {
	assert.equal(peakWeekVolumeM([{ target_volume_m: NaN }, { target_volume_m: 30_000 }]), 30_000);
});

// ─────────────────────── planRampCheck ───────────────────────

test('planRampCheck: fewer than the minimum active weeks is unknown', () => {
	const recent = recentRunVolume([run(1, 20_000), run(8, 20_000)], NOW);
	assert.equal(recent.activeWeeks, MIN_ACTIVE_WEEKS - 1);
	const check = planRampCheck(38_000, 59_000, recent);
	assert.equal(check.verdict, 'unknown');
	assert.equal(check.openingRatio, 0);
	assert.equal(check.peakRatio, 0);
});

test('planRampCheck: exactly the minimum active weeks does grade', () => {
	const recent = recentRunVolume([run(1, 20_000), run(8, 20_000), run(15, 20_000)], NOW);
	assert.equal(recent.activeWeeks, MIN_ACTIVE_WEEKS);
	assert.equal(planRampCheck(38_000, 59_000, recent).verdict, 'high');
});

test('planRampCheck: a runner with no history is unknown, never high', () => {
	// The beginner case the gate exists for: one short jog in a month must
	// not turn a C25K opening week into an injury-risk warning.
	const recent = recentRunVolume([run(5, 3000)], NOW);
	assert.equal(planRampCheck(6000, 9000, recent).verdict, 'unknown');
});

test('planRampCheck: a plan with no volume to grade is unknown', () => {
	const recent = recentRunVolume(fourActiveWeeks(20_000), NOW);
	assert.equal(planRampCheck(0, 59_000, recent).verdict, 'unknown');
	assert.equal(planRampCheck(NaN, 59_000, recent).verdict, 'unknown');
	assert.equal(planRampCheck(38_000, 0, recent).verdict, 'unknown');
	assert.equal(planRampCheck(38_000, NaN, recent).verdict, 'unknown');
});

test('planRampCheck: band edges match the coach_load ACWR policy', () => {
	const recent = { weeklyM: 100_000, activeWeeks: 4 };
	const at = (m: number) => planRampCheck(m, m, recent).verdict;
	assert.equal(at(79_000), 'under');
	assert.equal(at(80_000), 'matched');
	assert.equal(at(129_000), 'matched');
	assert.equal(at(130_000), 'elevated');
	assert.equal(at(149_000), 'elevated');
	assert.equal(at(150_000), 'high');
});

test('planRampCheck: reports both ratios it graded on', () => {
	const check = planRampCheck(38_000, 59_000, { weeklyM: 20_000, activeWeeks: 4 });
	assert.equal(check.verdict, 'high');
	assert.equal(check.openingRatio, 1.9);
	assert.equal(check.peakRatio, 2.95);
	assert.equal(check.openingWeekM, 38_000);
	assert.equal(check.peakWeekM, 59_000);
	assert.equal(check.recentWeeklyM, 20_000);
});

test('planRampCheck: the real marathon-on-20km case reads high', () => {
	// generatePlan({ goalEvent: 'distance_full', daysPerWeek: 4 }) with a goal
	// time emits a 38.0 km opening week and a 59.0 km peak. A runner averaging
	// 20 km a week is being asked for 1.9x their current load in week 1 — the
	// case this whole check exists for.
	const recent = recentRunVolume(fourActiveWeeks(20_000), NOW);
	assert.equal(planRampCheck(38_000, 59_000, recent).verdict, 'high');
});

test('planRampCheck: "under" is graded off the peak week, not the opening one', () => {
	// A runner already at 55 km/week building the same marathon plan. Its
	// opening week (38 km) is BELOW their current load — every plan opens
	// below its own peak — but the plan builds past them, so it is not too
	// light. Grading "under" off the opening week would have called it so.
	const check = planRampCheck(38_000, 59_000, { weeklyM: 55_000, activeWeeks: 4 });
	assert.ok(check.openingRatio < 0.8);
	assert.equal(check.verdict, 'matched');
});

test('planRampCheck: a plan that never reaches the runner reads under', () => {
	// The same 55 km/week runner picking a 5K plan: 14 km opening, 20 km peak.
	const check = planRampCheck(14_000, 20_000, { weeklyM: 55_000, activeWeeks: 4 });
	assert.equal(check.verdict, 'under');
});

test('planRampCheck: an oversized opening week wins over a light peak', () => {
	// Not reachable from the generator (peak >= opening always), but a pasted
	// or hand-edited plan can invert them, and safety is the arm that must win.
	const check = planRampCheck(200_000, 50_000, { weeklyM: 100_000, activeWeeks: 4 });
	assert.equal(check.verdict, 'high');
});

// ─────────────────────── shouldSurfaceRampNote ───────────────────────

test('shouldSurfaceRampNote: silent when the plan matches the runner', () => {
	assert.equal(
		shouldSurfaceRampNote(planRampCheck(100_000, 100_000, { weeklyM: 100_000, activeWeeks: 4 })),
		false,
	);
});

test('shouldSurfaceRampNote: silent when there is not enough history to speak', () => {
	assert.equal(
		shouldSurfaceRampNote(planRampCheck(38_000, 59_000, { weeklyM: 0, activeWeeks: 0 })),
		false,
	);
});

test('shouldSurfaceRampNote: speaks on both elevated and high', () => {
	assert.equal(
		shouldSurfaceRampNote(planRampCheck(140_000, 140_000, { weeklyM: 100_000, activeWeeks: 4 })),
		true,
	);
	assert.equal(
		shouldSurfaceRampNote(planRampCheck(200_000, 200_000, { weeklyM: 100_000, activeWeeks: 4 })),
		true,
	);
});

test('shouldSurfaceRampNote: an under-cooked plan is worth saying', () => {
	assert.equal(
		shouldSurfaceRampNote(planRampCheck(40_000, 40_000, { weeklyM: 100_000, activeWeeks: 4 })),
		true,
	);
});

test('shouldSurfaceRampNote: but not to a runner who asked for a walk-run plan', () => {
	const check = planRampCheck(40_000, 40_000, { weeklyM: 100_000, activeWeeks: 4 });
	assert.equal(check.verdict, 'under');
	assert.equal(shouldSurfaceRampNote(check, { beginnerWalkRun: true }), false);
});

test('shouldSurfaceRampNote: a walk-run plan still gets the safety warnings', () => {
	const check = planRampCheck(200_000, 200_000, { weeklyM: 100_000, activeWeeks: 4 });
	assert.equal(shouldSurfaceRampNote(check, { beginnerWalkRun: true }), true);
});
