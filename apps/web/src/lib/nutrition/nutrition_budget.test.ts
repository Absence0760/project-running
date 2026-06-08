import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	computeDayBudget,
	macroBudget,
	MACRO_IS_CEILING,
	type MacroKind,
} from './nutrition_budget';
import type { NutritionTargets } from './nutrition_targets';
import type { FoodMacros } from './food_search';

test('macroBudget: under a ceiling macro reports remaining, no flags', () => {
	const b = macroBudget(1400, 2000, 'calories');
	assert.equal(b.remaining, 600);
	assert.equal(b.over, 0);
	assert.equal(b.exceeded, false);
	assert.equal(b.reached, false);
});

test('macroBudget: over a ceiling macro flags exceeded with the overage', () => {
	const b = macroBudget(2300, 2000, 'calories');
	assert.equal(b.remaining, -300);
	assert.equal(b.over, 300);
	assert.equal(b.exceeded, true);
	assert.equal(b.reached, false);
});

test('macroBudget: exactly on a ceiling target is not yet exceeded', () => {
	const b = macroBudget(2000, 2000, 'calories');
	assert.equal(b.remaining, 0);
	assert.equal(b.over, 0);
	assert.equal(b.exceeded, false);
});

test('macroBudget: reaching a goal macro flags reached, never exceeded', () => {
	const b = macroBudget(150, 120, 'protein');
	assert.equal(b.remaining, -30); // signed headroom is still negative
	assert.equal(b.over, 30);
	assert.equal(b.exceeded, false); // protein over target is a win, not a warning
	assert.equal(b.reached, true);
});

test('macroBudget: a goal macro exactly on target counts as reached', () => {
	assert.equal(macroBudget(120, 120, 'protein').reached, true);
});

test('macroBudget: a goal macro under target is neither reached nor exceeded', () => {
	const b = macroBudget(90, 120, 'carbs');
	assert.equal(b.remaining, 30);
	assert.equal(b.reached, false);
	assert.equal(b.exceeded, false);
});

test('macroBudget: no / non-positive target hides the comparison', () => {
	for (const t of [null, undefined, 0, -5]) {
		const b = macroBudget(500, t as number | null, 'calories');
		assert.equal(b.remaining, null);
		assert.equal(b.over, 0);
		assert.equal(b.exceeded, false);
		assert.equal(b.reached, false);
	}
});

test('macroBudget: rounds fractional consumed/target', () => {
	const b = macroBudget(1999.6, 2000.2, 'calories');
	assert.equal(b.remaining, 1); // round(2000.2 - 1999.6) = round(0.6) = 1
	assert.equal(b.over, 0);
});

test('MACRO_IS_CEILING: calories + fat are ceilings, protein + carbs goals', () => {
	const expected: Record<MacroKind, boolean> = {
		calories: true,
		protein: false,
		carbs: false,
		fat: true,
	};
	assert.deepEqual(MACRO_IS_CEILING, expected);
});

const targets: NutritionTargets = {
	calories: 2200,
	baseCalories: 2000,
	exerciseKcal: 200,
	proteinG: 120,
	carbsG: 250,
	fatG: 70,
};

test('computeDayBudget: returns null when no targets', () => {
	const consumed: FoodMacros = { calories: 500, proteinG: 20, carbsG: 40, fatG: 10 };
	assert.equal(computeDayBudget(consumed, null), null);
});

test('computeDayBudget: assembles all four macro budgets', () => {
	const consumed: FoodMacros = { calories: 2400, proteinG: 130, carbsG: 200, fatG: 80 };
	const day = computeDayBudget(consumed, targets)!;
	// calories over a ceiling → exceeded
	assert.equal(day.calories.exceeded, true);
	assert.equal(day.calories.over, 200);
	// protein past its goal → reached, not exceeded
	assert.equal(day.protein.reached, true);
	assert.equal(day.protein.exceeded, false);
	// carbs under → remaining positive
	assert.equal(day.carbs.remaining, 50);
	assert.equal(day.carbs.reached, false);
	// fat over a ceiling → exceeded
	assert.equal(day.fat.exceeded, true);
	assert.equal(day.fat.over, 10);
});
