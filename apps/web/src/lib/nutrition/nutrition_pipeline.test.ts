import assert from 'node:assert/strict';
import { test } from 'node:test';

import { computeNutritionTargets, type BodyMetricsInput } from './nutrition_targets';
import { exerciseCaloriesForDay } from './exercise_calories';
import { sumMacros, ringFraction, type MacroRow } from './nutrition_totals';
import { computeDayBudget } from './nutrition_budget';
import { hydrationTargetMl, hydrationBudget } from './hydration';
import { weeklyIntakeSummary } from './nutrition_week';

/**
 * These pin the COMPOSITION the /nutrition page performs across the pure
 * helpers (each helper is unit-tested in isolation elsewhere). They guard the
 * seams: a logged day's macro sum feeding the day budget, the dynamic-TDEE
 * goal feeding the ring fraction, and the exercise add raising both the goal
 * and the hydration target together — the arithmetic that would silently
 * regress if one helper's contract shifted under another.
 */

const body: BodyMetricsInput = {
	weightKg: 70,
	heightCm: 178,
	ageYears: 35,
	sex: 'male',
	activityLevel: 'moderate',
	goal: 'maintain',
};

const dayRows: MacroRow[] = [
	{ calories: 412, protein_g: 12, carbs_g: 58, fat_g: 8, meal_slot: 'breakfast' },
	{ calories: 640, protein_g: 48, carbs_g: 52, fat_g: 20, meal_slot: 'lunch' },
	{ calories: 900, protein_g: 50, carbs_g: 80, fat_g: 30, meal_slot: 'dinner' },
];

test('pipeline: summed macros + base targets produce a coherent under-budget day', () => {
	const consumed = sumMacros(dayRows); // 1952 kcal
	const targets = computeNutritionTargets(body)!; // 2550 kcal base
	const budget = computeDayBudget(consumed, targets)!;

	assert.equal(consumed.calories, 1952);
	// Under the calorie ceiling → remaining positive, not exceeded.
	assert.equal(budget.calories.exceeded, false);
	assert.equal(budget.calories.remaining, targets.calories - consumed.calories);
	// The calorie ring fraction matches consumed/target, clamped.
	const frac = ringFraction(consumed.calories, targets.calories);
	assert.ok(Math.abs(frac! - consumed.calories / targets.calories) < 1e-9);
});

test('pipeline: a logged run raises the goal AND the hydration target together', () => {
	const exerciseKcal = exerciseCaloriesForDay({
		runs: [{ distanceM: 12000 }],
		gymSessions: [],
		weightKg: body.weightKg,
	});
	assert.ok(exerciseKcal > 0);

	const baseTargets = computeNutritionTargets(body)!;
	const dynamicTargets = computeNutritionTargets({ ...body, exerciseKcal })!;
	// Calorie goal rises by exactly the measured burn.
	assert.equal(dynamicTargets.calories, baseTargets.calories + exerciseKcal);
	assert.equal(dynamicTargets.baseCalories, baseTargets.calories);

	// 60 min of exercise raises the water target above the no-exercise figure.
	const restTarget = hydrationTargetMl(body.weightKg, 0);
	const activeTarget = hydrationTargetMl(body.weightKg, 60);
	assert.ok(activeTarget > restTarget);
	const hb = hydrationBudget(1000, activeTarget);
	assert.equal(hb.remainingMl, activeTarget - 1000);
});

test('pipeline: an over-eaten day flags the calorie ceiling while protein stays a reached goal', () => {
	const heavy: MacroRow[] = [
		{ calories: 3200, protein_g: 200, carbs_g: 300, fat_g: 120, meal_slot: 'dinner' },
	];
	const consumed = sumMacros(heavy);
	const targets = computeNutritionTargets(body)!;
	const budget = computeDayBudget(consumed, targets)!;

	assert.equal(budget.calories.exceeded, true); // over the kcal ceiling
	assert.ok(budget.calories.over > 0);
	assert.equal(budget.protein.reached, true); // protein floor cleared
	assert.equal(budget.protein.exceeded, false); // not a warning
	assert.equal(budget.fat.exceeded, true); // fat is a ceiling too
});

test('pipeline: the week summary averages logged days against the same dynamic goal', () => {
	const targets = computeNutritionTargets({ ...body, exerciseKcal: 300 })!;
	// Five logged days near the goal, two unlogged (0) — averaged over logged only.
	const week = [0, targets.calories, targets.calories, 0, targets.calories - 200, targets.calories + 200, 0];
	const summary = weeklyIntakeSummary(week, targets.calories);
	assert.equal(summary.loggedDays, 4);
	// avg of the four logged days vs goal → small signed delta.
	const loggedAvg = Math.round(
		week.filter((c) => c > 0).reduce((s, c) => s + c, 0) / 4,
	);
	assert.equal(summary.avgCalories, loggedAvg);
	assert.equal(summary.deltaPerDay, loggedAvg - targets.calories);
});

test('pipeline: with no body metrics the goal hides but hydration still has a target', () => {
	// Anti-clutter contract: no targets → rings hidden (null budget), but the
	// water tracker must still work off the flat 2 L baseline.
	const targets = computeNutritionTargets({ ...body, weightKg: null });
	assert.equal(targets, null);
	assert.equal(computeDayBudget(sumMacros(dayRows), targets), null);

	const waterTarget = hydrationTargetMl(null, 0);
	assert.equal(waterTarget, 2000);
	assert.equal(hydrationBudget(0, waterTarget).remainingMl, 2000);
});
