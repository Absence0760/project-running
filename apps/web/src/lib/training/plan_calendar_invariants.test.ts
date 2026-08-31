// The two plan-calendar invariants decisions.md § 735 was written about:
// a duration is not a calendar span, and a generator offset is not a weekday.
//
// Both defects came from treating a derived quantity as the thing it was
// derived from, and both were invisible for most of the year — the week
// index only disagrees across a DST transition, and the day roles only look
// wrong once the start date is not a Sunday. So the assertions below are
// written against real transition dates and against the generator's own
// output rather than against the arithmetic that produces them.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { currentPlanWeekIndex } from './plan_week';
import { nextSundayIso, isSundayIso } from './plan_start';
import { generatePlan } from './training';

const DAY_MS = 86_400_000;

/** Whole UTC epoch-day of an ISO date — the unit the invariant is stated in. */
function epochDay(iso: string): number {
	const [y, m, d] = iso.split('-').map((n) => Number.parseInt(n, 10));
	return Math.round(Date.UTC(y, m - 1, d) / DAY_MS);
}

function isoPlusDays(iso: string, days: number): string {
	const [y, m, d] = iso.split('-').map((n) => Number.parseInt(n, 10));
	const t = new Date(Date.UTC(y, m - 1, d + days));
	return t.toISOString().slice(0, 10);
}

// --- a duration is not a calendar span -------------------------------------

test('the week index is exact on every day of a 24-week plan', () => {
	const start = '2026-03-22';
	for (let day = 0; day < 24 * 7; day++) {
		const today = isoPlusDays(start, day);
		assert.equal(
			currentPlanWeekIndex(start, today, 24),
			Math.floor(day / 7),
			`day ${day} (${today})`,
		);
	}
});

test('a plan week that spans a spring-forward is still seven days long', () => {
	// § 735's measured case: Europe/London springs forward on 2026-03-29, so
	// the local-midnight span from 2026-03-23 to 2026-03-30 is 167 h. Dividing
	// that by a week of milliseconds floors to 0 and reports Week 1 while the
	// detail page reports Week 2. Working in epoch-days there is no such span.
	const start = '2026-03-23';
	assert.equal(currentPlanWeekIndex(start, '2026-03-29', 16), 0);
	assert.equal(currentPlanWeekIndex(start, '2026-03-30', 16), 1);
	assert.equal(currentPlanWeekIndex(start, '2026-04-05', 16), 1);
	assert.equal(currentPlanWeekIndex(start, '2026-04-06', 16), 2);
	// The rejected arithmetic, reproduced, so the assertion above is a
	// comparison rather than a bare restatement.
	const localMidnightSpanMs = 167 * 3_600_000;
	assert.equal(Math.floor(localMidnightSpanMs / (7 * DAY_MS)), 0);
	assert.equal(epochDay('2026-03-30') - epochDay(start), 7);
});

test('a plan week that spans a fall-back does not run a week ahead either', () => {
	// The mirror case: a 169 h local-midnight span floors to 1 for a span
	// that is genuinely seven days, which is correct by accident — the same
	// arithmetic is wrong in the other direction one boundary later.
	const start = '2026-10-19';
	assert.equal(currentPlanWeekIndex(start, '2026-10-25', 12), 0);
	assert.equal(currentPlanWeekIndex(start, '2026-10-26', 12), 1);
	assert.equal(currentPlanWeekIndex(start, '2026-11-01', 12), 1);
	assert.equal(currentPlanWeekIndex(start, '2026-11-02', 12), 2);
});

test('the week index is clamped at both ends rather than running off the plan', () => {
	const start = '2026-06-07';
	// Before the plan opens: week 0, never a negative index.
	assert.equal(currentPlanWeekIndex(start, '2026-06-06', 8), 0);
	assert.equal(currentPlanWeekIndex(start, '2025-01-01', 8), 0);
	// Past the last week: the final week, never one past the array.
	assert.equal(currentPlanWeekIndex(start, isoPlusDays(start, 8 * 7), 8), 7);
	assert.equal(currentPlanWeekIndex(start, isoPlusDays(start, 400), 8), 7);
	// A one-week plan has exactly one bucket.
	assert.equal(currentPlanWeekIndex(start, isoPlusDays(start, 90), 1), 0);
});

test('the index never leaves the renderable range for any plan length', () => {
	const start = '2026-01-04';
	for (const weeks of [1, 2, 4, 8, 12, 16, 24, 52]) {
		for (const offset of [-400, -8, -1, 0, 1, 6, 7, 55, 366, 4000]) {
			const idx = currentPlanWeekIndex(start, isoPlusDays(start, offset), weeks);
			assert.ok(idx >= 0 && idx <= weeks - 1, `weeks=${weeks} offset=${offset} idx=${idx}`);
		}
	}
});

test('a leap day inside the span costs the plan no week', () => {
	// 2028 is a leap year. A plan opening in February must still count 29
	// February as one day.
	const start = '2028-02-06';
	assert.equal(epochDay('2028-03-05') - epochDay(start), 28);
	assert.equal(currentPlanWeekIndex(start, '2028-03-05', 12), 4);
	assert.equal(currentPlanWeekIndex(start, '2028-02-29', 12), 3);
});

