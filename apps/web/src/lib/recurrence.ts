// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// See docs/decisions.md #10 — we deliberately avoided RFC 5545 RRULE in favour
// of (freq, byday[], until, count). Expansion is cheap, idempotent, and runs
// on every event-detail render; no need to materialise instances.

import type { Event, Weekday, RecurrenceFreq } from './types';

const WEEKDAY_TO_INDEX: Record<Weekday, number> = {
	SU: 0,
	MO: 1,
	TU: 2,
	WE: 3,
	TH: 4,
	FR: 5,
	SA: 6
};

const WEEKDAY_LABEL: Record<Weekday, string> = {
	MO: 'Mon',
	TU: 'Tue',
	WE: 'Wed',
	TH: 'Thu',
	FR: 'Fri',
	SA: 'Sat',
	SU: 'Sun'
};

const ISO_ORDER: Weekday[] = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/**
 * Expand a recurring event into instance start times within [from, to], or
 * return [starts_at] for a non-recurring event. Bounded by the event's
 * `recurrence_until` and `recurrence_count` as well.
 */
export function expandInstances(event: Event, from: Date, to: Date, max = 100): Date[] {
	const start = new Date(event.starts_at);
	if (!event.recurrence_freq) {
		return start >= from && start <= to ? [start] : [];
	}

	const until = event.recurrence_until ? new Date(event.recurrence_until) : null;
	const hardCap = event.recurrence_count ?? Infinity;
	const results: Date[] = [];
	const step = event.recurrence_freq === 'biweekly' ? 14 : 7;
	const byday: Weekday[] =
		event.recurrence_freq === 'monthly'
			? ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'] // unused for monthly; we use the day-of-month of starts_at
			: (event.recurrence_byday?.length ? event.recurrence_byday : [indexToWeekday(start.getDay())]) as Weekday[];

	let produced = 0;
	if (event.recurrence_freq === 'monthly') {
		// Monthly: same day-of-month as starts_at, every N months stepping by 1.
		let cursor = new Date(start);
		for (let i = 0; i < max * 12 && produced < hardCap; i++) {
			if (until && cursor > until) break;
			if (cursor > to) break;
			if (cursor >= from) {
				results.push(new Date(cursor));
				produced++;
				if (results.length >= max) break;
			}
			cursor = addMonths(cursor, 1);
		}
		return results;
	}

	// Weekly / biweekly: for each week-block (size 7 or 14 days), emit every
	// weekday in `byday` that falls on or after the block start and matches.
	// Simpler: step the cursor day-by-day, and only emit days in `byday`, but
	// only when the week index (0, 1, 2, ...) is a multiple of step/7.
	const anchor = startOfWeek(start); // Sunday anchor, so weekIndex * 7 == elapsed weeks
	for (let dayOffset = 0; dayOffset < max * step * 7; dayOffset++) {
		const d = addDays(anchor, dayOffset);
		if (d < start) continue;
		if (until && d > until) break;
		if (d > to) break;

		const weekIndex = Math.floor(dayOffset / 7);
		if (weekIndex % (step / 7) !== 0) continue;

		const wd = indexToWeekday(d.getDay());
		if (!byday.includes(wd)) continue;

		// Preserve the time-of-day of the original starts_at.
		d.setHours(start.getHours(), start.getMinutes(), start.getSeconds(), 0);
		if (d < start) continue;

		if (d >= from) {
			results.push(new Date(d));
			produced++;
			if (results.length >= max) break;
			if (produced >= hardCap) break;
		}
	}
	return results;
}

export function nextInstanceAfter(event: Event, after = new Date()): Date | null {
	const in10Years = new Date(after.getTime() + 10 * 365 * 24 * 3600 * 1000);
	const [first] = expandInstances(event, after, in10Years, 1);
	return first ?? null;
}

export function describeRecurrence(
	freq: RecurrenceFreq | null,
	byday: Weekday[] | null | undefined
): string {
	if (!freq) return 'One-off event';
	if (freq === 'monthly') return 'Repeats monthly';
	const days = (byday ?? []).length
		? ISO_ORDER.filter((d) => byday!.includes(d)).map((d) => WEEKDAY_LABEL[d]).join(', ')
		: '';
	const base = freq === 'biweekly' ? 'Every other week' : 'Every week';
	return days ? `${base} · ${days}` : base;
}

export const WEEKDAY_CHOICES: { code: Weekday; label: string }[] = ISO_ORDER.map((code) => ({
	code,
	label: WEEKDAY_LABEL[code]
}));

function indexToWeekday(i: number): Weekday {
	return Object.entries(WEEKDAY_TO_INDEX).find(([, v]) => v === i)![0] as Weekday;
}

function addDays(d: Date, n: number): Date {
	const c = new Date(d);
	c.setDate(c.getDate() + n);
	return c;
}

function addMonths(d: Date, n: number): Date {
	const c = new Date(d);
	c.setMonth(c.getMonth() + n);
	return c;
}

function startOfWeek(d: Date): Date {
	const c = new Date(d);
	c.setHours(0, 0, 0, 0);
	c.setDate(c.getDate() - c.getDay());
	return c;
}
