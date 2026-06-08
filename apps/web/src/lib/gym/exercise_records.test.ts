import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exerciseRecords, type DatedGymSet } from './exercise_records';

function s(over: Partial<DatedGymSet>): DatedGymSet {
	return {
		workout_id: 'w1',
		started_at: '2026-06-01T08:00:00Z',
		exercise_name: 'Bench Press',
		reps: 5,
		weight_kg: 100,
		...over,
	};
}

test('empty input yields no records', () => {
	assert.deepEqual(exerciseRecords([]), []);
});

test('single weighted exercise rolls up its bests, last date and session count', () => {
	const out = exerciseRecords([
		s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 100 }),
		s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 3, weight_kg: 105 }),
		s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', reps: 8, weight_kg: 90 }),
	]);
	assert.equal(out.length, 1);
	const r = out[0];
	assert.equal(r.exerciseName, 'Bench Press');
	assert.equal(r.heaviestWeightKg, 105);
	assert.equal(r.heaviestWeightReps, 3);
	// Best single-set volume = 8 × 90 = 720 (beats 5×100=500, 3×105=315).
	assert.equal(r.bestVolumeKg, 720);
	// e1rm best: 90·(1+8/30)=114 beats 105 (single → 105) and 100·(1+5/30)≈116.67.
	assert.equal(r.bestEst1RmKg, 116.7);
	assert.equal(r.lastPerformedAt, '2026-06-05T08:00:00Z');
	assert.equal(r.sessionCount, 2);
});

test('bodyweight-only exercise (no weight) is excluded — consistent with the PR engine', () => {
	const out = exerciseRecords([
		s({ exercise_name: 'Pull-up', reps: 12, weight_kg: null }),
		s({ exercise_name: 'Squat', reps: 5, weight_kg: 140 }),
	]);
	assert.deepEqual(
		out.map((r) => r.exerciseName),
		['Squat'],
	);
});

test('sorted most-recently-performed first, ties broken alphabetically', () => {
	const out = exerciseRecords([
		s({ exercise_name: 'Deadlift', workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', weight_kg: 180 }),
		s({ exercise_name: 'Squat', workout_id: 'w2', started_at: '2026-06-10T08:00:00Z', weight_kg: 140 }),
		// Same last date as Squat → alphabetical: Bench before Squat.
		s({ exercise_name: 'Bench Press', workout_id: 'w3', started_at: '2026-06-10T08:00:00Z', weight_kg: 100 }),
	]);
	assert.deepEqual(
		out.map((r) => r.exerciseName),
		['Bench Press', 'Squat', 'Deadlift'],
	);
});

test('case/whitespace variants of a name collapse to one record', () => {
	const out = exerciseRecords([
		s({ exercise_name: 'Bench Press', weight_kg: 100 }),
		s({ exercise_name: 'bench  press', weight_kg: 110 }),
		s({ exercise_name: '  BENCH PRESS ', weight_kg: 105 }),
	]);
	assert.equal(out.length, 1);
	assert.equal(out[0].heaviestWeightKg, 110);
	// Display spelling is the first set's spelling (PR-engine behaviour).
	assert.equal(out[0].exerciseName, 'Bench Press');
});

test('sessionCount counts distinct workouts, not sets', () => {
	const out = exerciseRecords([
		s({ workout_id: 'w1', weight_kg: 100 }),
		s({ workout_id: 'w1', weight_kg: 100 }),
		s({ workout_id: 'w1', weight_kg: 100 }),
	]);
	assert.equal(out[0].sessionCount, 1);
});

test('blank exercise names are ignored', () => {
	const out = exerciseRecords([
		s({ exercise_name: '   ', weight_kg: 100 }),
		s({ exercise_name: '', weight_kg: 100 }),
	]);
	assert.deepEqual(out, []);
});

test('volume and e1rm stay null when an exercise was only ever logged without reps', () => {
	const out = exerciseRecords([s({ exercise_name: 'Carry', reps: null, weight_kg: 50 })]);
	assert.equal(out.length, 1);
	assert.equal(out[0].heaviestWeightKg, 50);
	assert.equal(out[0].bestVolumeKg, null);
	assert.equal(out[0].bestEst1RmKg, null);
});
