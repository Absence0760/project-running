import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	canStepForward,
	diaryWindow,
	entryTimestampFor,
	isDiaryToday,
	isoDateOf,
	isWithinWindow,
	parseIsoDate,
	resolveDiaryDate,
	stepDiaryDate,
	trailingDates,
	waterDayKey,
} from './diary_day';

const NOW = new Date(2026, 7, 13, 14, 22, 9, 250); // Thu 13 Aug 2026, local

test('isoDateOf zero-pads month and day', () => {
	assert.equal(isoDateOf(new Date(2026, 0, 3)), '2026-01-03');
	assert.equal(isoDateOf(new Date(2026, 11, 31)), '2026-12-31');
});

test('parseIsoDate accepts a real calendar date', () => {
	assert.deepEqual(parseIsoDate('2026-08-13'), { y: 2026, m: 8, d: 13 });
	assert.deepEqual(parseIsoDate('2024-02-29'), { y: 2024, m: 2, d: 29 });
});

test('parseIsoDate rejects anything that is not a real zero-padded calendar date', () => {
	for (const bad of [
		null,
		undefined,
		'',
		'today',
		'2026-8-3', // unpadded
		'2026-13-01', // month out of range
		'2026-00-10',
		'2026-02-30', // Date would normalise this into March
		'2026-02-29', // 2026 is not a leap year
		'0026-02-01', // two-digit years mean 1900+y to Date
		'2026-08-13T00:00:00',
		' 2026-08-13',
	]) {
		assert.equal(parseIsoDate(bad as string | null), null, `expected null for ${String(bad)}`);
	}
});

test('resolveDiaryDate keeps a real past date and falls back to today otherwise', () => {
	assert.equal(resolveDiaryDate('2026-08-10', NOW), '2026-08-10');
	assert.equal(resolveDiaryDate('2026-08-13', NOW), '2026-08-13');
	assert.equal(resolveDiaryDate(null, NOW), '2026-08-13');
	assert.equal(resolveDiaryDate('nonsense', NOW), '2026-08-13');
	assert.equal(resolveDiaryDate('2026-02-30', NOW), '2026-08-13');
});

test('resolveDiaryDate clamps a future date to today — nobody can have eaten tomorrow', () => {
	assert.equal(resolveDiaryDate('2026-08-14', NOW), '2026-08-13');
	assert.equal(resolveDiaryDate('2099-01-01', NOW), '2026-08-13');
});

test('stepDiaryDate walks the calendar across month, year and leap-day edges', () => {
	assert.equal(stepDiaryDate('2026-08-01', -1, NOW), '2026-07-31');
	assert.equal(stepDiaryDate('2026-03-01', -1, new Date(2026, 7, 13)), '2026-02-28');
	assert.equal(stepDiaryDate('2024-03-01', -1, new Date(2026, 7, 13)), '2024-02-29');
	assert.equal(stepDiaryDate('2026-01-01', -1, NOW), '2025-12-31');
	assert.equal(stepDiaryDate('2025-12-31', 1, NOW), '2026-01-01');
	assert.equal(stepDiaryDate('2026-08-01', -7, NOW), '2026-07-25');
});

test('stepDiaryDate never steps past today', () => {
	assert.equal(stepDiaryDate('2026-08-13', 1, NOW), '2026-08-13');
	assert.equal(stepDiaryDate('2026-08-12', 5, NOW), '2026-08-13');
	assert.equal(stepDiaryDate('2026-08-12', 1, NOW), '2026-08-13');
});

test('stepDiaryDate resolves an unparseable day to today', () => {
	assert.equal(stepDiaryDate('rubbish', -1, NOW), '2026-08-13');
});

test('isDiaryToday and canStepForward agree on the boundary', () => {
	assert.equal(isDiaryToday('2026-08-13', NOW), true);
	assert.equal(isDiaryToday('2026-08-12', NOW), false);
	assert.equal(canStepForward('2026-08-13', NOW), false);
	assert.equal(canStepForward('2026-08-12', NOW), true);
});

test('diaryWindow spans local midnight to the next local midnight', () => {
	const w = diaryWindow('2026-08-13');
	assert.ok(w);
	assert.equal(new Date(w.startIso).getTime(), new Date(2026, 7, 13).getTime());
	assert.equal(new Date(w.endIso).getTime(), new Date(2026, 7, 14).getTime());
});

test('diaryWindow of n days starts n-1 days earlier and keeps the same end', () => {
	const w = diaryWindow('2026-08-13', 7);
	assert.ok(w);
	assert.equal(new Date(w.startIso).getTime(), new Date(2026, 7, 7).getTime());
	assert.equal(new Date(w.endIso).getTime(), new Date(2026, 7, 14).getTime());
});

