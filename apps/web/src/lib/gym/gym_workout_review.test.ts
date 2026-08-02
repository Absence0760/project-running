import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { reviewFromMetadata, reviewRowKey } from './gym_workout_review';
import {
	computeRoutineAdherence,
	type ActualSetRef,
	type PlannedSetRef,
} from './gym_adherence';

function row(over: Record<string, unknown> = {}): Record<string, unknown> {
	return {
		exercise_key: 'squat',
		step_index: 0,
		set_index: 0,
		status: 'hit',
		reps_delta: null,
		weight_delta_kg: null,
		target_reps_min: 5,
		target_reps_max: null,
		target_weight_kg: 100,
		target_duration_s: null,
		target_distance_m: null,
		actual_reps: 5,
		actual_weight_kg: 100,
		actual_duration_s: null,
		actual_distance_m: null,
		...over,
	};
}

function meta(rows: unknown[], verdict = 'completed'): Record<string, unknown> {
	return { routine_id: 'r1', gym_step_results: rows, gym_adherence: verdict };
}

test('replays stepIndex from the persisted step_index, not the per-block set_index', () => {
	// The heavy-top-set-then-back-off pattern: one exercise in two blocks, so
	// set_index restarts and only step_index distinguishes the four refs.
	const rows = [
		row({ step_index: 0, set_index: 0, target_weight_kg: 140 }),
		row({ step_index: 1, set_index: 1, target_weight_kg: 140 }),
		row({ step_index: 2, set_index: 0, target_weight_kg: 100 }),
		row({ step_index: 3, set_index: 1, target_weight_kg: 100 }),
	];
	const out = reviewFromMetadata(meta(rows));
	assert.ok(out);
	assert.deepEqual(
		out.adherence.sets.map((s) => s.stepIndex),
		[0, 1, 2, 3],
	);
	assert.deepEqual(
		out.adherence.sets.map((s) => s.setIndex),
		[0, 1, 0, 1],
	);
	// The identity has to be unique across the session — the whole point of §304.
	assert.equal(new Set(out.adherence.sets.map((s) => s.stepIndex)).size, 4);
});

test('replay reproduces exactly what computeRoutineAdherence produced at session time', () => {
	const planned: PlannedSetRef[] = [0, 1, 2, 3].map((i) => ({
		exerciseKey: 'squat',
		stepIndex: i,
		setIndex: i % 2,
		setType: 'working',
		targetRepsMin: 5,
		targetRepsMax: null,
		targetWeightKg: i < 2 ? 140 : 100,
		targetDurationS: null,
		targetDistanceM: null,
	}));
	const actual: ActualSetRef[] = [
		{
			exerciseKey: 'squat',
			stepIndex: 0,
			setIndex: 0,
			reps: 6,
			weightKg: 145,
			durationS: null,
			distanceM: null,
		},
		{
			exerciseKey: 'squat',
			stepIndex: 2,
			setIndex: 0,
			reps: 5,
			weightKg: 100,
			durationS: null,
			distanceM: null,
		},
	];
	const live = computeRoutineAdherence(planned, actual);

	// Persist it the way GymSessionRunner.buildMetadata does, then replay.
	const rows = live.sets.map((s) => ({
		exercise_key: s.exerciseKey,
		step_index: s.stepIndex,
		set_index: s.setIndex,
		status: s.status,
		reps_delta: s.repsDelta,
		weight_delta_kg: s.weightDeltaKg,
	}));
	const out = reviewFromMetadata(meta(rows, live.verdict));

	assert.ok(out);
	assert.deepEqual(out.adherence.sets, live.sets);
	assert.equal(out.adherence.plannedCount, live.plannedCount);
	assert.equal(out.adherence.completedCount, live.completedCount);
	assert.equal(out.adherence.adherencePct, live.adherencePct);
	assert.equal(out.adherence.verdict, live.verdict);
});

test('replays the persisted deltas instead of discarding them', () => {
	const out = reviewFromMetadata(
		meta([row({ status: 'partial', reps_delta: -2, weight_delta_kg: -5.5 })]),
		);
	assert.ok(out);
	assert.equal(out.adherence.sets[0].repsDelta, -2);
	assert.equal(out.adherence.sets[0].weightDeltaKg, -5.5);
});

test('a pre-decisions-304 row with no step_index replays under the set_index it was written with', () => {
	const legacy = row();
	delete legacy.step_index;
	const out = reviewFromMetadata(meta([legacy, { ...row(), step_index: undefined, set_index: 1 }]));
	assert.ok(out);
	assert.deepEqual(
		out.adherence.sets.map((s) => s.stepIndex),
		[0, 1],
	);
});

test('extra sets stay in the table but out of the denominator', () => {
	const rows = [
		row({ step_index: 0, set_index: 0, status: 'hit' }),
		row({ step_index: 1, set_index: 1, status: 'missed' }),
		row({ step_index: 2, set_index: 2, status: 'extra' }),
	];
	const out = reviewFromMetadata(meta(rows, 'partial'));
	assert.ok(out);
	assert.equal(out.adherence.sets.length, 3);
	assert.equal(out.adherence.plannedCount, 2);
	assert.equal(out.adherence.completedCount, 1);
	assert.equal(out.adherence.adherencePct, 0.5);
	assert.equal(out.adherence.verdict, 'partial');
	assert.equal(out.stepResults.length, 3);
});

test('an all-extra session reports 0% rather than dividing by zero', () => {
	const out = reviewFromMetadata(meta([row({ status: 'extra' })], 'abandoned'));
	assert.ok(out);
	assert.equal(out.adherence.plannedCount, 0);
	assert.equal(out.adherence.adherencePct, 0);
});

test('self-hides on a missing, empty, or unrecognisable trio', () => {
	assert.equal(reviewFromMetadata(null), null);
	assert.equal(reviewFromMetadata(undefined), null);
	assert.equal(reviewFromMetadata('nope'), null);
	assert.equal(reviewFromMetadata({}), null);
	assert.equal(reviewFromMetadata(meta([])), null);
	assert.equal(reviewFromMetadata({ gym_step_results: [row()] }), null);
	assert.equal(reviewFromMetadata(meta([row()], 'finished')), null);
	assert.equal(reviewFromMetadata({ ...meta([row()]), gym_step_results: 'x' }), null);
});

test('reviewRowKey stays unique when one exercise is programmed into two blocks', () => {
	// The decisions §304 shape: `set_index` restarts per block, so keying on it
	// collides and Svelte throws each_key_duplicate, wedging the whole review.
	const rows = [
		{ exercise_key: 'squat', set_index: 0, step_index: 0, status: 'hit' as const },
		{ exercise_key: 'squat', set_index: 1, step_index: 1, status: 'hit' as const },
		{ exercise_key: 'squat', set_index: 0, step_index: 2, status: 'hit' as const },
		{ exercise_key: 'squat', set_index: 1, step_index: 3, status: 'hit' as const },
	];
	const keys = rows.map(reviewRowKey);
	assert.equal(new Set(keys).size, rows.length);
});

test('reviewRowKey falls back to set_index on pre-§304 rows', () => {
	const row = { exercise_key: 'squat', set_index: 2, status: 'hit' as const };
	assert.equal(reviewRowKey(row), 'squat:2:hit');
});
