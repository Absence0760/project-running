import assert from 'node:assert/strict';
import { test } from 'node:test';

import { weeklyIntakeSummary } from './nutrition_week';

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
