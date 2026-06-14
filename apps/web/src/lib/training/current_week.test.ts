import { test } from 'node:test';
import assert from 'node:assert/strict';
import { currentWeek, type WeekActivity } from './current_week';

// A Wednesday, local time. 2026-06-10 is a Wednesday.
const WED = new Date(2026, 5, 10, 12, 0, 0);

function isos(week: ReturnType<typeof currentWeek>): string[] {
	return week.days.map((d) => d.iso);
}

test('currentWeek: monday-start window spans Mon..Sun containing now', () => {
	const w = currentWeek([], 'monday', WED);
	assert.deepEqual(isos(w), [
		'2026-06-08', // Mon
		'2026-06-09',
		'2026-06-10', // Wed (now)
		'2026-06-11',
		'2026-06-12',
		'2026-06-13',
		'2026-06-14', // Sun
	]);
	assert.equal(w.days.length, 7);
});

test('currentWeek: sunday-start window spans Sun..Sat containing now', () => {
	const w = currentWeek([], 'sunday', WED);
	assert.deepEqual(isos(w), [
		'2026-06-07', // Sun
		'2026-06-08',
		'2026-06-09',
		'2026-06-10', // Wed (now)
		'2026-06-11',
		'2026-06-12',
		'2026-06-13', // Sat
	]);
});

test('currentWeek: dow is the JS day-of-week for each cell', () => {
	const w = currentWeek([], 'monday', WED);
	assert.deepEqual(
		w.days.map((d) => d.dow),
		[1, 2, 3, 4, 5, 6, 0], // Mon..Sun
	);
});

test('currentWeek: flags today and future days', () => {
	const w = currentWeek([], 'monday', WED);
	const today = w.days.find((d) => d.iso === '2026-06-10');
	assert.ok(today?.isToday);
	assert.equal(today?.isFuture, false);
	assert.equal(w.days.find((d) => d.iso === '2026-06-09')?.isFuture, false); // past
	assert.equal(w.days.find((d) => d.iso === '2026-06-11')?.isFuture, true); // tomorrow
});

test('currentWeek: buckets activities onto their local day and sums distance + count', () => {
	const acts: WeekActivity[] = [
		{ started_at: '2026-06-08T07:00:00', distance_m: 5000 },
		{ started_at: '2026-06-08T18:00:00', distance_m: 3000 }, // same day, second run
		{ started_at: '2026-06-10T06:30:00', distance_m: 10_000 },
	];
	const w = currentWeek(acts, 'monday', WED);
	const mon = w.days.find((d) => d.iso === '2026-06-08')!;
	assert.equal(mon.distanceM, 8000);
	assert.equal(mon.count, 2);
	const wed = w.days.find((d) => d.iso === '2026-06-10')!;
	assert.equal(wed.distanceM, 10_000);
	assert.equal(wed.count, 1);
	assert.equal(w.totalDistanceM, 18_000);
	assert.equal(w.totalCount, 3);
});

test('currentWeek: ignores activities outside the current week', () => {
	const acts: WeekActivity[] = [
		{ started_at: '2026-06-01T07:00:00', distance_m: 5000 }, // last week
		{ started_at: '2026-06-20T07:00:00', distance_m: 5000 }, // next week
		{ started_at: '2026-06-09T07:00:00', distance_m: 4000 }, // in week
	];
	const w = currentWeek(acts, 'monday', WED);
	assert.equal(w.totalDistanceM, 4000);
	assert.equal(w.totalCount, 1);
});

test('currentWeek: ignores zero / negative distance activities', () => {
	const acts: WeekActivity[] = [
		{ started_at: '2026-06-09T07:00:00', distance_m: 0 },
		{ started_at: '2026-06-09T08:00:00', distance_m: -100 },
		{ started_at: '2026-06-09T09:00:00', distance_m: 2000 },
	];
	const w = currentWeek(acts, 'monday', WED);
	assert.equal(w.totalDistanceM, 2000);
	assert.equal(w.totalCount, 1);
});

test('currentWeek: ignores activities with an unparseable timestamp', () => {
	const acts: WeekActivity[] = [
		{ started_at: 'not-a-date', distance_m: 5000 },
		{ started_at: '2026-06-09T07:00:00', distance_m: 3000 },
	];
	const w = currentWeek(acts, 'monday', WED);
	assert.equal(w.totalDistanceM, 3000);
	assert.equal(w.totalCount, 1);
});

test('currentWeek: a late-evening run buckets onto its local day, not UTC', () => {
	// 23:30 local on Tuesday — toISOString() could roll this to Wednesday
	// in a positive-offset zone. The strip must keep it on Tuesday.
	const acts: WeekActivity[] = [{ started_at: '2026-06-09T23:30:00', distance_m: 6000 }];
	const w = currentWeek(acts, 'monday', WED);
	assert.equal(w.days.find((d) => d.iso === '2026-06-09')!.distanceM, 6000);
	assert.equal(w.days.find((d) => d.iso === '2026-06-10')!.distanceM, 0);
});

test('currentWeek: empty input yields a zeroed seven-day week', () => {
	const w = currentWeek([], 'monday', WED);
	assert.equal(w.totalDistanceM, 0);
	assert.equal(w.totalCount, 0);
	assert.ok(w.days.every((d) => d.distanceM === 0 && d.count === 0));
});
