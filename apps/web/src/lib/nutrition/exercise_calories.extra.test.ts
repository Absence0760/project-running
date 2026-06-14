import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	exerciseCaloriesForDay,
	gymCalories,
	runCalories,
	GYM_MET,
	KCAL_PER_KG_PER_KM,
} from './exercise_calories';

test('gymCalories — a 45-minute session is 0.75 of an hour of MET burn', () => {
	const expected = GYM_MET * 70 * (2700 / 3600);
	assert.ok(Math.abs(gymCalories(2700, 70) - expected) < 1e-9);
});

test('runCalories — heavier runner over the same distance burns more', () => {
	assert.ok(runCalories(10000, 90) > runCalories(10000, 60));
});

test('exerciseCaloriesForDay — a mixed day sums valid rows and skips null-metric rows', () => {
	const total = exerciseCaloriesForDay({
		runs: [{ distanceM: 8000 }, { distanceM: null }],
		gymSessions: [{ durationS: 2700 }, { durationS: null }],
		weightKg: 65,
	});
	const expected = Math.round(KCAL_PER_KG_PER_KM * 65 * 8 + GYM_MET * 65 * (2700 / 3600));
	assert.equal(total, expected);
});

test('exerciseCaloriesForDay — rounds the day total once, not per activity', () => {
	// Two runs that each carry a .709 fractional tail: rounding once at the end
	// keeps 483, where per-activity rounding (242 + 242) would drift to 484.
	const day = exerciseCaloriesForDay({
		runs: [{ distanceM: 3333 }, { distanceM: 3333 }],
		gymSessions: [],
		weightKg: 70,
	});
	const perActivity = Math.round(runCalories(3333, 70)) + Math.round(runCalories(3333, 70));
	assert.equal(day, 483);
	assert.notEqual(day, perActivity); // 483 vs 484 — proves single-rounding
});

test('exerciseCaloriesForDay — non-physical bodyweight (negative) reads as unknown → 0', () => {
	assert.equal(
		exerciseCaloriesForDay({
			runs: [{ distanceM: 10000 }],
			gymSessions: [{ durationS: 3600 }],
			weightKg: -70,
		}),
		0,
	);
});

test('exerciseCaloriesForDay — many small runs accumulate (not truncated to one)', () => {
	const runs = Array.from({ length: 5 }, () => ({ distanceM: 2000 }));
	const total = exerciseCaloriesForDay({ runs, gymSessions: [], weightKg: 70 });
	assert.equal(total, Math.round(KCAL_PER_KG_PER_KM * 70 * 10)); // 5 × 2 km = 10 km
});
