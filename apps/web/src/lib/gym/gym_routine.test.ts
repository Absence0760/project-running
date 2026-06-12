import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	routineFromWorkout,
	prefillFromRoutine,
	type LoggedSet,
	type PlannedRoutine,
} from './gym_routine';

function lset(
	exercise_name: string,
	reps: number | null,
	weight_kg: number | null,
	rpe: number | null = null,
): LoggedSet {
	return { exercise_name, reps, weight_kg, rpe };
}

test('routineFromWorkout: groups consecutive equal names into one block', () => {
	const draft = routineFromWorkout('Push day', [
		lset('Bench Press', 5, 80),
		lset('Bench Press', 5, 80),
		lset('Overhead Press', 8, 40),
	]);
	assert.equal(draft.title, 'Push day');
	assert.equal(draft.exerciseCount, 2);
	assert.equal(draft.exercises[0].exerciseName, 'Bench Press');
	assert.equal(draft.exercises[0].sets.length, 2);
	assert.equal(draft.exercises[1].exerciseName, 'Overhead Press');
	assert.equal(draft.exercises[1].sets.length, 1);
});

test('routineFromWorkout: a re-entered exercise later is its own block', () => {
	const draft = routineFromWorkout(null, [
		lset('Squat', 5, 100),
		lset('Curl', 10, 15),
		lset('Squat', 5, 100),
	]);
	assert.equal(draft.exercises.length, 3);
	assert.deepEqual(
		draft.exercises.map((e) => e.exerciseName),
		['Squat', 'Curl', 'Squat'],
	);
	assert.deepEqual(
		draft.exercises.map((e) => e.position),
		[0, 1, 2],
	);
});

test('routineFromWorkout: stamps exercise_key via normaliseExerciseName', () => {
	const draft = routineFromWorkout(null, [lset('  Bench   Press ', 5, 80)]);
	assert.equal(draft.exercises[0].exerciseName, 'Bench   Press'); // display trimmed only at ends
	assert.equal(draft.exercises[0].exerciseKey, 'bench press');
});

test('routineFromWorkout: logged values become planned targets', () => {
	const draft = routineFromWorkout(null, [lset('Deadlift', 3, 180, 9)]);
	const s = draft.exercises[0].sets[0];
	assert.equal(s.setIndex, 0);
	assert.equal(s.setType, 'working');
	assert.equal(s.targetRepsMin, 3);
	assert.equal(s.targetRepsMax, null);
	assert.equal(s.targetWeightKg, 180);
	assert.equal(s.targetRpe, 9);
});

test('routineFromWorkout: drops blank-named sets', () => {
	const draft = routineFromWorkout(null, [lset('   ', 5, 50), lset('Row', 8, 60)]);
	assert.equal(draft.exercises.length, 1);
	assert.equal(draft.exercises[0].exerciseName, 'Row');
});

test('routineFromWorkout: null reps/weight carry through as null targets', () => {
	const draft = routineFromWorkout(null, [lset('Plank', null, null)]);
	const s = draft.exercises[0].sets[0];
	assert.equal(s.targetRepsMin, null);
	assert.equal(s.targetWeightKg, null);
});

test('routineFromWorkout: empty/whitespace title falls back', () => {
	assert.equal(routineFromWorkout('   ', [lset('X', 1, 1)]).title, 'Routine');
	assert.equal(routineFromWorkout(undefined, [lset('X', 1, 1)]).title, 'Routine');
	assert.equal(routineFromWorkout(null, [lset('X', 1, 1)], 'My plan').title, 'My plan');
});

test('routineFromWorkout: no sets yields an empty draft', () => {
	const draft = routineFromWorkout('Empty', []);
	assert.equal(draft.exerciseCount, 0);
	assert.deepEqual(draft.exercises, []);
});

test('prefillFromRoutine: orders by position and setIndex, fills targets', () => {
	const routine: PlannedRoutine = {
		title: 'Plan',
		exercises: [
			{
				exerciseName: 'Overhead Press',
				position: 1,
				sets: [{ setIndex: 1, targetRepsMin: 8, targetRepsMax: null, targetWeightKg: 40, targetRpe: null }],
			},
			{
				exerciseName: 'Bench Press',
				position: 0,
				sets: [
					{ setIndex: 1, targetRepsMin: 5, targetRepsMax: null, targetWeightKg: 80, targetRpe: 8 },
					{ setIndex: 0, targetRepsMin: 5, targetRepsMax: null, targetWeightKg: 80, targetRpe: 8 },
				],
			},
		],
	};
	const blocks = prefillFromRoutine(routine);
	assert.deepEqual(
		blocks.map((b) => b.name),
		['Bench Press', 'Overhead Press'],
	);
	// Bench sets sorted by setIndex (0 then 1).
	assert.equal(blocks[0].sets.length, 2);
	assert.equal(blocks[0].sets[0].reps, '5');
	assert.equal(blocks[0].sets[0].weightKg, 80);
	assert.equal(blocks[0].sets[0].rpe, '8');
});

test('prefillFromRoutine: rep range prefills the min', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'DB Press',
				position: 0,
				sets: [{ setIndex: 0, targetRepsMin: 8, targetRepsMax: 12, targetWeightKg: 20, targetRpe: null }],
			},
		],
	};
	const blocks = prefillFromRoutine(routine);
	assert.equal(blocks[0].sets[0].reps, '8');
});

test('prefillFromRoutine: null targets prefill empty strings', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'Plank',
				position: 0,
				sets: [{ setIndex: 0, targetRepsMin: null, targetRepsMax: null, targetWeightKg: null, targetRpe: null }],
			},
		],
	};
	const blocks = prefillFromRoutine(routine);
	assert.equal(blocks[0].sets[0].reps, '');
	assert.equal(blocks[0].sets[0].weightKg, null);
	assert.equal(blocks[0].sets[0].rpe, '');
});

test('prefillFromRoutine: an empty routine yields one empty block', () => {
	const blocks = prefillFromRoutine({ title: 'P', exercises: [] });
	assert.equal(blocks.length, 1);
	assert.equal(blocks[0].name, '');
	assert.equal(blocks[0].sets.length, 1);
	assert.equal(blocks[0].sets[0].reps, '');
});

test('prefillFromRoutine: an exercise with no sets yields one empty set', () => {
	const blocks = prefillFromRoutine({
		title: 'P',
		exercises: [{ exerciseName: 'Squat', position: 0, sets: [] }],
	});
	assert.equal(blocks[0].name, 'Squat');
	assert.equal(blocks[0].sets.length, 1);
	assert.equal(blocks[0].sets[0].reps, '');
});
