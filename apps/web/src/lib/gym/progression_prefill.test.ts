import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	consecutiveMissSessions,
	lastSessionSets,
	progressionParamsWithStreak,
	type DatedLoggedSet,
} from './progression_prefill';
import { nextPrescription } from './gym_progression';

const FIVE_BY_FIVE = { targetSets: 5, targetReps: 5 };

/// Five completed sets of `reps` at `weight` — one 5×5 session of `name`.
function session(
	workout_id: string,
	started_at: string,
	name: string,
	reps: number,
	weight: number,
	count = 5,
): DatedLoggedSet[] {
	return Array.from({ length: count }, () => s(workout_id, started_at, name, reps, weight));
}

function s(
	workout_id: string,
	started_at: string,
	exercise_name: string,
	reps: number | null,
	weight_kg: number | null,
	set_type: string | null = 'working',
): DatedLoggedSet {
	return { workout_id, started_at, exercise_name, reps, weight_kg, rpe: null, set_type };
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
		{ reps: 5, weight_kg: 82.5, rpe: null, set_type: 'working' },
		{ reps: 4, weight_kg: 82.5, rpe: null, set_type: 'working' },
	]);
});

test('matches by normalised name (case / spacing insensitive)', () => {
	const sets = [s('w1', '2026-01-01', '  bench  press ', 5, 80)];
	assert.deepEqual(lastSessionSets(sets, 'Bench Press'), [
		{ reps: 5, weight_kg: 80, rpe: null, set_type: 'working' },
	]);
});

test('ignores other exercises in the same workout', () => {
	const sets = [
		s('w1', '2026-02-01', 'Squat', 5, 120),
		s('w1', '2026-02-01', 'Bench', 5, 80),
	];
	assert.deepEqual(lastSessionSets(sets, 'Bench'), [
		{ reps: 5, weight_kg: 80, rpe: null, set_type: 'working' },
	]);
});

test('ties on started_at break by workout id (deterministic)', () => {
	const sets = [
		s('wA', '2026-02-01', 'Row', 8, 50),
		s('wB', '2026-02-01', 'Row', 8, 55),
	];
	assert.deepEqual(lastSessionSets(sets, 'Row'), [
		{ reps: 8, weight_kg: 55, rpe: null, set_type: 'working' },
	]);
});

test('set_type is carried through to the prescriber', () => {
	// The prescriber excludes warmups; it can only do that if this glue passes
	// the column along. Dropping it here is how the ramp-up set came to be
	// judged as a failed working set.
	const sets = [
		s('w1', '2026-03-01', 'Squat', 3, 60, 'warmup'),
		s('w1', '2026-03-01', 'Squat', 5, 100, 'working'),
	];
	assert.deepEqual(
		lastSessionSets(sets, 'Squat')?.map((x) => x.set_type),
		['warmup', 'working'],
	);
});

test('consecutiveMissSessions: an unlogged exercise has no streak', () => {
	assert.equal(consecutiveMissSessions([], 'Squat', FIVE_BY_FIVE), 0);
	assert.equal(
		consecutiveMissSessions(session('w1', '2026-01-01', 'Bench', 5, 80), 'Squat', FIVE_BY_FIVE),
		0,
	);
});

test('consecutiveMissSessions: counts back from the newest, stopping at the first cleared session', () => {
	const sets = [
		...session('w1', '2026-01-01', 'Squat', 3, 100), // an older miss, past the stop
		...session('w2', '2026-01-08', 'Squat', 5, 100), // cleared — the walk stops here
		...session('w3', '2026-01-15', 'Squat', 4, 100),
		...session('w4', '2026-01-22', 'Squat', 4, 100),
		...session('w5', '2026-01-29', 'Squat', 3, 100),
	];
	assert.equal(consecutiveMissSessions(sets, 'Squat', FIVE_BY_FIVE), 3);
});

test('consecutiveMissSessions: too few completed sets is a miss even at target reps', () => {
	// StrongLifts fails a session on the set count, not only on the reps: four
	// clean sets of five is still a failed 5×5.
	const sets = session('w1', '2026-02-01', 'Squat', 5, 100, 4);
	assert.equal(consecutiveMissSessions(sets, 'Squat', FIVE_BY_FIVE), 1);
});

test('consecutiveMissSessions: a session with no completed working set is skipped, not counted', () => {
	// Warmups-only and rep-less rows are logging artifacts, not failures — three
	// of them must not add up to a prescribed load reduction.
	const sets = [
		...session('w1', '2026-02-01', 'Squat', 5, 100),
		s('w2', '2026-02-08', 'Squat', 3, 60, 'warmup'),
		s('w3', '2026-02-15', 'Squat', null, 100),
		s('w4', '2026-02-22', 'Squat', 0, 100),
	];
	assert.equal(consecutiveMissSessions(sets, 'Squat', FIVE_BY_FIVE), 0);
});

