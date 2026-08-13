// A DST-bearing zone, set before any Date is constructed. CI runs in UTC,
// where every assertion below holds trivially and proves nothing — the point
// of pinning the zone is that these are the cases decisions.md § 589 records
// as having shipped broken: a day stepped or ended by a fixed 24 hours repeats
// a date on a fall-back and hides the last hour of entries.
process.env.TZ = 'America/New_York';

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	diaryWindow,
	entryTimestampFor,
	isoDateOf,
	stepDiaryDate,
	trailingDates,
} from './diary_day';

// 2026: DST starts Sun 8 Mar (23 h day), ends Sun 1 Nov (25 h day).
const SPRING_FORWARD = '2026-03-08';
const FALL_BACK = '2026-11-01';
const HOUR_MS = 3_600_000;

test('the pinned zone took effect and really does have the transitions', () => {
	assert.equal(Intl.DateTimeFormat().resolvedOptions().timeZone, 'America/New_York');
	assert.equal(new Date(2026, 10, 1, 0).getTimezoneOffset(), 240); // EDT
	assert.equal(new Date(2026, 10, 2, 0).getTimezoneOffset(), 300); // EST
});

test('a fall-back day is 25 hours long and its window ends at the next midnight', () => {
	const w = diaryWindow(FALL_BACK);
	assert.ok(w);
	const span = new Date(w.endIso).getTime() - new Date(w.startIso).getTime();
	assert.equal(span, 25 * HOUR_MS);
	// The bug this replaces: `start + 24 h` lands at 23:00 the same day, so the
	// last hour of entries falls outside the window and the day reads short.
	const buggyEnd = new Date(new Date(w.startIso).getTime() + 24 * HOUR_MS);
	assert.equal(isoDateOf(buggyEnd), FALL_BACK);
	const lateEntry = new Date(2026, 10, 1, 23, 30);
	assert.ok(lateEntry.getTime() >= new Date(w.startIso).getTime());
	assert.ok(lateEntry.getTime() < new Date(w.endIso).getTime());
	assert.ok(lateEntry.getTime() >= buggyEnd.getTime()); // the hour that was lost
});

test('a spring-forward day is 23 hours long and still ends at the next midnight', () => {
	const w = diaryWindow(SPRING_FORWARD);
	assert.ok(w);
	const span = new Date(w.endIso).getTime() - new Date(w.startIso).getTime();
	assert.equal(span, 23 * HOUR_MS);
	assert.equal(new Date(w.endIso).getTime(), new Date(2026, 2, 9).getTime());
});

test('stepping across either transition lands on the neighbouring calendar day', () => {
	const now = new Date(2026, 11, 1);
	assert.equal(stepDiaryDate('2026-11-02', -1, now), FALL_BACK);
	assert.equal(stepDiaryDate(FALL_BACK, -1, now), '2026-10-31');
	assert.equal(stepDiaryDate(FALL_BACK, 1, now), '2026-11-02');
	assert.equal(stepDiaryDate('2026-03-07', 1, now), SPRING_FORWARD);
	assert.equal(stepDiaryDate(SPRING_FORWARD, 1, now), '2026-03-09');
});

test('a trend window spanning a fall-back has seven distinct days, not a repeat', () => {
	const days = trailingDates('2026-11-03', 7);
	assert.equal(days.length, 7);
	assert.equal(new Set(days).size, 7);
	assert.deepEqual(days, [
		'2026-10-28',
		'2026-10-29',
		'2026-10-30',
		'2026-10-31',
		FALL_BACK,
		'2026-11-02',
		'2026-11-03',
	]);
});

test('a back-filled entry on a spring-forward day stays on that day', () => {
	// 02:30 does not exist on 8 Mar in this zone; Date normalises it to 03:30,
	// which is still inside the day the diary is showing.
	const now = new Date(2026, 2, 20, 2, 30, 0);
	const stamp = entryTimestampFor(SPRING_FORWARD, now);
	assert.equal(isoDateOf(new Date(stamp)), SPRING_FORWARD);
	const w = diaryWindow(SPRING_FORWARD);
	assert.ok(w);
	assert.ok(new Date(stamp).getTime() >= new Date(w.startIso).getTime());
	assert.ok(new Date(stamp).getTime() < new Date(w.endIso).getTime());
});

test('a back-filled entry late on a fall-back day stays inside the 25-hour window', () => {
	const now = new Date(2026, 10, 20, 23, 45, 0);
	const stamp = entryTimestampFor(FALL_BACK, now);
	assert.equal(isoDateOf(new Date(stamp)), FALL_BACK);
	const w = diaryWindow(FALL_BACK);
	assert.ok(w);
	assert.ok(new Date(stamp).getTime() < new Date(w.endIso).getTime());
});
