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

test('percent_cycle: prescription below last top weight -> hold', () => {
	const out = nextPrescription(
		input({
			scheme: 'percent_cycle',
			lastSets: [s(3, 120)],
			params: { percent: 0.7, oneRmKg: 100 },
		}),
	);
	assert.equal(out.suggestedWeightKg, 70);
	assert.equal(out.reason, 'hold');
});

test('percent_cycle: first/bodyweight session (no prior top weight) -> establish_baseline, not hold', () => {
	// Regression: a concrete percentage-of-1RM prescription with no prior top
	// weight (first session, or a bodyweight-logged one) was mislabelled 'hold' —
	// there was nothing to hold. The weight value is unchanged; only the label was.
	const out = nextPrescription(
		input({
			scheme: 'percent_cycle',
			lastSets: [s(3, null)],
			params: { percent: 0.85, oneRmKg: 150 },
		}),
	);
	assert.equal(out.reason, 'establish_baseline');
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

test('linear bodyweight success raises the rep target, never re-prescribes the same count', () => {
	// Regression: a maxed bodyweight linear set used to return the UNCHANGED reps
	// while labelling it "increase_reps" — telling the user to do more reps while
	// prescribing the identical count (the bug double_progression / five_by_five
	// already fixed for their bodyweight paths). Single rep target -> bump it.
	const single = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(10, null), s(10, null)],
			targetRepsMin: 10,
			targetRepsMax: null,
		}),
	);
	assert.equal(single.suggestedWeightKg, null);
	assert.equal(single.reason, 'increase_reps');
	assert.equal(single.suggestedRepsMin, 11);
	assert.equal(single.suggestedRepsMax, null);

	// Rep range -> raise the top of the range, keep the floor.
	const range = nextPrescription(
		input({
			scheme: 'linear',
			lastSets: [s(8, null), s(8, null)],
			targetRepsMin: 6,
			targetRepsMax: 8,
		}),
	);
	assert.equal(range.suggestedWeightKg, null);
	assert.equal(range.reason, 'increase_reps');
	assert.equal(range.suggestedRepsMin, 6);
	assert.equal(range.suggestedRepsMax, 9);
});

test('rpe_autoreg bodyweight below target raises the rep target, never re-prescribes the same count', () => {
	const out = nextPrescription(
		input({
			scheme: 'rpe_autoreg',
			lastSets: [s(8, null, 6), s(8, null, 6.5)],
			targetRepsMin: 8,
			targetRepsMax: null,
			params: { targetRpe: 8 },
		}),
	);
	assert.equal(out.suggestedWeightKg, null);
	assert.equal(out.reason, 'increase_reps');
	assert.equal(out.suggestedRepsMin, 9);
	assert.equal(out.suggestedRepsMax, null);
});

test('double_progression bodyweight at top of range raises the rep ceiling, never reduces it', () => {
	// Regression: a maxed bodyweight range used to collapse to repsMin (12 → 8)
	// while reporting "increase_reps" — a reduction mislabelled as progress. With
	// no load to add, the suggestion must genuinely raise the rep target.
	const out = nextPrescription(
		input({
			scheme: 'double_progression',
			lastSets: [s(12, null), s(12, null)],
			targetRepsMin: 8,
			targetRepsMax: 12,
		}),
	);
	assert.equal(out.suggestedWeightKg, null);
	assert.equal(out.reason, 'increase_reps');
	assert.equal(out.suggestedRepsMax, 13);
	assert.ok((out.suggestedRepsMax ?? 0) > 12, 'must not reduce reps below the maxed range');
});

test('five_by_five bodyweight success raises the rep target, never re-prescribes the same count', () => {
	const out = nextPrescription(
		input({
			scheme: 'five_by_five',
			lastSets: [s(5, null), s(5, null), s(5, null), s(5, null), s(5, null)],
			targetRepsMin: 5,
			targetRepsMax: 5,
		}),
	);
	assert.equal(out.suggestedWeightKg, null);
	assert.equal(out.reason, 'increase_reps');
	assert.equal(out.suggestedRepsMin, 6);
	assert.equal(out.suggestedRepsMax, 6);
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
