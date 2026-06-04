import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	ACTIVITY_LEVELS,
	GOAL_KCAL_DELTA,
	MIN_CALORIE_TARGET,
	ageFromDob,
	computeNutritionTargets,
	mifflinStJeorBmr,
	type BodyMetricsInput,
} from './nutrition_targets';

const base: BodyMetricsInput = {
	weightKg: 70,
	heightCm: 178,
	ageYears: 35,
	sex: 'male',
	activityLevel: 'moderate',
	goal: 'maintain',
};

test('mifflinStJeorBmr — male offset is +5', () => {
	// 10*70 + 6.25*178 - 5*35 + 5 = 700 + 1112.5 - 175 + 5 = 1642.5
	assert.equal(mifflinStJeorBmr(70, 178, 35, 'male'), 1642.5);
});

test('mifflinStJeorBmr — female offset is -161', () => {
	assert.equal(mifflinStJeorBmr(70, 178, 35, 'female'), 1642.5 - 5 - 161);
});

test('mifflinStJeorBmr — neutral offset (-78) for nonbinary / withheld / unknown', () => {
	const neutral = 10 * 70 + 6.25 * 178 - 5 * 35 - 78;
	assert.equal(mifflinStJeorBmr(70, 178, 35, 'nonbinary'), neutral);
	assert.equal(mifflinStJeorBmr(70, 178, 35, 'prefer_not_to_say'), neutral);
	assert.equal(mifflinStJeorBmr(70, 178, 35, null), neutral);
});

test('computeNutritionTargets — applies the moderate activity factor', () => {
	const t = computeNutritionTargets(base)!;
	// 1642.5 * 1.55 = 2545.875 → round/10 = 2550
	assert.equal(t.calories, 2550);
});

test('computeNutritionTargets — protein is 1.8 g/kg, fat is 30% of kcal', () => {
	const t = computeNutritionTargets(base)!;
	assert.equal(t.proteinG, Math.round(1.8 * 70)); // 126
	assert.equal(t.fatG, Math.round((0.3 * 2550) / 9)); // 85
});

test('computeNutritionTargets — carbs fill the remaining calorie budget', () => {
	const t = computeNutritionTargets(base)!;
	const remaining = 2550 - t.proteinG * 4 - t.fatG * 9;
	assert.equal(t.carbsG, Math.round(remaining / 4));
});

test('computeNutritionTargets — goal delta lowers/raises calories', () => {
	const lose = computeNutritionTargets({ ...base, goal: 'lose' })!;
	const gain = computeNutritionTargets({ ...base, goal: 'gain' })!;
	assert.equal(lose.calories, 2550 + GOAL_KCAL_DELTA.lose);
	assert.equal(gain.calories, 2550 + GOAL_KCAL_DELTA.gain);
});

test('computeNutritionTargets — sedentary < very_active for the same body', () => {
	const sed = computeNutritionTargets({ ...base, activityLevel: 'sedentary' })!;
	const va = computeNutritionTargets({ ...base, activityLevel: 'very_active' })!;
	assert.ok(va.calories > sed.calories);
});

test('computeNutritionTargets — calorie floor protects against a too-low default', () => {
	const t = computeNutritionTargets({
		weightKg: 40,
		heightCm: 150,
		ageYears: 80,
		sex: 'female',
		activityLevel: 'sedentary',
		goal: 'lose',
	})!;
	assert.equal(t.calories, MIN_CALORIE_TARGET);
});

test('computeNutritionTargets — null on missing or non-physical metrics', () => {
	assert.equal(computeNutritionTargets({ ...base, weightKg: null }), null);
	assert.equal(computeNutritionTargets({ ...base, heightCm: null }), null);
	assert.equal(computeNutritionTargets({ ...base, ageYears: null }), null);
	assert.equal(computeNutritionTargets({ ...base, weightKg: 0 }), null);
	assert.equal(computeNutritionTargets({ ...base, weightKg: 600 }), null);
	assert.equal(computeNutritionTargets({ ...base, heightCm: 400 }), null);
});

test('ageFromDob — whole-year age, decremented before the birthday', () => {
	const now = Date.UTC(2026, 5, 4); // 2026-06-04
	assert.equal(ageFromDob('1990-06-04', now), 36); // birthday today
	assert.equal(ageFromDob('1990-06-05', now), 35); // birthday tomorrow
	assert.equal(ageFromDob('1990-06-03', now), 36); // birthday yesterday
});

test('ageFromDob — null on missing / malformed / out-of-range', () => {
	const now = Date.UTC(2026, 5, 4);
	assert.equal(ageFromDob(null, now), null);
	assert.equal(ageFromDob('', now), null);
	assert.equal(ageFromDob('not-a-date', now), null);
	assert.equal(ageFromDob('1850-01-01', now), null); // > 120
});

test('ACTIVITY_LEVELS is ordered least → most active with rising factors', () => {
	for (let i = 1; i < ACTIVITY_LEVELS.length; i++) {
		assert.ok(ACTIVITY_LEVELS[i].factor > ACTIVITY_LEVELS[i - 1].factor);
	}
});
