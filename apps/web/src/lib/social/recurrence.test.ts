import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	expandInstances,
	nextInstanceAfter,
	describeRecurrence,
} from './recurrence';
import type { Event } from '../types';

// Build a partial Event with just enough fields for recurrence math.
// Casts the rest to `unknown as Event` — the recurrence helpers only
// touch `starts_at`, `recurrence_freq`, `recurrence_byday`,
// `recurrence_until`, and `recurrence_count`.
function ev(partial: Partial<Event>): Event {
	return partial as unknown as Event;
}

test('expandInstances — non-recurring event returns its single instance when in window', () => {
	const e = ev({ starts_at: '2026-04-10T08:00:00Z' });
	const inWindow = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	assert.equal(inWindow.length, 1);

	const outOfWindow = expandInstances(
		e,
		new Date('2026-05-01T00:00:00Z'),
		new Date('2026-05-31T23:59:59Z'),
	);
	assert.equal(outOfWindow.length, 0);
});

test('expandInstances — weekly event produces multiple instances in a month', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	// Apr 1 (Wed), Apr 8, Apr 15, Apr 22, Apr 29 → 5 instances. The Apr 1
	// instance used to slip on UTC hosts because the loop compared a
	// midnight cursor against starts_at's 08:00 time-of-day — the fix
	// separates calendar-day and stamped-time comparisons so the first-
	// week instance is no longer silently dropped.
	assert.equal(out.length, 5);
});

test('expandInstances — weekly emits the starts_at week even when start has a non-midnight time-of-day', () => {
	// Regression: this used to drop the Tuesday instance because the
	// midnight cursor for the start day was < starts_at (Tuesday 19:00),
	// so the entire first week's matching day was filtered out before
	// time-of-day was stamped.
	const e = ev({
		starts_at: '2026-04-07T19:00:00Z', // Tue
		recurrence_freq: 'weekly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	const firstDay = out[0]?.toISOString().slice(0, 10);
	assert.equal(firstDay, '2026-04-07', `first instance should be Apr 7, got ${firstDay}`);
});

test('expandInstances — biweekly produces fewer instances than weekly in the same window', () => {
	const start = '2026-04-01T08:00:00Z';
	const weekly = ev({ starts_at: start, recurrence_freq: 'weekly' });
	const biweekly = ev({ starts_at: start, recurrence_freq: 'biweekly' });
	const from = new Date('2026-04-01T00:00:00Z');
	const to = new Date('2026-04-30T23:59:59Z');
	const w = expandInstances(weekly, from, to);
	const b = expandInstances(biweekly, from, to);
	assert.ok(b.length < w.length, `biweekly ${b.length} should be fewer than weekly ${w.length}`);
});

test('expandInstances — biweekly with a weekend-crossing byday anchors on Monday', () => {
	// Twin-parity contract with apps/mobile_android/lib/recurrence.dart: the week
	// is anchored on Monday, so a biweekly [SA, SU] event starting on a Saturday
	// fires Sat+Sun on the start week, skips a week, then Sat+Sun again. A Sunday
	// anchor (the old Dart behaviour) split the Sunday into the next week and
	// produced a different set of dates. CI runs in UTC; the start time is given
	// in Z so getDay() reads Saturday.
	const e = ev({
		starts_at: '2026-05-02T09:00:00Z', // Sat
		recurrence_freq: 'biweekly',
		recurrence_byday: ['SA', 'SU'],
	});
	const out = expandInstances(
		e,
		new Date('2026-05-01T00:00:00Z'),
		new Date('2026-05-31T23:59:59Z'),
	);
	const dates = out.map((d) => d.toISOString().slice(0, 10));
	assert.deepEqual(dates, [
		'2026-05-02',
		'2026-05-03',
		'2026-05-16',
		'2026-05-17',
		'2026-05-30',
		'2026-05-31',
	]);
});

test('expandInstances — recurrence_count caps the number of instances', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_count: 3,
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 3);
});

test('expandInstances — recurrence_until stops the expansion', () => {
	const until = '2026-04-22T08:00:00Z';
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_until: until,
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.ok(out.length > 0);
	const untilMs = new Date(until).getTime();
	for (const d of out) {
		assert.ok(d.getTime() <= untilMs, `instance ${d.toISOString()} after until`);
	}
});

