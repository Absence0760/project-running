import { test } from 'node:test';
import assert from 'node:assert/strict';
import { orderedPlanPhases, longestCompletedLongRunMetres } from './plan_progress';

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

test('longestCompletedLongRunMetres: ignores non-long completed workouts', () => {
	const workouts = [
		{ kind: 'tempo', target_distance_m: 40_000, manually_completed: true },
		{ kind: 'long', target_distance_m: 12_000, manually_completed: true },
	];
	assert.equal(longestCompletedLongRunMetres(workouts), 12_000);
});
