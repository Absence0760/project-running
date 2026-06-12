import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	parseGymTemplate,
	gymTemplateFromInputs,
	workoutDraftFromTemplate,
	workoutDraftFromSession
} from './event_gym_template';
import type { SessionStep } from './session_steps';

function step(over: Partial<SessionStep>): SessionStep {
	return {
		itemId: 'i',
		movementName: 'Move',
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

test('parseGymTemplate: valid full template', () => {
	assert.deepEqual(parseGymTemplate({ discipline: 'Vinyasa yoga', duration_min: 60 }), {
		discipline: 'Vinyasa yoga',
		duration_min: 60
	});
});

test('parseGymTemplate: null / non-object / array -> null', () => {
	assert.equal(parseGymTemplate(null), null);
	assert.equal(parseGymTemplate(undefined), null);
	assert.equal(parseGymTemplate('yoga'), null);
	assert.equal(parseGymTemplate(42), null);
	assert.equal(parseGymTemplate([1, 2]), null);
});

test('parseGymTemplate: empty object -> null (treated as no template)', () => {
	assert.equal(parseGymTemplate({}), null);
});

test('parseGymTemplate: discipline only', () => {
	assert.deepEqual(parseGymTemplate({ discipline: 'Spin' }), {
		discipline: 'Spin',
		duration_min: null
	});
});

test('parseGymTemplate: duration only', () => {
	assert.deepEqual(parseGymTemplate({ duration_min: 45 }), {
		discipline: null,
		duration_min: 45
	});
});

test('parseGymTemplate: wrong-typed values are dropped', () => {
	// numeric discipline + string duration + blank discipline all coerce to null
	assert.equal(parseGymTemplate({ discipline: 123, duration_min: 'long' }), null);
	assert.equal(parseGymTemplate({ discipline: '   ', duration_min: 0 }), null);
	assert.equal(parseGymTemplate({ discipline: '  ', duration_min: -10 }), null);
	assert.deepEqual(parseGymTemplate({ discipline: '  Pilates ', duration_min: 30.9 }), {
		discipline: 'Pilates',
		duration_min: 30
	});
});

test('gymTemplateFromInputs: both empty -> null', () => {
	assert.equal(gymTemplateFromInputs('', null), null);
	assert.equal(gymTemplateFromInputs('   ', null), null);
	assert.equal(gymTemplateFromInputs(null, undefined), null);
	assert.equal(gymTemplateFromInputs('', 0), null);
});

test('gymTemplateFromInputs: discipline only', () => {
	assert.deepEqual(gymTemplateFromInputs('Strength', null), {
		discipline: 'Strength',
		duration_min: null
	});
});

test('gymTemplateFromInputs: duration only', () => {
	assert.deepEqual(gymTemplateFromInputs('', 50), {
		discipline: null,
		duration_min: 50
	});
});

test('gymTemplateFromInputs: both, trims + floors', () => {
	assert.deepEqual(gymTemplateFromInputs('  Yoga  ', 60.7), {
		discipline: 'Yoga',
		duration_min: 60
	});
});

test('workoutDraftFromTemplate: duration -> seconds, title from discipline', () => {
	assert.deepEqual(workoutDraftFromTemplate({ discipline: 'Spin', duration_min: 45 }, 'Sat ride'), {
		title: 'Spin',
		duration_s: 45 * 60
	});
});

test('workoutDraftFromTemplate: title falls back to event title when no discipline', () => {
	assert.deepEqual(
		workoutDraftFromTemplate({ discipline: null, duration_min: 30 }, 'Morning Strength'),
		{ title: 'Morning Strength', duration_s: 30 * 60 }
	);
});

test('workoutDraftFromTemplate: null template + null title -> empty draft', () => {
	assert.deepEqual(workoutDraftFromTemplate(null, null), { title: null, duration_s: null });
	assert.deepEqual(workoutDraftFromTemplate(null, '  '), { title: null, duration_s: null });
});

test('workoutDraftFromSession: title from discipline when present', () => {
	const draft = workoutDraftFromSession({ steps: [], totalS: 0 }, 'Morning Flow', 'Vinyasa yoga');
	assert.equal(draft.title, 'Vinyasa yoga');
});

test('workoutDraftFromSession: title from planTitle when discipline null', () => {
	const draft = workoutDraftFromSession({ steps: [], totalS: 0 }, 'Morning Flow', null);
	assert.equal(draft.title, 'Morning Flow');
});

test('workoutDraftFromSession: duration_s = totalS when > 0', () => {
	const draft = workoutDraftFromSession({ steps: [], totalS: 600 }, 'Flow', 'Yoga');
	assert.equal(draft.duration_s, 600);
});

test('workoutDraftFromSession: duration_s null when totalS 0', () => {
	const draft = workoutDraftFromSession({ steps: [], totalS: 0 }, 'Flow', 'Yoga');
	assert.equal(draft.duration_s, null);
});

test('workoutDraftFromSession: one set per step', () => {
	const expanded = {
		steps: [
			step({ itemId: 'a', movementName: 'Plank', durationS: 30 }),
			step({ itemId: 'b', movementName: 'Bridge', durationS: 45 })
		],
		totalS: 75
	};
	const draft = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
	assert.deepEqual(draft.sets, [
		{ exercise_name: 'Plank', duration_s: 30, reps: null },
		{ exercise_name: 'Bridge', duration_s: 45, reps: null }
	]);
});

test('workoutDraftFromSession: per-side step -> two sets', () => {
	const expanded = {
		steps: [
			step({ itemId: 'a', movementName: 'Lunge', durationS: 30, side: 'left' }),
			step({ itemId: 'a', movementName: 'Lunge', durationS: 30, side: 'right' })
		],
		totalS: 60
	};
	const draft = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
	assert.deepEqual(draft.sets, [
		{ exercise_name: 'Lunge', duration_s: 30, reps: null },
		{ exercise_name: 'Lunge', duration_s: 30, reps: null }
	]);
});

test('workoutDraftFromSession: reps step carries reps, null duration', () => {
	const expanded = {
		steps: [step({ movementName: 'Push-up', kind: 'reps', durationS: null, reps: 12 })],
		totalS: 0
	};
	const draft = workoutDraftFromSession(expanded, 'Flow', 'Yoga');
	assert.deepEqual(draft.sets, [{ exercise_name: 'Push-up', duration_s: null, reps: 12 }]);
});
