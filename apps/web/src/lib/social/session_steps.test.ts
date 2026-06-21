import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	expandSessionSteps,
	computeSessionAdherence,
	type SessionPlanInput,
	type SessionStep,
	type SessionStepResult
} from './session_steps';

function item(over: Partial<SessionPlanInput['items'][number]> = {}) {
	return {
		id: 'i',
		block_id: null,
		position: 0,
		movement_name: 'Pose',
		kind: 'hold' as const,
		duration_s: 30,
		reps: null,
		per_side: false,
		tempo: null,
		cue: null,
		...over
	};
}

test('block flatten: blocks in position order, items in position order within', () => {
	const plan: SessionPlanInput = {
		blocks: [
			{ id: 'b2', position: 2, name: 'Standing' },
			{ id: 'b1', position: 1, name: 'Warm-up' }
		],
		items: [
			item({ id: 'b2i1', block_id: 'b2', position: 1, movement_name: 'Warrior II', duration_s: 60 }),
			item({ id: 'b1i2', block_id: 'b1', position: 2, movement_name: 'Cat-Cow', duration_s: 20 }),
			item({ id: 'b1i1', block_id: 'b1', position: 1, movement_name: 'Child', duration_s: 30 })
		]
	};
	const out = expandSessionSteps(plan);
	assert.deepEqual(
		out.steps.map((s) => s.movementName),
		['Child', 'Cat-Cow', 'Warrior II']
	);
	assert.deepEqual(
		out.steps.map((s) => s.cumulativeS),
		[30, 50, 110]
	);
	assert.equal(out.totalS, 110);
});

test('per-side split: a per_side item becomes consecutive Left then Right steps', () => {
	const plan: SessionPlanInput = {
		blocks: [],
		items: [item({ id: 'lunge', movement_name: 'Low Lunge', duration_s: 45, per_side: true })]
	};
	const out = expandSessionSteps(plan);
	assert.equal(out.steps.length, 2);
	assert.deepEqual(
		out.steps.map((s) => s.movementName),
		['Low Lunge', 'Low Lunge']
	);
	assert.deepEqual(
		out.steps.map((s) => s.side),
		['left', 'right']
	);
	assert.deepEqual(
		out.steps.map((s) => s.cumulativeS),
		[45, 90]
	);
	assert.equal(out.totalS, 90);
});

test('reps step with no duration contributes 0 to the time estimate', () => {
	const plan: SessionPlanInput = {
		blocks: [],
		items: [
			item({ id: 'hold', movement_name: 'Plank', kind: 'hold', duration_s: 60 }),
			item({
				id: 'roll',
				position: 1,
				movement_name: 'Roll-Up',
				kind: 'reps',
				duration_s: null,
				reps: 10
			}),
			item({ id: 'flow', position: 2, movement_name: 'Vinyasa', kind: 'flow', duration_s: 15 })
		]
	};
	const out = expandSessionSteps(plan);
	assert.deepEqual(
		out.steps.map((s) => s.cumulativeS),
		[60, 60, 75]
	);
	assert.equal(out.steps[1].reps, 10);
	assert.equal(out.steps[1].durationS, null);
	assert.equal(out.totalS, 75);
});

test('empty plan: no blocks, no items -> no steps, zero total', () => {
	const out = expandSessionSteps({ blocks: [], items: [] });
	assert.deepEqual(out.steps, []);
	assert.equal(out.totalS, 0);
});

test('single item: one non-per-side hold -> one step', () => {
	const out = expandSessionSteps({
		blocks: [],
		items: [item({ id: 'savasana', movement_name: 'Savasana', duration_s: 300, cue: 'Soften' })]
	});
	assert.equal(out.steps.length, 1);
	assert.equal(out.steps[0].movementName, 'Savasana');
	assert.equal(out.steps[0].side, null);
	assert.equal(out.steps[0].cue, 'Soften');
	assert.equal(out.steps[0].cumulativeS, 300);
	assert.equal(out.totalS, 300);
});

function step(over: Partial<SessionStep> = {}): SessionStep {
	return {
		itemId: 'i',
		movementName: 'Pose',
		kind: 'hold',
		durationS: 30,
		reps: null,
		tempo: null,
		cue: null,
		side: null,
		cumulativeS: 30,
		...over
	};
}

function result(over: Partial<SessionStepResult> = {}): SessionStepResult {
	return {
		itemId: 'i',
		movementName: 'Pose',
		kind: 'hold',
		side: null,
		targetDurationS: 30,
		actualDurationS: 30,
		status: 'completed',
		...over
	};
}

test('adherence: all steps completed -> completed verdict, pct 1.0', () => {
	const steps = [step({ itemId: 'a' }), step({ itemId: 'b' }), step({ itemId: 'c' })];
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'b' }),
		result({ itemId: 'c' })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.completedSteps, 3);
	assert.equal(out.totalSteps, 3);
	assert.equal(out.adherencePct, 1);
	assert.equal(out.verdict, 'completed');
});

test('adherence: zero completed -> abandoned verdict', () => {
	const steps = [step({ itemId: 'a' }), step({ itemId: 'b' })];
	const results = [
		result({ itemId: 'a', status: 'skipped', actualDurationS: null }),
		result({ itemId: 'b', status: 'skipped', actualDurationS: null })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.completedSteps, 0);
	assert.equal(out.adherencePct, 0);
	assert.equal(out.verdict, 'abandoned');
});

test('adherence: 80% boundary -> completed verdict', () => {
	const steps = ['a', 'b', 'c', 'd', 'e'].map((id) => step({ itemId: id }));
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'b' }),
		result({ itemId: 'c' }),
		result({ itemId: 'd' }),
		result({ itemId: 'e', status: 'skipped', actualDurationS: null })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.completedSteps, 4);
	assert.equal(out.adherencePct, 0.8);
	assert.equal(out.verdict, 'completed');
});

test('adherence: below 80% -> partial verdict', () => {
	const steps = ['a', 'b', 'c', 'd'].map((id) => step({ itemId: id }));
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'b' }),
		result({ itemId: 'c', status: 'skipped', actualDurationS: null }),
		result({ itemId: 'd', status: 'skipped', actualDurationS: null })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.completedSteps, 2);
	assert.equal(out.adherencePct, 0.5);
	assert.equal(out.verdict, 'partial');
});

test('adherence: a skipped step counts toward total but not completed', () => {
	const steps = [step({ itemId: 'a' }), step({ itemId: 'b' })];
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'b', status: 'skipped', actualDurationS: null })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.totalSteps, 2);
	assert.equal(out.completedSteps, 1);
	assert.equal(out.adherencePct, 0.5);
	assert.equal(out.verdict, 'partial');
});

test('adherence: more completed results than steps clamps to 1.0', () => {
	const steps = [step({ itemId: 'a' }), step({ itemId: 'b' })];
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'a' }),
		result({ itemId: 'b' })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.totalSteps, 2);
	assert.equal(out.completedSteps, 2);
	assert.equal(out.adherencePct, 1);
	assert.equal(out.verdict, 'completed');
});

test('adherence: results with itemIds not matching any step are ignored', () => {
	const steps = [step({ itemId: 'a' }), step({ itemId: 'b' })];
	const results = [
		result({ itemId: 'a' }),
		result({ itemId: 'ghost' }),
		result({ itemId: 'phantom' })
	];
	const out = computeSessionAdherence(steps, results);
	assert.equal(out.totalSteps, 2);
	assert.equal(out.completedSteps, 1);
	assert.equal(out.adherencePct, 0.5);
	assert.equal(out.verdict, 'partial');
});
