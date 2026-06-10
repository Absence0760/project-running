import { test } from 'node:test';
import assert from 'node:assert/strict';
import { exerciseProgress, previousExerciseSession, type DatedGymSet } from './exercise_history';

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

test('unknown exercise / blank name yields null', () => {
	assert.equal(exerciseProgress([], 'Bench Press'), null);
	assert.equal(exerciseProgress([s({})], '   '), null);
	assert.equal(exerciseProgress([s({ exercise_name: 'Squat' })], 'Deadlift'), null);
});

test('collapses sessions chronologically with top set, e1rm, volume and set count', () => {
	const p = exerciseProgress(
		[
			s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', reps: 3, weight_kg: 110 }),
			s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 100 }),
			s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 90 }),
		],
		'Bench Press',
	);
	assert.ok(p);
	assert.equal(p.exerciseName, 'Bench Press');
	assert.equal(p.sessions.length, 2);
	// Oldest first.
	assert.equal(p.sessions[0].workoutId, 'w1');
	assert.equal(p.sessions[1].workoutId, 'w2');
	// Session 1: heaviest 100 (5 reps), two sets, volume 5×100 + 5×90 = 950.
	assert.equal(p.sessions[0].topWeightKg, 100);
	assert.equal(p.sessions[0].topWeightReps, 5);
	assert.equal(p.sessions[0].setCount, 2);
	assert.equal(p.sessions[0].volumeKg, 950);
	// e1rm session 1: max(100·(1+5/30), 90·(1+5/30)) = 116.67 → 116.7.
	assert.equal(p.sessions[0].bestEst1RmKg, 116.7);
});

test('marks the session that set a new estimated-1RM PR', () => {
	const p = exerciseProgress(
		[
			s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 100 }), // e1rm 116.7
			s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', reps: 5, weight_kg: 95 }), // e1rm 110.8 — no PR
			s({ workout_id: 'w3', started_at: '2026-06-09T08:00:00Z', reps: 3, weight_kg: 110 }), // e1rm 121 — PR
		],
		'Bench Press',
	);
	assert.ok(p);
	assert.deepEqual(
		p.sessions.map((x) => x.isEst1RmPr),
		[true, false, true],
	);
});

test('headline est-1RM delta is latest minus first across sessions with an e1rm', () => {
	const p = exerciseProgress(
		[
			s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 100 }), // 116.7
			s({ workout_id: 'w2', started_at: '2026-06-09T08:00:00Z', reps: 3, weight_kg: 110 }), // 121.0
		],
		'Bench Press',
	);
	assert.ok(p);
	assert.equal(p.firstEst1RmKg, 116.7);
	assert.equal(p.latestEst1RmKg, 121);
	assert.equal(p.bestEst1RmKg, 121);
	assert.equal(p.est1RmDeltaKg, 4.3);
});

test('delta is null with only one e1rm data point', () => {
	const p = exerciseProgress([s({ reps: 5, weight_kg: 100 })], 'Bench Press');
	assert.ok(p);
	assert.equal(p.est1RmDeltaKg, null);
	assert.equal(p.firstEst1RmKg, 116.7);
});

test('case/whitespace name variants match the same exercise', () => {
	const p = exerciseProgress(
		[
			s({ workout_id: 'w1', exercise_name: 'Bench Press', weight_kg: 100 }),
			s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', exercise_name: 'bench  press', weight_kg: 110 }),
		],
		'BENCH PRESS',
	);
	assert.ok(p);
	assert.equal(p.sessions.length, 2);
	// Display spelling is the first-seen one, via the PR engine.
	assert.equal(p.exerciseName, 'Bench Press');
});

test('a session with only bodyweight sets of the exercise is excluded', () => {
	const p = exerciseProgress(
		[
			s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', weight_kg: 100 }),
			s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', reps: 10, weight_kg: null }),
		],
		'Bench Press',
	);
	assert.ok(p);
	assert.equal(p.sessions.length, 1);
	assert.equal(p.sessions[0].workoutId, 'w1');
});

test('a weighted session with no reps carries a top weight but no e1rm/volume', () => {
	const p = exerciseProgress([s({ exercise_name: 'Carry', reps: null, weight_kg: 50 })], 'Carry');
	assert.ok(p);
	assert.equal(p.sessions[0].topWeightKg, 50);
	assert.equal(p.sessions[0].bestEst1RmKg, null);
	assert.equal(p.sessions[0].volumeKg, 0);
	assert.equal(p.est1RmDeltaKg, null);
	assert.equal(p.bestEst1RmKg, null);
});

test('previousExerciseSession returns the latest qualifying session before the cutoff', () => {
	const sets = [
		s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', reps: 5, weight_kg: 100 }),
		s({ workout_id: 'w2', started_at: '2026-06-05T08:00:00Z', reps: 5, weight_kg: 105 }),
		s({ workout_id: 'w3', started_at: '2026-06-09T08:00:00Z', reps: 5, weight_kg: 110 }),
	];
	// Cutoff = w3's started_at: the previous session is w2 (105), not w3 itself.
	const prev = previousExerciseSession(sets, 'Bench Press', '2026-06-09T08:00:00Z');
	assert.ok(prev);
	assert.equal(prev.workoutId, 'w2');
	assert.equal(prev.topWeightKg, 105);
});

test('previousExerciseSession is null when nothing precedes the cutoff', () => {
	const sets = [s({ workout_id: 'w1', started_at: '2026-06-05T08:00:00Z', weight_kg: 100 })];
	// Cutoff equals the only session's date — strict `<` excludes it.
	assert.equal(previousExerciseSession(sets, 'Bench Press', '2026-06-05T08:00:00Z'), null);
	// Cutoff before everything.
	assert.equal(previousExerciseSession(sets, 'Bench Press', '2026-06-01T00:00:00Z'), null);
});

test('previousExerciseSession ignores other exercises and bodyweight-only sessions', () => {
	const sets = [
		s({ workout_id: 'w1', started_at: '2026-06-01T08:00:00Z', exercise_name: 'Squat', weight_kg: 140 }),
		s({ workout_id: 'w2', started_at: '2026-06-03T08:00:00Z', exercise_name: 'Bench Press', reps: 10, weight_kg: null }),
		s({ workout_id: 'w3', started_at: '2026-06-05T08:00:00Z', exercise_name: 'Bench Press', reps: 5, weight_kg: 100 }),
	];
	// Looking back from w4's date for Bench Press: w2 is bodyweight-only (skipped),
	// w1 is a different exercise (skipped) → w3 is the previous Bench session.
	const prev = previousExerciseSession(sets, 'Bench Press', '2026-06-09T08:00:00Z');
	assert.ok(prev);
	assert.equal(prev.workoutId, 'w3');
	assert.equal(prev.topWeightKg, 100);
});
