import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { nextPrescription, type ProgressionSetLike, type ProgressionInput } from './gym_progression';

function s(reps: number | null, weight_kg: number | null, rpe: number | null = null): ProgressionSetLike {
	return { reps, weight_kg, rpe };
}

function input(over: Partial<ProgressionInput>): ProgressionInput {
	return {
		scheme: 'none',
		lastSets: [],
		targetRepsMin: null,
		targetRepsMax: null,
		params: null,
		...over,
	};
}

test('none scheme suggests nothing', () => {
	const out = nextPrescription(input({ scheme: 'none', lastSets: [s(5, 100)] }));
	assert.deepEqual(out, {
		suggestedWeightKg: null,
		suggestedRepsMin: null,
		suggestedRepsMax: null,
		reason: 'none',
	});
});

test('linear: all sets hit top reps -> +2.5kg increase_weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(5, 100), s(5, 100), s(5, 100)],
			targetRepsMin: 5,
			targetRepsMax: 5,
		}),
	);
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 102.5);
});

test('linear: a missed set -> hold at the same weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(5, 100), s(4, 100), s(5, 100)],
			targetRepsMin: 5,
			targetRepsMax: 5,
		}),
	);
	assert.equal(out.reason, 'hold');
	assert.equal(out.suggestedWeightKg, 100);
});

test('double_progression: below repsMax -> increase_reps, same weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'double_progression',
			lastSets: [s(8, 60), s(8, 60), s(8, 60)],
			targetRepsMin: 8,
			targetRepsMax: 12,
		}),
	);
	assert.equal(out.reason, 'increase_reps');
	assert.equal(out.suggestedWeightKg, 60);
	assert.equal(out.suggestedRepsMax, 12);
});

test('double_progression: at repsMax -> +2.5kg, reset reps to repsMin', () => {
	const out = nextPrescription(
		input({
			scheme: 'double_progression',
			lastSets: [s(12, 60), s(12, 60), s(12, 60)],
			targetRepsMin: 8,
			targetRepsMax: 12,
		}),
	);
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 62.5);
	assert.equal(out.suggestedRepsMin, 8);
	assert.equal(out.suggestedRepsMax, 8);
});

test('five_by_five: 5x5 success -> +2.5kg', () => {
	const out = nextPrescription(
		input({
			scheme: 'five_by_five',
			lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(5, 80)],
			targetRepsMin: 5,
			targetRepsMax: 5,
		}),
	);
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 82.5);
});

test('five_by_five: one rep short -> hold', () => {
	const out = nextPrescription(
		input({
			scheme: 'five_by_five',
			lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(4, 80)],
			targetRepsMin: 5,
			targetRepsMax: 5,
		}),
	);
	assert.equal(out.reason, 'hold');
	assert.equal(out.suggestedWeightKg, 80);
});

test('five_by_five: 3 consecutive misses -> deload', () => {
	const out = nextPrescription(
		input({
			scheme: 'five_by_five',
			lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(3, 80)],
			targetRepsMin: 5,
			targetRepsMax: 5,
			params: { consecutiveMisses: 3 },
		}),
	);
	assert.equal(out.reason, 'deload');
	assert.equal(out.suggestedWeightKg, 72);
});

test('percent_cycle: prescribes params.percent * oneRmKg', () => {
	const out = nextPrescription(
		input({
			scheme: 'percent_cycle',
			lastSets: [s(3, 120)],
			params: { percent: 0.85, oneRmKg: 150 },
		}),
	);
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 127.5);
});

test('rpe_autoreg: achieved RPE below target -> increase_weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'rpe_autoreg',
			lastSets: [s(5, 100, 7), s(5, 100, 7.5)],
			params: { targetRpe: 8 },
		}),
	);
	assert.equal(out.reason, 'increase_weight');
	assert.equal(out.suggestedWeightKg, 102.5);
});

test('rpe_autoreg: achieved RPE above target -> hold', () => {
	const out = nextPrescription(
		input({
			scheme: 'rpe_autoreg',
			lastSets: [s(5, 100, 9), s(5, 100, 9.5)],
			params: { targetRpe: 8 },
		}),
	);
	assert.equal(out.reason, 'hold');
	assert.equal(out.suggestedWeightKg, 100);
});

test('empty lastSets -> hold (or none for none scheme)', () => {
	const held = nextPrescription(
		input({ scheme: 'linear', lastSets: [], targetRepsMin: 5, targetRepsMax: 5 }),
	);
	assert.equal(held.reason, 'hold');
	const noneOut = nextPrescription(input({ scheme: 'none', lastSets: [] }));
	assert.equal(noneOut.reason, 'none');
});

test('null weights (bodyweight) -> reps-only suggestion, never a weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(10, null), s(10, null), s(10, null)],
			targetRepsMin: 10,
			targetRepsMax: 10,
		}),
	);
	assert.equal(out.suggestedWeightKg, null);
	assert.equal(out.reason, 'increase_reps');
});

test('negative/zero params never suggest a negative weight', () => {
	const out = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(5, 100), s(5, 100)],
			targetRepsMin: 5,
			targetRepsMax: 5,
			params: { incrementKg: -200 },
		}),
	);
	assert.ok(out.suggestedWeightKg != null && out.suggestedWeightKg > 0);
});
