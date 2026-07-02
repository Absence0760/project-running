import assert from 'node:assert/strict';
import { test } from 'node:test';

import { weeklyIntakeSummary, weeklyProteinSummary } from './nutrition_week';

test('weeklyIntakeSummary: averages over logged days only, ignores empty days', () => {
	// Three logged days (2000, 2400, 2200), four empty → avg 2200.
	const s = weeklyIntakeSummary([0, 2000, 0, 2400, 0, 2200, 0], 2300);
	assert.equal(s.loggedDays, 3);
	assert.equal(s.avgCalories, 2200);
	assert.equal(s.deltaPerDay, -100); // 2200 − 2300 under goal
});

test('weeklyIntakeSummary: over goal yields a positive delta', () => {
	const s = weeklyIntakeSummary([2600, 2600], 2300);
	assert.equal(s.avgCalories, 2600);
	assert.equal(s.deltaPerDay, 300);
});

test('weeklyIntakeSummary: exactly on goal yields a zero delta', () => {
	const s = weeklyIntakeSummary([2300], 2300);
	assert.equal(s.deltaPerDay, 0);
});

test('weeklyIntakeSummary: no logged days → zero avg, null delta', () => {
	const s = weeklyIntakeSummary([0, 0, 0], 2300);
	assert.equal(s.loggedDays, 0);
	assert.equal(s.avgCalories, 0);
	assert.equal(s.deltaPerDay, null);
});

test('weeklyIntakeSummary: empty input is all-zero, null delta', () => {
	const s = weeklyIntakeSummary([], 2300);
	assert.deepEqual(s, { loggedDays: 0, avgCalories: 0, deltaPerDay: null });
});

test('weeklyIntakeSummary: missing/non-positive target hides the delta', () => {
	for (const t of [null, undefined, 0, -100]) {
		const s = weeklyIntakeSummary([2000, 2200], t as number | null);
		assert.equal(s.avgCalories, 2100);
		assert.equal(s.deltaPerDay, null);
	}
});

test('weeklyIntakeSummary: rounds a fractional average', () => {
	const s = weeklyIntakeSummary([2000, 2001], 2000);
	assert.equal(s.avgCalories, 2001); // round(4001/2) = round(2000.5) = 2001
	assert.equal(s.deltaPerDay, 1);
});

test('weeklyIntakeSummary: a fractional target yields a whole-number delta (twin parity)', () => {
	// Regression: subtracting an un-rounded fractional target produced a long
	// decimal (e.g. -100.40000000000009) that the week chip rendered raw, and
	// diverged from the Dart twin which rounds the target. The delta must be an
	// integer on both platforms.
	const s = weeklyIntakeSummary([2200], 2300.4);
	assert.equal(s.deltaPerDay, -100);
	assert.equal(Number.isInteger(s.deltaPerDay), true);
});

test('weeklyProteinSummary: counts logged days that reached the protein goal', () => {
	// Four logged days (150, 120, 165, 130), three empty. Goal 140 → 2 of 4 met.
	const s = weeklyProteinSummary([0, 150, 0, 120, 165, 0, 130], 140);
	assert.equal(s.loggedDays, 4);
	assert.equal(s.avgProteinG, 141); // round((150+120+165+130)/4) = round(141.25)
	assert.equal(s.daysMetGoal, 2);
});

test('weeklyProteinSummary: hitting the target exactly counts as met (floor, not ceiling)', () => {
	const s = weeklyProteinSummary([140, 139], 140);
	assert.equal(s.daysMetGoal, 1);
});

test('weeklyProteinSummary: all logged days can meet the goal', () => {
	const s = weeklyProteinSummary([150, 160, 170], 140);
	assert.equal(s.loggedDays, 3);
	assert.equal(s.daysMetGoal, 3);
});

test('weeklyProteinSummary: no logged days → zero avg, null daysMetGoal', () => {
	const s = weeklyProteinSummary([0, 0, 0], 140);
	assert.deepEqual(s, { loggedDays: 0, avgProteinG: 0, daysMetGoal: null });
});

test('weeklyProteinSummary: empty input is all-zero, null daysMetGoal', () => {
	const s = weeklyProteinSummary([], 140);
	assert.deepEqual(s, { loggedDays: 0, avgProteinG: 0, daysMetGoal: null });
});

test('weeklyProteinSummary: missing/non-positive target hides daysMetGoal but keeps the average', () => {
	for (const t of [null, undefined, 0, -20]) {
		const s = weeklyProteinSummary([120, 140], t as number | null);
		assert.equal(s.loggedDays, 2);
		assert.equal(s.avgProteinG, 130);
		assert.equal(s.daysMetGoal, null);
	}
});