// --- a generator offset is not a weekday -----------------------------------

const PLAN_INPUT = {
	goalEvent: 'distance_half' as const,
	daysPerWeek: 5,
	weeks: 4,
	recent5kSec: 22 * 60,
};

/** UTC weekday of an ISO date; 0 = Sunday. */
function dow(iso: string): number {
	return new Date(iso + 'T00:00:00Z').getUTCDay();
}

test('a Sunday start puts the long run on Sunday and the rest day on Monday', () => {
	// The generator's own comments name Sunday and Monday, but `longRun = 0`
	// and `rest = 1` are OFFSETS from the start date. They are only true
	// weekdays because the start is a Sunday, which is what `plan_start.ts`
	// exists to enforce.
	const plan = generatePlan({ ...PLAN_INPUT, startDate: '2026-06-07' });
	assert.equal(isSundayIso('2026-06-07'), true);
	for (const week of plan.weeks) {
		// The Sunday slot carries the week's anchor: the long run in every
		// phase but the last, and the race itself in race week.
		const anchor = week.workouts[0];
		assert.equal(dow(anchor.scheduled_date), 0, `week ${week.week_index} opens on Sunday`);
		assert.ok(
			anchor.kind === 'long' || anchor.kind === 'race',
			`week ${week.week_index} Sunday slot is ${anchor.kind}`,
		);
		// Monday is the generator's FIXED rest day (offset 1). Other unused
		// days also emit `rest`, so the claim is about that slot, not about
		// every rest day in the week.
		const monday = week.workouts.find((w) => dow(w.scheduled_date) === 1);
		assert.ok(monday, `week ${week.week_index} must contain a Monday`);
		assert.equal(monday.kind, 'rest', `week ${week.week_index} Monday`);
		// And the week is seven consecutive days starting on the Sunday.
		assert.equal(week.workouts.length, 7);
		assert.equal(dow(week.workouts[0].scheduled_date), 0);
	}
});

test('a Wednesday start shifts every day role — the offsets follow the start, not the calendar', () => {
	// This is the shape the mobile wizard used to accept. Pinned so the claim
	// "a non-Sunday start is a broken plan" is a measured fact rather than a
	// comment, and so a later generator change that made the roles absolute
	// would be noticed here rather than silently retiring plan_start.
	const plan = generatePlan({ ...PLAN_INPUT, startDate: '2026-06-03' });
	assert.equal(isSundayIso('2026-06-03'), false);
	const anchor = plan.weeks[0].workouts[0];
	assert.equal(anchor.kind, 'long');
	assert.equal(dow(anchor.scheduled_date), 3, 'the long run lands on Wednesday');
	const thursday = plan.weeks[0].workouts.find((w) => dow(w.scheduled_date) === 4);
	assert.ok(thursday);
	assert.equal(thursday.kind, 'rest', 'the fixed rest day lands on Thursday');
	// And no week of this plan opens its anchor slot on a Sunday at all.
	for (const week of plan.weeks) {
		assert.notEqual(dow(week.workouts[0].scheduled_date), 0, `week ${week.week_index}`);
	}
});

test('nextSundayIso lands on a Sunday for every day of three years', () => {
	let iso = '2026-01-01';
	for (let i = 0; i < 3 * 366; i++) {
		const snapped = nextSundayIso(iso);
		assert.equal(isSundayIso(snapped), true, `${iso} -> ${snapped}`);
		const delta = epochDay(snapped) - epochDay(iso);
		assert.ok(delta >= 0 && delta <= 6, `${iso} -> ${snapped} moved ${delta} days`);
		iso = isoPlusDays(iso, 1);
	}
});

test('nextSundayIso is idempotent, so a resubmitted form cannot walk the date forward', () => {
	for (const iso of ['2026-06-03', '2026-06-07', '2026-12-31', '2028-02-26']) {
		const once = nextSundayIso(iso);
		assert.equal(nextSundayIso(once), once, iso);
	}
});

test('nextSundayIso crosses a year boundary and a leap-year February', () => {
	// 2026-12-29 is a Tuesday.
	assert.equal(nextSundayIso('2026-12-29'), '2027-01-03');
	assert.equal(isSundayIso('2027-01-03'), true);
	// 2028-02-26 is a Saturday; the next day is the leap-year Sunday.
	assert.equal(nextSundayIso('2028-02-26'), '2028-02-27');
	// 2028-02-28 is a Monday, so the snap steps over 29 February.
	assert.equal(nextSundayIso('2028-02-28'), '2028-03-05');
});

test('a plan started on the snapped date is one the week index buckets from day zero', () => {
	// The two helpers meet here: the wizard snaps the start, and the surfaces
	// bucket from it. Week 0 must contain the start date itself.
	const asked = '2026-06-03';
	const start = nextSundayIso(asked);
	assert.equal(currentPlanWeekIndex(start, start, 12), 0);
	assert.equal(currentPlanWeekIndex(start, isoPlusDays(start, 6), 12), 0);
	assert.equal(currentPlanWeekIndex(start, isoPlusDays(start, 7), 12), 1);
});
