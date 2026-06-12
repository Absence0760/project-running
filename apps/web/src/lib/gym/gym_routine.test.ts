import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	routineFromWorkout,
	prefillFromRoutine,
	expandRoutineSteps,
	type LoggedSet,
	type PlannedRoutine,
	type PlannedSet,
} from './gym_routine';

function pset(setIndex: number, reps: number | null, weightKg: number | null): PlannedSet {
	return {
		setIndex,
		targetRepsMin: reps,
		targetRepsMax: null,
		targetWeightKg: weightKg,
		targetRpe: null,
	};
}

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

test('expandRoutineSteps: a single exercise with 3 sets expands to 3 steps in setIndex order', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'Squat',
				position: 0,
				sets: [pset(2, 5, 100), pset(0, 5, 100), pset(1, 5, 100)],
			},
		],
	};
	const out = expandRoutineSteps(routine);
	assert.equal(out.totalSets, 3);
	assert.equal(out.supersetGroups, 0);
	assert.deepEqual(
		out.steps.map((s) => s.setIndex),
		[0, 1, 2],
	);
	assert.equal(out.steps[0].setType, 'working');
});

test('expandRoutineSteps: two sequential exercises expand all of ex1 then all of ex2', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{ exerciseName: 'Bench', position: 0, sets: [pset(0, 5, 80), pset(1, 5, 80)] },
			{ exerciseName: 'Row', position: 1, sets: [pset(0, 8, 60)] },
		],
	};
	const out = expandRoutineSteps(routine);
	assert.deepEqual(
		out.steps.map((s) => s.exerciseName),
		['Bench', 'Bench', 'Row'],
	);
	assert.equal(out.totalSets, 3);
});

test('expandRoutineSteps: a superset group of 2 x 3 sets interleaves A1,B1,A2,B2,A3,B3', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'Curl',
				position: 0,
				supersetGroup: 1,
				supersetOrder: 0,
				sets: [pset(0, 10, 15), pset(1, 10, 15), pset(2, 10, 15)],
			},
			{
				exerciseName: 'Pushdown',
				position: 1,
				supersetGroup: 1,
				supersetOrder: 1,
				sets: [pset(0, 12, 30), pset(1, 12, 30), pset(2, 12, 30)],
			},
		],
	};
	const out = expandRoutineSteps(routine);
	assert.deepEqual(
		out.steps.map((s) => `${s.exerciseName}${s.setIndex}`),
		['Curl0', 'Pushdown0', 'Curl1', 'Pushdown1', 'Curl2', 'Pushdown2'],
	);
	assert.equal(out.supersetGroups, 1);
	assert.equal(out.totalSets, 6);
});

test('expandRoutineSteps: supersetOrder is honoured over position', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'A',
				position: 0,
				supersetGroup: 7,
				supersetOrder: 1,
				sets: [pset(0, 5, 10)],
			},
			{
				exerciseName: 'B',
				position: 1,
				supersetGroup: 7,
				supersetOrder: 0,
				sets: [pset(0, 5, 10)],
			},
		],
	};
	const out = expandRoutineSteps(routine);
	assert.deepEqual(
		out.steps.map((s) => s.exerciseName),
		['B', 'A'],
	);
});

test('expandRoutineSteps: a superset group followed by a standalone', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'A',
				position: 0,
				supersetGroup: 1,
				supersetOrder: 0,
				sets: [pset(0, 5, 10), pset(1, 5, 10)],
			},
			{
				exerciseName: 'B',
				position: 1,
				supersetGroup: 1,
				supersetOrder: 1,
				sets: [pset(0, 5, 10), pset(1, 5, 10)],
			},
			{ exerciseName: 'Finisher', position: 2, sets: [pset(0, 20, 0)] },
		],
	};
	const out = expandRoutineSteps(routine);
	assert.deepEqual(
		out.steps.map((s) => `${s.exerciseName}${s.setIndex}`),
		['A0', 'B0', 'A1', 'B1', 'Finisher0'],
	);
	assert.equal(out.supersetGroups, 1);
	assert.equal(out.totalSets, 5);
});

test('expandRoutineSteps: an uneven superset (A x3, B x2) skips B\'s missing 3rd round', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'A',
				position: 0,
				supersetGroup: 1,
				supersetOrder: 0,
				sets: [pset(0, 5, 10), pset(1, 5, 10), pset(2, 5, 10)],
			},
			{
				exerciseName: 'B',
				position: 1,
				supersetGroup: 1,
				supersetOrder: 1,
				sets: [pset(0, 8, 20), pset(1, 8, 20)],
			},
		],
	};
	const out = expandRoutineSteps(routine);
	assert.deepEqual(
		out.steps.map((s) => `${s.exerciseName}${s.setIndex}`),
		['A0', 'B0', 'A1', 'B1', 'A2'],
	);
	assert.equal(out.supersetGroups, 1);
	assert.equal(out.totalSets, 5);
});

test('expandRoutineSteps: a duration-based set is preserved (targetDurationS set, weight null)', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [
			{
				exerciseName: 'Plank',
				position: 0,
				sets: [
					{
						setIndex: 0,
						targetRepsMin: null,
						targetRepsMax: null,
						targetWeightKg: null,
						targetRpe: null,
						targetDurationS: 60,
						setType: 'working',
					},
				],
			},
		],
	};
	const out = expandRoutineSteps(routine);
	assert.equal(out.steps[0].targetDurationS, 60);
	assert.equal(out.steps[0].targetWeightKg, null);
	assert.equal(out.steps[0].targetRepsMin, null);
});

test('expandRoutineSteps: an empty routine yields no steps', () => {
	const out = expandRoutineSteps({ title: 'P', exercises: [] });
	assert.deepEqual(out, { steps: [], totalSets: 0, supersetGroups: 0 });
});

test('expandRoutineSteps: exerciseKey is stamped via normaliseExerciseName', () => {
	const routine: PlannedRoutine = {
		title: 'P',
		exercises: [{ exerciseName: '  Bench   Press ', position: 0, sets: [pset(0, 5, 80)] }],
	};
	const out = expandRoutineSteps(routine);
	assert.equal(out.steps[0].exerciseKey, 'bench press');
	assert.equal(out.steps[0].exerciseName, '  Bench   Press ');
});
