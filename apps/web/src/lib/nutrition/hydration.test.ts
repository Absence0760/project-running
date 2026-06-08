import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	hydrationTargetMl,
	hydrationBudget,
	BASELINE_ML_PER_KG,
	DEFAULT_BASELINE_ML,
} from './hydration';

test('hydrationTargetMl: bodyweight baseline at 35 ml/kg, rounded to 50', () => {
	// 70 kg → 2450 ml, already a multiple of 50.
	assert.equal(hydrationTargetMl(70, 0), 70 * BASELINE_ML_PER_KG);
	// 68 kg → 2380 → rounds to 2400.
	assert.equal(hydrationTargetMl(68, 0), 2400);
});

test('hydrationTargetMl: missing/non-physical bodyweight falls back to flat baseline', () => {
	for (const w of [null, undefined, 0, -5]) {
		assert.equal(hydrationTargetMl(w as number | null, 0), DEFAULT_BASELINE_ML);
	}
});

test('hydrationTargetMl: exercise minutes raise the goal (~480 ml/hr)', () => {
	// 70 kg baseline 2450 + 60 min × 8 = 2930 → rounds to 2950.
	assert.ok(hydrationTargetMl(70, 60) > hydrationTargetMl(70, 0));
	assert.equal(hydrationTargetMl(70, 60), 2950);
	// Exercise add applies on the flat baseline too: 2000 + 240 = 2240 → 2250.
	assert.equal(hydrationTargetMl(null, 30), 2250);
});

test('hydrationTargetMl: missing/zero exercise adds nothing', () => {
	for (const e of [null, undefined, 0, -10]) {
		assert.equal(hydrationTargetMl(70, e as number | null), 2450);
	}
});

test('hydrationBudget: under goal reports remaining, not reached', () => {
	const b = hydrationBudget(1000, 2450);
	assert.equal(b.remainingMl, 1450);
	assert.equal(b.reached, false);
	assert.ok(Math.abs(b.fraction - 1000 / 2450) < 1e-9);
});

test('hydrationBudget: reaching the goal flags reached, remaining floors at 0', () => {
	const b = hydrationBudget(2450, 2450);
	assert.equal(b.remainingMl, 0);
	assert.equal(b.reached, true);
	assert.equal(b.fraction, 1);
});

test('hydrationBudget: over the goal stays reached, fraction clamps to 1', () => {
	const b = hydrationBudget(3000, 2450);
	assert.equal(b.remainingMl, 0);
	assert.equal(b.reached, true);
	assert.equal(b.fraction, 1);
});

test('hydrationBudget: a zero target never reads as reached or divides', () => {
	const b = hydrationBudget(0, 0);
	assert.equal(b.reached, false);
	assert.equal(b.fraction, 0);
	assert.equal(b.remainingMl, 0);
});

test('hydrationBudget: rounds and floors negative consumed', () => {
	const b = hydrationBudget(-50, 2000);
	assert.equal(b.consumedMl, 0);
	assert.equal(b.remainingMl, 2000);
});
