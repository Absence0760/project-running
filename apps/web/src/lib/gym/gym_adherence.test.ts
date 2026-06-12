import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import {
	computeRoutineAdherence,
	type PlannedSetRef,
	type ActualSetRef,
} from './gym_adherence';

function planned(
	exerciseKey: string,
	setIndex: number,
	targetRepsMin: number | null = null,
	targetWeightKg: number | null = null,
	targetDurationS: number | null = null,
	targetRepsMax: number | null = null,
	setType: string = 'working',
): PlannedSetRef {
	return {
		exerciseKey,
		setIndex,
		setType,
		targetRepsMin,
		targetRepsMax,
		targetWeightKg,
		targetDurationS,
	};
}

function actual(
	exerciseKey: string,
	setIndex: number,
	reps: number | null = null,
	weightKg: number | null = null,
	durationS: number | null = null,
): ActualSetRef {
	return { exerciseKey, setIndex, reps, weightKg, durationS };
}

test('all sets hit -> completed, pct 1.0', () => {
	const r = computeRoutineAdherence(
		[planned('bench', 0, 5, 80), planned('bench', 1, 5, 80)],
		[actual('bench', 0, 5, 80), actual('bench', 1, 6, 85)],
	);
	assert.equal(r.plannedCount, 2);
	assert.equal(r.completedCount, 2);
	assert.equal(r.adherencePct, 1.0);
	assert.equal(r.verdict, 'completed');
	assert.deepEqual(
		r.sets.map((s) => s.status),
		['hit', 'hit'],
	);
});

test('zero completed -> abandoned', () => {
	const r = computeRoutineAdherence(
		[planned('squat', 0, 5, 100), planned('squat', 1, 5, 100)],
		[],
	);
	assert.equal(r.completedCount, 0);
	assert.equal(r.adherencePct, 0);
	assert.equal(r.verdict, 'abandoned');
});

test('80% boundary -> completed', () => {
	const plan: PlannedSetRef[] = [];
	const act: ActualSetRef[] = [];
	for (let i = 0; i < 10; i++) plan.push(planned('row', i, 5, 50));
	for (let i = 0; i < 8; i++) act.push(actual('row', i, 5, 50));
	const r = computeRoutineAdherence(plan, act);
	assert.equal(r.completedCount, 8);
	assert.equal(r.adherencePct, 0.8);
	assert.equal(r.verdict, 'completed');
});

test('79% -> partial', () => {
	const plan: PlannedSetRef[] = [];
	const act: ActualSetRef[] = [];
	for (let i = 0; i < 100; i++) plan.push(planned('row', i, 5, 50));
	for (let i = 0; i < 79; i++) act.push(actual('row', i, 5, 50));
	const r = computeRoutineAdherence(plan, act);
	assert.equal(r.completedCount, 79);
	assert.equal(r.adherencePct, 0.79);
	assert.equal(r.verdict, 'partial');
});

test('reps below min -> partial status', () => {
	const r = computeRoutineAdherence([planned('curl', 0, 10, 20)], [actual('curl', 0, 7, 20)]);
	assert.equal(r.sets[0].status, 'partial');
	assert.equal(r.completedCount, 0);
});

test('weight below 80% of target -> missed', () => {
	const r = computeRoutineAdherence([planned('press', 0, 5, 60)], [actual('press', 0, 5, 45)]);
	assert.equal(r.sets[0].status, 'missed');
	assert.equal(r.completedCount, 0);
});

test('reps at 80% of floor -> hit', () => {
	const r = computeRoutineAdherence([planned('curl', 0, 10, 20)], [actual('curl', 0, 8, 20)]);
	assert.equal(r.sets[0].status, 'hit');
	assert.equal(r.verdict, 'completed');
});

test('weight at 80% of target -> hit', () => {
	const r = computeRoutineAdherence([planned('press', 0, 5, 100)], [actual('press', 0, 5, 80)]);
	assert.equal(r.sets[0].status, 'hit');
});

