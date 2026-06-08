import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	runCalories,
	gymCalories,
	exerciseCaloriesForDay,
	KCAL_PER_KG_PER_KM,
	GYM_MET,
} from './exercise_calories';

test('runCalories: 70 kg over 10 km ≈ 1.036·70·10', () => {
	assert.ok(Math.abs(runCalories(10000, 70) - KCAL_PER_KG_PER_KM * 70 * 10) < 1e-9);
});

test('runCalories: scales linearly with distance', () => {
	assert.ok(Math.abs(runCalories(5000, 70) - runCalories(10000, 70) / 2) < 1e-9);
});

test('runCalories: missing or non-physical inputs → 0', () => {
	assert.equal(runCalories(null, 70), 0);
	assert.equal(runCalories(10000, null), 0);
	assert.equal(runCalories(0, 70), 0);
	assert.equal(runCalories(10000, 0), 0);
	assert.equal(runCalories(-100, 70), 0);
	assert.equal(runCalories(10000, -5), 0);
});

test('gymCalories: 70 kg for 1 h ≈ MET·70·1', () => {
	assert.ok(Math.abs(gymCalories(3600, 70) - GYM_MET * 70) < 1e-9);
});

test('gymCalories: half the duration → half the burn', () => {
	assert.ok(Math.abs(gymCalories(1800, 70) - gymCalories(3600, 70) / 2) < 1e-9);
});

test('gymCalories: missing or non-physical inputs → 0', () => {
	assert.equal(gymCalories(null, 70), 0);
	assert.equal(gymCalories(3600, null), 0);
	assert.equal(gymCalories(0, 70), 0);
	assert.equal(gymCalories(3600, 0), 0);
});

test('exerciseCaloriesForDay: sums runs + gym, rounded once', () => {
	const total = exerciseCaloriesForDay({
		runs: [{ distanceM: 10000 }, { distanceM: 5000 }],
		gymSessions: [{ durationS: 3600 }],
		weightKg: 70,
	});
	const expected = Math.round(
		KCAL_PER_KG_PER_KM * 70 * 10 + KCAL_PER_KG_PER_KM * 70 * 5 + GYM_MET * 70,
	);
	assert.equal(total, expected);
});

test('exerciseCaloriesForDay: unknown bodyweight → 0', () => {
	assert.equal(
		exerciseCaloriesForDay({
			runs: [{ distanceM: 10000 }],
			gymSessions: [{ durationS: 3600 }],
			weightKg: null,
		}),
		0,
	);
});

test('exerciseCaloriesForDay: no activities → 0', () => {
	assert.equal(exerciseCaloriesForDay({ runs: [], gymSessions: [], weightKg: 70 }), 0);
});

test('exerciseCaloriesForDay: ignores rows missing their metric', () => {
	assert.equal(
		exerciseCaloriesForDay({
			runs: [{ distanceM: null }],
			gymSessions: [{ durationS: null }],
			weightKg: 70,
		}),
		0,
	);
});