test('progressionParamsWithStreak: a non-5×5 scheme passes its params through untouched', () => {
	const params = { incrementKg: 5 };
	assert.equal(
		progressionParamsWithStreak({
			scheme: 'linear',
			params,
			targetRepsMin: 5,
			targetRepsMax: 5,
			history: session('w1', '2026-01-01', 'Squat', 2, 100),
			exerciseName: 'Squat',
		}),
		params,
	);
	assert.equal(
		progressionParamsWithStreak({
			scheme: 'none',
			params: null,
			targetRepsMin: null,
			targetRepsMax: null,
			history: [],
			exerciseName: 'Squat',
		}),
		null,
	);
});

test('progressionParamsWithStreak: derives the count, overriding a stale authored one', () => {
	const out = progressionParamsWithStreak({
		scheme: 'five_by_five',
		params: { incrementKg: 5, consecutiveMisses: 99 },
		targetRepsMin: 5,
		targetRepsMax: 5,
		history: [
			...session('w1', '2026-03-01', 'Squat', 4, 100),
			...session('w2', '2026-03-08', 'Squat', 4, 100),
		],
		exerciseName: 'Squat',
	});
	assert.deepEqual(out, { incrementKg: 5, consecutiveMisses: 2 });
});

test('progressionParamsWithStreak: a routine with no rep target grades on params.targetSets/targetReps', () => {
	// The bar has to be resolved the same way the prescriber resolves it, or the
	// streak grades sessions against a 5×5 the routine never prescribed.
	const params = { targetSets: 3, targetReps: 3 };
	const args = {
		scheme: 'five_by_five' as const,
		params,
		targetRepsMin: null,
		targetRepsMax: null,
		exerciseName: 'Dip',
	};
	const cleared = [
		...session('w1', '2026-06-01', 'Dip', 3, 20, 3),
		...session('w2', '2026-06-08', 'Dip', 3, 20, 3),
	];
	assert.deepEqual(progressionParamsWithStreak({ ...args, history: cleared }), {
		...params,
		consecutiveMisses: 0,
	});
	const short = [
		...session('w1', '2026-06-01', 'Dip', 2, 20, 3),
		...session('w2', '2026-06-08', 'Dip', 2, 20, 3),
	];
	assert.deepEqual(progressionParamsWithStreak({ ...args, history: short }), {
		...params,
		consecutiveMisses: 2,
	});
});

test('a stall of three sessions now reaches the deload the prescriber could never fire', () => {
	// Regression: progression_params is authored at routine-build time and never
	// carried consecutiveMisses, so `misses` was always 0 and five_by_five could
	// only ever hold. A lifter stuck at 100 kg stayed at 100 kg forever.
	const history = [
		...session('w1', '2026-04-01', 'Squat', 4, 100),
		...session('w2', '2026-04-08', 'Squat', 4, 100),
		...session('w3', '2026-04-15', 'Squat', 4, 100),
	];
	const args = {
		scheme: 'five_by_five' as const,
		params: null,
		targetRepsMin: 5,
		targetRepsMax: 5,
		history,
		exerciseName: 'Squat',
	};
	const stalled = nextPrescription({
		scheme: 'five_by_five',
		lastSets: lastSessionSets(history, 'Squat') ?? [],
		targetRepsMin: 5,
		targetRepsMax: 5,
		params: progressionParamsWithStreak(args),
	});
	assert.equal(stalled.reason, 'deload');
	assert.equal(stalled.suggestedWeightKg, 90);

	// Two misses is still a hold — the third is what earns the back-off.
	const twoMisses = history.filter((x) => x.workout_id !== 'w3');
	const held = nextPrescription({
		scheme: 'five_by_five',
		lastSets: lastSessionSets(twoMisses, 'Squat') ?? [],
		targetRepsMin: 5,
		targetRepsMax: 5,
		params: progressionParamsWithStreak({ ...args, history: twoMisses }),
	});
	assert.equal(held.reason, 'hold');
	assert.equal(held.suggestedWeightKg, 100);
});

test('breaking the stall clears the streak, so the next session is not deloaded', () => {
	const history = [
		...session('w1', '2026-05-01', 'Squat', 4, 100),
		...session('w2', '2026-05-08', 'Squat', 4, 100),
		...session('w3', '2026-05-15', 'Squat', 4, 100),
		...session('w4', '2026-05-22', 'Squat', 5, 100),
	];
	const out = nextPrescription({
		scheme: 'five_by_five',
		lastSets: lastSessionSets(history, 'Squat') ?? [],
		targetRepsMin: 5,
		targetRepsMax: 5,
		params: progressionParamsWithStreak({
			scheme: 'five_by_five',
			params: null,
			targetRepsMin: 5,
			targetRepsMax: 5,
			history,
			exerciseName: 'Squat',
		}),
	});
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 102.5);
});