test('weight at 79% of target -> missed', () => {
	const r = computeRoutineAdherence([planned('press', 0, 5, 100)], [actual('press', 0, 5, 79)]);
	assert.equal(r.sets[0].status, 'missed');
});

test('warmup set is excluded from the verdict denominator', () => {
	const r = computeRoutineAdherence(
		[planned('squat', 0, 5, 60, null, null, 'warmup'), planned('squat', 1, 5, 100)],
		[actual('squat', 1, 5, 100)],
	);
	assert.equal(r.plannedCount, 1);
	assert.equal(r.completedCount, 1);
	assert.equal(r.verdict, 'completed');
	assert.ok(!r.sets.some((s) => s.exerciseKey === 'squat' && s.setIndex === 0));
});

test('amrap set is hit when any reps logged', () => {
	const r = computeRoutineAdherence(
		[planned('pullup', 0, 5, null, null, null, 'amrap')],
		[actual('pullup', 0, 3, null)],
	);
	assert.equal(r.sets[0].status, 'hit');
	assert.equal(r.verdict, 'completed');
});

test('extra unplanned set -> extra, not counted in plannedCount', () => {
	const r = computeRoutineAdherence(
		[planned('bench', 0, 5, 80)],
		[actual('bench', 0, 5, 80), actual('bench', 1, 5, 80)],
	);
	assert.equal(r.plannedCount, 1);
	assert.equal(r.completedCount, 1);
	const extra = r.sets.find((s) => s.status === 'extra');
	assert.ok(extra);
	assert.equal(extra?.setIndex, 1);
	assert.equal(r.adherencePct, 1.0);
});

test('duration-set hit by durationS', () => {
	const r = computeRoutineAdherence(
		[planned('plank', 0, null, null, 60), planned('plank', 1, null, null, 60)],
		[actual('plank', 0, null, null, 75), actual('plank', 1, null, null, 45)],
	);
	assert.equal(r.sets[0].status, 'hit');
	assert.equal(r.sets[1].status, 'partial');
});

test('deltas signed correctly', () => {
	const r = computeRoutineAdherence(
		[planned('bench', 0, 5, 80), planned('bench', 1, 8, 100)],
		[actual('bench', 0, 7, 85), actual('bench', 1, 6, 90)],
	);
	assert.equal(r.sets[0].repsDelta, 2);
	assert.equal(r.sets[0].weightDeltaKg, 5);
	assert.equal(r.sets[1].repsDelta, -2);
	assert.equal(r.sets[1].weightDeltaKg, -10);
});

test('empty planned -> abandoned edge, pct 0', () => {
	const r = computeRoutineAdherence([], [actual('bench', 0, 5, 80)]);
	assert.equal(r.plannedCount, 0);
	assert.equal(r.completedCount, 0);
	assert.equal(r.adherencePct, 0);
	assert.equal(r.verdict, 'abandoned');
	assert.equal(r.sets.length, 1);
	assert.equal(r.sets[0].status, 'extra');
});

test('empty actual -> all missed', () => {
	const r = computeRoutineAdherence(
		[planned('squat', 0, 5, 100), planned('squat', 1, 5, 100), planned('squat', 2, 5, 100)],
		[],
	);
	assert.deepEqual(
		r.sets.map((s) => s.status),
		['missed', 'missed', 'missed'],
	);
	assert.equal(r.verdict, 'abandoned');
});

test('match by key+setIndex, not name spelling', () => {
	const r = computeRoutineAdherence(
		[planned('bench-press', 0, 5, 80)],
		[actual('bench-press', 0, 5, 80), actual('Bench Press', 0, 5, 80)],
	);
	assert.equal(r.sets[0].status, 'hit');
	const extra = r.sets.find((s) => s.exerciseKey === 'Bench Press');
	assert.equal(extra?.status, 'extra');
	assert.equal(r.plannedCount, 1);
	assert.equal(r.completedCount, 1);
});
