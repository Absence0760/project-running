import { test } from 'node:test';
import assert from 'node:assert/strict';
import { entriesForSlotOnDay, slotCalorieTrend } from './meal_detail';

function row(started_at: string, meal_slot: string | null, calories: number | null) {
	return { started_at, meal_slot: meal_slot as never, calories };
}

test('entriesForSlotOnDay: keeps only the slot on the day', () => {
	const rows = [
		row('2026-06-05T08:00:00', 'breakfast', 300),
		row('2026-06-05T12:00:00', 'lunch', 600),
		row('2026-06-05T08:30:00', 'breakfast', 150),
		row('2026-06-04T08:00:00', 'breakfast', 999), // wrong day
	];
	const r = entriesForSlotOnDay(rows, '2026-06-05', 'breakfast' as never);
	assert.equal(r.length, 2);
	assert.deepEqual(
		r.map((e) => e.calories),
		[300, 150],
	);
});

test('entriesForSlotOnDay: a null slot folds into snack', () => {
	const rows = [row('2026-06-05T15:00:00', null, 120)];
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'snack' as never).length, 1);
	assert.equal(entriesForSlotOnDay(rows, '2026-06-05', 'lunch' as never).length, 0);
});

test('slotCalorieTrend: returns exactly 7 chronological buckets', () => {
	const t = slotCalorieTrend([], '2026-06-07', 'dinner' as never);
	assert.equal(t.length, 7);
	assert.equal(t[0].date, '2026-06-01');
	assert.equal(t[6].date, '2026-06-07');
	assert.ok(t.every((b) => b.calories === 0));
});

test('slotCalorieTrend: sums the slot per day and zero-fills the rest', () => {
	const rows = [
		row('2026-06-07T19:00:00', 'dinner', 500),
		row('2026-06-07T20:00:00', 'dinner', 200),
		row('2026-06-05T19:00:00', 'dinner', 400),
		row('2026-06-05T12:00:00', 'lunch', 999), // other slot ignored
	];
	const t = slotCalorieTrend(rows, '2026-06-07', 'dinner' as never);
	const byDate = Object.fromEntries(t.map((b) => [b.date, b.calories]));
	assert.equal(byDate['2026-06-07'], 700);
	assert.equal(byDate['2026-06-05'], 400);
	assert.equal(byDate['2026-06-06'], 0);
});

test('slotCalorieTrend: ignores days outside the window', () => {
	const rows = [row('2026-05-30T19:00:00', 'dinner', 1000)];
	const t = slotCalorieTrend(rows, '2026-06-07', 'dinner' as never);
	assert.ok(t.every((b) => b.calories === 0));
});
