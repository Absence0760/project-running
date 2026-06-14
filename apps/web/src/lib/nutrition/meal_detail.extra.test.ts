import assert from 'node:assert/strict';
import { test } from 'node:test';

import { dayKey, entriesForSlotOnDay, slotCalorieTrend } from './meal_detail';

function row(started_at: string, meal_slot: string | null, calories: number | null) {
	return { started_at, meal_slot: meal_slot as never, calories };
}

test('dayKey: returns the UTC YYYY-MM-DD of an ISO timestamp', () => {
	assert.equal(dayKey('2026-06-05T08:00:00Z'), '2026-06-05');
	assert.equal(dayKey('2026-06-05T23:59:59Z'), '2026-06-05');
});

test('entriesForSlotOnDay: a midnight-start entry is in the day (half-open window)', () => {
	// The window is [date 00:00, next-day 00:00). An entry exactly at local
	// midnight belongs to the day; one exactly at the next midnight does not.
	const rows = [
		row('2026-06-05T00:00:00', 'breakfast', 100),
		row('2026-06-06T00:00:00', 'breakfast', 200), // next day's midnight → excluded
	];
	const r = entriesForSlotOnDay(rows, '2026-06-05', 'breakfast' as never);
	assert.equal(r.length, 1);
	assert.equal(r[0].calories, 100);
});

test('entriesForSlotOnDay: a one-second-before-midnight entry is still in the day', () => {
	const rows = [row('2026-06-05T23:59:59', 'dinner', 700)];
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'dinner' as never).length, 1);
});

test('entriesForSlotOnDay: empty rows yields an empty list, never throws', () => {
	assert.deepEqual(entriesForSlotOnDay([], '2026-06-05', 'lunch' as never), []);
});

test('entriesForSlotOnDay: distinct slots on the same day do not bleed together', () => {
	const rows = [
		row('2026-06-05T08:00:00', 'breakfast', 300),
		row('2026-06-05T12:00:00', 'lunch', 600),
		row('2026-06-05T19:00:00', 'dinner', 800),
		row('2026-06-05T15:00:00', null, 120), // → snack
	];
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'breakfast' as never).length, 1);
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'lunch' as never).length, 1);
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'dinner' as never).length, 1);
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'snack' as never).length, 1);
});

test('slotCalorieTrend: honours a custom window length', () => {
	const t = slotCalorieTrend([], '2026-06-07', 'lunch' as never, 3);
	assert.equal(t.length, 3);
	assert.equal(t[0].date, '2026-06-05');
	assert.equal(t[2].date, '2026-06-07');
});

test('slotCalorieTrend: a null-slot entry counts toward the snack trend', () => {
	const rows = [
		row('2026-06-07T15:00:00', null, 250), // null → snack
		row('2026-06-07T15:30:00', 'snack', 100),
	];
	const t = slotCalorieTrend(rows, '2026-06-07', 'snack' as never);
	const today = t.find((b) => b.date === '2026-06-07')!;
	assert.equal(today.calories, 350);
});

test('slotCalorieTrend: a null-calorie entry contributes 0, not NaN', () => {
	const rows = [
		row('2026-06-07T19:00:00', 'dinner', null),
		row('2026-06-07T20:00:00', 'dinner', 400),
	];
	const t = slotCalorieTrend(rows, '2026-06-07', 'dinner' as never);
	const today = t.find((b) => b.date === '2026-06-07')!;
	assert.equal(today.calories, 400);
});

test('slotCalorieTrend: the anchor day is the last (rightmost) bucket', () => {
	const t = slotCalorieTrend([], '2026-06-07', 'breakfast' as never);
	assert.equal(t[t.length - 1].date, '2026-06-07');
});
