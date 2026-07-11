import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	orderedPlanPhases,
	longestCompletedLongRunMetres,
	planDistanceBanked,
} from './plan_progress';

// ─────────────────────── orderedPlanPhases ───────────────────────

test('orderedPlanPhases: de-dupes and sorts into canonical order', () => {
	const weeks = [
		{ phase: 'build' },
		{ phase: 'base' },
		{ phase: 'build' },
		{ phase: 'taper' },
		{ phase: 'peak' },
	];
	assert.deepEqual(orderedPlanPhases(weeks), ['base', 'build', 'peak', 'taper']);
});

test('orderedPlanPhases: empty plan yields no phases', () => {
	assert.deepEqual(orderedPlanPhases([]), []);
});

test('orderedPlanPhases: ignores unknown phase strings', () => {
	assert.deepEqual(orderedPlanPhases([{ phase: 'base' }, { phase: 'mystery' }]), ['base']);
});

// ─────────────────── longestCompletedLongRunMetres ───────────────────

test('longestCompletedLongRunMetres: null when no long run is completed', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 25_000, completed_run_id: null },
		{ kind: 'easy', target_distance_m: 8_000, completed_run_id: 'r1', manually_completed: false },
	];
	assert.equal(longestCompletedLongRunMetres(workouts), null);
});

test('longestCompletedLongRunMetres: picks the max completed long-run target', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 18_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 28_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 32_000, completed_run_id: null }, // not done
	];
	assert.equal(longestCompletedLongRunMetres(workouts), 28_000);
});

test('longestCompletedLongRunMetres: prefers actual run distance over the planned target', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 30_000, completed_run_id: 'r1' },
	];
	// The runner actually went 31.2 km on the long run scheduled for 30.
	const actual = new Map([['r1', 31_200]]);
	assert.equal(longestCompletedLongRunMetres(workouts, actual), 31_200);
});

test('longestCompletedLongRunMetres: falls back to target when the run is off-window', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 30_000, completed_run_id: 'r-old' },
	];
	// r-old isn't in the supplied recent-runs map.
	assert.equal(longestCompletedLongRunMetres(workouts, new Map()), 30_000);
});

test('longestCompletedLongRunMetres: a zero-distance linked run falls back to the planned target', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 30_000, completed_run_id: 'r1' },
	];
	// r1 is linked but recorded 0 m (distance-less / degenerate import) — it
	// must not drop the long run; fall back to the 30 km planned target.
	assert.equal(longestCompletedLongRunMetres(workouts, new Map([['r1', 0]])), 30_000);
});

test('longestCompletedLongRunMetres: a zero-distance linked run does not beat a real longer run', () => {
	const workouts = [
		{ kind: 'long', target_distance_m: 18_000, completed_run_id: 'r1' }, // recorded 0
		{ kind: 'long', target_distance_m: 22_000, completed_run_id: 'r2' }, // recorded 24 km
	];
	const actual = new Map([['r1', 0], ['r2', 24_000]]);
	assert.equal(longestCompletedLongRunMetres(workouts, actual), 24_000);
});

test('longestCompletedLongRunMetres: ignores non-long completed workouts', () => {
	const workouts = [
		{ kind: 'tempo', target_distance_m: 40_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 12_000, manually_completed: true },
	];
	assert.equal(longestCompletedLongRunMetres(workouts), 12_000);
});

// ─────────────────────── planDistanceBanked ───────────────────────

test('planDistanceBanked: sums planned over non-rest, completed over done', () => {
	const workouts = [
		{ kind: 'easy', target_distance_m: 8_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 20_000, completed_run_id: null },
		{ kind: 'rest', target_distance_m: null },
	];
	assert.deepEqual(planDistanceBanked(workouts), {
		completedMetres: 8_000,
		plannedMetres: 28_000,
	});
});

test('planDistanceBanked: prefers actual run distance for completed workouts', () => {
	const workouts = [{ kind: 'long', target_distance_m: 20_000, completed_run_id: 'r1' }];
	const actual = new Map([['r1', 21_400]]);
	assert.deepEqual(planDistanceBanked(workouts, actual), {
		completedMetres: 21_400,
		plannedMetres: 20_000,
	});
});

test('planDistanceBanked: a skipped workout leaves the planned denominator', () => {
	const workouts = [
		{ kind: 'easy', target_distance_m: 8_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 20_000, skipped_at: '2026-07-01T00:00:00Z' },
	];
	// The skipped long run is off the books: it neither counts as banked nor
	// inflates the plan's asking distance.
	assert.deepEqual(planDistanceBanked(workouts), {
		completedMetres: 8_000,
		plannedMetres: 8_000,
	});
});

test('planDistanceBanked: banked can exceed planned when the runner over-runs', () => {
	const workouts = [{ kind: 'long', target_distance_m: 20_000, completed_run_id: 'r1' }];
	const actual = new Map([['r1', 24_000]]);
	const r = planDistanceBanked(workouts, actual);
	assert.equal(r.completedMetres, 24_000);
	assert.equal(r.plannedMetres, 20_000);
});

test('planDistanceBanked: a zero-distance linked run falls back to the planned target', () => {
	const workouts = [{ kind: 'long', target_distance_m: 20_000, completed_run_id: 'r1' }];
	assert.deepEqual(planDistanceBanked(workouts, new Map([['r1', 0]])), {
		completedMetres: 20_000,
		plannedMetres: 20_000,
	});
});

test('planDistanceBanked: empty plan is zero / zero', () => {
	assert.deepEqual(planDistanceBanked([]), { completedMetres: 0, plannedMetres: 0 });
});
