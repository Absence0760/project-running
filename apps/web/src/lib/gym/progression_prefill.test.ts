import { test } from 'node:test';
import assert from 'node:assert/strict';

import { lastSessionSets, type DatedLoggedSet } from './progression_prefill';

function s(
	workout_id: string,
	started_at: string,
	exercise_name: string,
	reps: number | null,
	weight_kg: number | null,
): DatedLoggedSet {
	return { workout_id, started_at, exercise_name, reps, weight_kg, rpe: null };
}

test('returns null when the exercise was never logged', () => {
	const sets = [s('w1', '2026-01-01', 'Squat', 5, 100)];
	assert.equal(lastSessionSets(sets, 'Bench Press'), null);
});

test('returns null for a blank exercise name', () => {
	const sets = [s('w1', '2026-01-01', 'Squat', 5, 100)];
	assert.equal(lastSessionSets(sets, '   '), null);
});

test('picks the most recent session by started_at, keeping logged order', () => {
	const sets = [
		s('w1', '2026-01-01', 'Bench', 5, 80),
		s('w2', '2026-02-01', 'Bench', 5, 82.5),
		s('w2', '2026-02-01', 'Bench', 4, 82.5),
	];
	assert.deepEqual(lastSessionSets(sets, 'Bench'), [
		{ reps: 5, weight_kg: 82.5, rpe: null },
		{ reps: 4, weight_kg: 82.5, rpe: null },
	]);
});

test('matches by normalised name (case / spacing insensitive)', () => {
	const sets = [s('w1', '2026-01-01', '  bench  press ', 5, 80)];
	assert.deepEqual(lastSessionSets(sets, 'Bench Press'), [{ reps: 5, weight_kg: 80, rpe: null }]);
});

test('ignores other exercises in the same workout', () => {
	const sets = [
		s('w1', '2026-02-01', 'Squat', 5, 120),
		s('w1', '2026-02-01', 'Bench', 5, 80),
	];
	assert.deepEqual(lastSessionSets(sets, 'Bench'), [{ reps: 5, weight_kg: 80, rpe: null }]);
});

test('ties on started_at break by workout id (deterministic)', () => {
	const sets = [
		s('wA', '2026-02-01', 'Row', 8, 50),
		s('wB', '2026-02-01', 'Row', 8, 55),
	];
	assert.deepEqual(lastSessionSets(sets, 'Row'), [{ reps: 8, weight_kg: 55, rpe: null }]);
});