test('diaryWindow fails closed on an unusable day or a non-positive span', () => {
	assert.equal(diaryWindow('2026-02-30'), null);
	assert.equal(diaryWindow('nope'), null);
	assert.equal(diaryWindow('2026-08-13', 0), null);
});

test('isWithinWindow includes the start instant and excludes the end instant', () => {
	const w = diaryWindow('2026-08-13');
	assert.ok(w);
	assert.equal(isWithinWindow(w.startIso, w), true);
	assert.equal(isWithinWindow(w.endIso, w), false);
	assert.equal(isWithinWindow(new Date(2026, 7, 13, 23, 59, 59).toISOString(), w), true);
	assert.equal(isWithinWindow(new Date(2026, 7, 12, 23, 59, 59).toISOString(), w), false);
});

test('isWithinWindow compares instants, not strings — the boundary row is kept', () => {
	const w = diaryWindow('2026-08-13');
	assert.ok(w);
	// Postgres' rendering of the very same moment the window starts at.
	const pgStyle = new Date(w.startIso).toISOString().replace('Z', '+00:00');
	assert.equal(isWithinWindow(pgStyle, w), true);
	// The string compare this replaces drops it, because '+' sorts below '.'.
	assert.equal(pgStyle >= w.startIso, false);
});

test('isWithinWindow rejects a missing or unparseable timestamp', () => {
	const w = diaryWindow('2026-08-13');
	assert.ok(w);
	assert.equal(isWithinWindow(null, w), false);
	assert.equal(isWithinWindow(undefined, w), false);
	assert.equal(isWithinWindow('', w), false);
	assert.equal(isWithinWindow('not a time', w), false);
});

test('trailingDates returns n dates oldest first, ending on the day itself', () => {
	assert.deepEqual(trailingDates('2026-08-13', 7), [
		'2026-08-07',
		'2026-08-08',
		'2026-08-09',
		'2026-08-10',
		'2026-08-11',
		'2026-08-12',
		'2026-08-13',
	]);
	assert.deepEqual(trailingDates('2026-03-02', 3), ['2026-02-28', '2026-03-01', '2026-03-02']);
	assert.deepEqual(trailingDates('2026-08-13', 1), ['2026-08-13']);
});

test('trailingDates buckets match isoDateOf, so an entry lands in its own day', () => {
	const days = trailingDates('2026-08-13', 7);
	const entryAt = new Date(2026, 7, 9, 23, 30);
	assert.ok(days.includes(isoDateOf(entryAt)));
});

test('trailingDates is empty for an unusable day or a non-positive count', () => {
	assert.deepEqual(trailingDates('rubbish', 7), []);
	assert.deepEqual(trailingDates('2026-08-13', 0), []);
});

test('entryTimestampFor on today is exactly now', () => {
	assert.equal(entryTimestampFor('2026-08-13', NOW), NOW.toISOString());
	assert.equal(entryTimestampFor('rubbish', NOW), NOW.toISOString());
});

test('entryTimestampFor on a past day keeps the clock time and lands inside that day', () => {
	const stamp = entryTimestampFor('2026-08-10', NOW);
	const at = new Date(stamp);
	assert.equal(isoDateOf(at), '2026-08-10');
	assert.equal(at.getHours(), 14);
	assert.equal(at.getMinutes(), 22);
	const w = diaryWindow('2026-08-10');
	assert.ok(w);
	assert.ok(at.getTime() >= new Date(w.startIso).getTime());
	assert.ok(at.getTime() < new Date(w.endIso).getTime());
});

test('entryTimestampFor is monotonic across a back-filling session', () => {
	const first = entryTimestampFor('2026-08-10', new Date(2026, 7, 13, 14, 22, 9));
	const second = entryTimestampFor('2026-08-10', new Date(2026, 7, 13, 14, 22, 11));
	assert.ok(new Date(second).getTime() > new Date(first).getTime());
});

test('waterDayKey keeps the shipped unpadded shape so no stored count is orphaned', () => {
	// The key format that shipped: `${getFullYear()}-${getMonth() + 1}-${getDate()}`.
	const d = new Date(2026, 7, 3);
	const shipped = `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`;
	assert.equal(waterDayKey('2026-08-03'), shipped);
	assert.equal(waterDayKey('2026-08-03'), '2026-8-3');
	assert.equal(waterDayKey('2026-12-31'), '2026-12-31');
});

test('waterDayKey passes an unusable day through rather than colliding on a fallback', () => {
	assert.equal(waterDayKey('rubbish'), 'rubbish');
});