test('expandInstances — monthly produces one instance per month in window', () => {
	const e = ev({
		starts_at: '2026-04-05T10:00:00Z',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-06-30T23:59:59Z'),
	);
	assert.equal(out.length, 3);
});

test('expandInstances — day-31 monthly clamps to month-end (no overflow)', () => {
	// Jan-31 monthly must land on Feb-28 (2026 is not a leap year), Mar-31,
	// Apr-30 — never roll into the following month. A naive setMonth(+1) on a
	// Jan-31 cursor overflows to March 3. Local-time start (no Z) so the
	// day-of-month is unambiguous in the UTC CI runner.
	const e = ev({
		starts_at: '2026-01-31T09:00:00',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2026-01-01T00:00:00'),
		new Date('2026-04-30T23:59:59'),
	);
	const dates = out.map((d) => `${d.getFullYear()}-${d.getMonth() + 1}-${d.getDate()}`);
	assert.deepEqual(dates, ['2026-1-31', '2026-2-28', '2026-3-31', '2026-4-30']);
	// Each instance re-anchors on the original day (March is back to 31), so a
	// February clamp doesn't permanently shrink the day-of-month.
	for (const d of out) {
		assert.equal(d.getHours(), 9);
		assert.equal(d.getMinutes(), 0);
	}
});

test('expandInstances — day-31 monthly hits Feb-29 in a leap year', () => {
	const e = ev({
		starts_at: '2024-01-31T08:00:00',
		recurrence_freq: 'monthly',
	});
	const out = expandInstances(
		e,
		new Date('2024-02-01T00:00:00'),
		new Date('2024-02-29T23:59:59'),
	);
	assert.equal(out.length, 1);
	assert.equal(out[0].getMonth(), 1); // February
	assert.equal(out[0].getDate(), 29);
});

test('expandInstances — instances do not precede the original starts_at', () => {
	const startsAt = '2026-04-08T09:00:00Z';
	const e = ev({ starts_at: startsAt, recurrence_freq: 'weekly' });
	const out = expandInstances(
		e,
		new Date('2026-04-01T00:00:00Z'),
		new Date('2026-04-30T23:59:59Z'),
	);
	const startMs = new Date(startsAt).getTime();
	for (const d of out) {
		assert.ok(d.getTime() >= startMs, `instance ${d.toISOString()} precedes starts_at`);
	}
});

test('expandInstances — monthly with recurrence_count caps instances', () => {
	const e = ev({
		starts_at: '2026-01-01T09:00:00Z',
		recurrence_freq: 'monthly',
		recurrence_count: 4,
	});
	const out = expandInstances(
		e,
		new Date('2026-01-01T00:00:00Z'),
		new Date('2026-12-31T23:59:59Z'),
	);
	assert.equal(out.length, 4);
});

test('nextInstanceAfter — returns the next instance after a cutoff', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
	});
	const next = nextInstanceAfter(e, new Date('2026-04-10T00:00:00Z'));
	assert.ok(next != null);
	// The first weekly instance after Apr 10 should be Apr 15 (Wed).
	assert.equal(next!.toISOString().slice(0, 10), '2026-04-15');
});

test('nextInstanceAfter — returns null past recurrence_until', () => {
	const e = ev({
		starts_at: '2026-04-01T08:00:00Z',
		recurrence_freq: 'weekly',
		recurrence_until: '2026-04-30T23:59:59Z',
	});
	const next = nextInstanceAfter(e, new Date('2026-05-01T00:00:00Z'));
	assert.equal(next, null);
});

test('describeRecurrence — null freq is "One-off event"', () => {
	assert.equal(describeRecurrence(null, []), 'One-off event');
	assert.equal(describeRecurrence(null, null), 'One-off event');
});

test('describeRecurrence — monthly is "Repeats monthly"', () => {
	assert.equal(describeRecurrence('monthly', null), 'Repeats monthly');
	assert.equal(describeRecurrence('monthly', ['MO']), 'Repeats monthly');
});

test('describeRecurrence — weekly with byday lists days in ISO order', () => {
	// Even when input order is shuffled, output order is MO,TU,...,SU.
	assert.equal(describeRecurrence('weekly', ['WE', 'MO']), 'Every week · Mon, Wed');
});

test('describeRecurrence — biweekly without byday is bare', () => {
	assert.equal(describeRecurrence('biweekly', null), 'Every other week');
	assert.equal(describeRecurrence('biweekly', []), 'Every other week');
});
