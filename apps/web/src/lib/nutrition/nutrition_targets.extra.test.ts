import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	ageFromDob,
	computeNutritionTargets,
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

test('computeNutritionTargets — an unknown activity level falls back to moderate (no NaN)', () => {
	// `activityLevel` is a raw string off the settings bag; factorFor returns
	// the moderate factor (1.55) for anything it does not recognise, so a stale
	// value yields a valid target identical to the moderate one.
	const moderate = computeNutritionTargets(base)!;
	const unknown = computeNutritionTargets({
		...base,
		activityLevel: 'space_marine' as BodyMetricsInput['activityLevel'],
	})!;
	assert.ok(Number.isFinite(unknown.calories));
	assert.equal(unknown.calories, moderate.calories);
});

test('computeNutritionTargets — carbs floor at 0 when protein + fat exhaust the budget', () => {
	// A very heavy body drives protein (1.8 g/kg) past the calorie budget, so
	// the carbs remainder would go negative — it must clamp to 0, never report a
	// negative gram target.
	const t = computeNutritionTargets({
		weightKg: 500,
		heightCm: 50,
		ageYears: 120,
		sex: 'female',
		activityLevel: 'sedentary',
		goal: 'lose',
	})!;
	assert.ok(t.proteinG * 4 + t.fatG * 9 > t.calories); // budget genuinely exhausted
	assert.equal(t.carbsG, 0);
	assert.ok(t.carbsG >= 0);
});

test('computeNutritionTargets — base goal rounds calories to the nearest 10', () => {
	const t = computeNutritionTargets(base)!;
	assert.equal(t.calories % 10, 0);
});

test('computeNutritionTargets — exerciseKcal is added AFTER the base, not re-rounded to 10', () => {
	// The base is rounded to a multiple of 10; the exercise add is a raw whole
	// number on top, so the final goal can be a non-multiple of 10.
	const t = computeNutritionTargets({ ...base, exerciseKcal: 137 })!;
	assert.equal(t.baseCalories % 10, 0);
	assert.equal(t.exerciseKcal, 137);
	assert.equal(t.calories, t.baseCalories + 137);
});

test('computeNutritionTargets — a fractional exerciseKcal is rounded to whole kcal', () => {
	const t = computeNutritionTargets({ ...base, exerciseKcal: 200.6 })!;
	assert.equal(t.exerciseKcal, 201);
});

test('computeNutritionTargets — non-physical age (>120) and negative metrics return null', () => {
	assert.equal(computeNutritionTargets({ ...base, ageYears: 121 }), null);
	assert.equal(computeNutritionTargets({ ...base, heightCm: -10 }), null);
	assert.equal(computeNutritionTargets({ ...base, ageYears: -1 }), null);
});

test('ageFromDob — same birth-month, earlier day counts the birthday as passed', () => {
	const now = Date.UTC(2026, 5, 4); // 2026-06-04
	assert.equal(ageFromDob('1990-05-03', now), 36); // May already passed
	assert.equal(ageFromDob('1990-07-04', now), 35); // July not yet reached
});

test('ageFromDob — a DOB with a time component still parses by calendar date', () => {
	const now = Date.UTC(2026, 5, 4);
	assert.equal(ageFromDob('1990-06-04T13:45:00Z', now), 36); // birthday today
});

test('ageFromDob — a zero-padded single-digit month/day parses', () => {
	const now = Date.UTC(2026, 0, 15); // 2026-01-15
	assert.equal(ageFromDob('2000-01-09', now), 26);
});

test('ageFromDob — a future DOB yields null (out of range), never a negative age', () => {
	const now = Date.UTC(2026, 5, 4);
	assert.equal(ageFromDob('2030-01-01', now), null);
});
