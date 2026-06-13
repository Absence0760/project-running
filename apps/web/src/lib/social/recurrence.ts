// Client-side expansion of the enum-recurrence model used by Phase 2 events.
// See docs/architecture/decisions.md #10 — we deliberately avoided RFC 5545 RRULE in favour
// of (freq, byday[], until, count). Expansion is cheap, idempotent, and runs
// on every event-detail render; no need to materialise instances.

import type { Event, Weekday, RecurrenceFreq } from '../types';

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

// A recurring event's instance_start is its per-occurrence capacity key
// (20261018_001) and the live-race arm key — every viewer's expansion MUST
// produce the IDENTICAL instant, or two spectators in different zones RSVP
// against different keys and a cross-TZ viewer sees a live race as "not
// armed". The wall-clock the organiser meant is fixed in the EVENT's zone,
// not the viewer's. Reading the recurrence fields with `getHours()` /
// `getDay()` and stamping with `setHours()` used the viewer's LOCAL zone, so
// the computed instant drifted by the viewer-vs-event offset. When the event
// carries a timezone (20270111_001) we read + stamp the fields in UTC — a
// zone-independent anchor identical on every viewer and both platforms (the
// server's discovery filter likewise normalises via `at time zone`). Legacy
// rows with no timezone keep the original local-zone behaviour so their
// already-placed RSVPs don't shift. Mirrors apps/mobile_android/lib/
// recurrence.dart — keep the two in lockstep.
interface WallClock {
	weekday(d: Date): number;
	startOfWeek(d: Date): Date;
	startOfDay(d: Date): Date;
	addDays(d: Date, n: number): Date;
	stamp(day: Date, src: Date): Date;
}

const localClock: WallClock = {
	weekday: (d) => d.getDay(),
	startOfWeek,
	startOfDay,
	addDays,
	stamp: (day, src) => {
		const s = new Date(day);
		s.setHours(src.getHours(), src.getMinutes(), src.getSeconds(), 0);
		return s;
	}
};

const utcClock: WallClock = {
	weekday: (d) => d.getUTCDay(),
	startOfWeek: (d) => {
		const c = new Date(d);
		c.setUTCHours(0, 0, 0, 0);
		c.setUTCDate(c.getUTCDate() - ((c.getUTCDay() + 6) % 7)); // Monday anchor
		return c;
	},
	startOfDay: (d) => {
		const c = new Date(d);
		c.setUTCHours(0, 0, 0, 0);
		return c;
	},
	addDays: (d, n) => {
		const c = new Date(d);
		c.setUTCDate(c.getUTCDate() + n);
		return c;
	},
	stamp: (day, src) => {
		const s = new Date(day);
		s.setUTCHours(src.getUTCHours(), src.getUTCMinutes(), src.getUTCSeconds(), 0);
		return s;
	}
};

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

	const wc = event.timezone ? utcClock : localClock;
	const until = event.recurrence_until ? new Date(event.recurrence_until) : null;
	const hardCap = event.recurrence_count ?? Infinity;
	const results: Date[] = [];
	const step = event.recurrence_freq === 'biweekly' ? 14 : 7;
	const byday: Weekday[] =
		event.recurrence_freq === 'monthly'
			? ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'] // unused for monthly; we use the day-of-month of starts_at
			: (event.recurrence_byday?.length ? event.recurrence_byday : [indexToWeekday(wc.weekday(start))]) as Weekday[];

	let produced = 0;
	if (event.recurrence_freq === 'monthly') {
		// Monthly: same day-of-month as starts_at, every N months. Each instance
		// is `i` whole months from start with the day clamped to the target
		// month's last day (Jan-31 → Feb-28/29). Stepping a running cursor would
		// let a clamp permanently shrink the day-of-month (Jan-31 → Feb-28 →
		// Mar-28), drifting off the intended day.
		for (let i = 0; produced < hardCap; i++) {
			if (i >= max * 12) break;
			const cursor = addMonthsClamped(start, i, !!event.timezone);
			if (until && cursor > until) break;
			if (cursor > to) break;
			if (cursor >= from) {
				results.push(cursor);
				produced++;
				if (results.length >= max) break;
			}
		}
		return results;
	}

	// Weekly / biweekly: step day-by-day, anchored at the Monday of starts_at's
	// week so weekIndex * 7 == elapsed weeks. The loop guards compare *calendar
	// day* (cursor d is at midnight) — the precise checks happen against the
	// `stamped` time (d stamped at starts_at's time-of-day). Mirrors the Dart
	// twin in apps/mobile_android/lib/recurrence.dart; without the split, the
	// first-week instance is silently dropped whenever starts_at has a non-
	// midnight time-of-day (d at midnight < start at, say, 09:00).
	const anchor = wc.startOfWeek(start);
	const startDayOnly = wc.startOfDay(start);
	for (let dayOffset = 0; dayOffset < max * step * 7; dayOffset++) {
		const d = wc.addDays(anchor, dayOffset);
		if (d < startDayOnly) continue;
		if (until && d > wc.addDays(until, 1)) break;
		if (d > wc.addDays(to, 1)) break;

		const weekIndex = Math.floor(dayOffset / 7);
		if (weekIndex % (step / 7) !== 0) continue;

		const wd = indexToWeekday(wc.weekday(d));
		if (!byday.includes(wd)) continue;

		const stamped = wc.stamp(d, start);
		if (until && stamped > until) continue;
		if (stamped > to) continue;
		if (stamped < start) continue;

		if (stamped >= from) {
			results.push(stamped);
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

function addMonthsClamped(base: Date, months: number, useUtc: boolean): Date {
	const baseMonth = useUtc ? base.getUTCMonth() : base.getMonth();
	const baseYear = useUtc ? base.getUTCFullYear() : base.getFullYear();
	const baseDay = useUtc ? base.getUTCDate() : base.getDate();
	const h = useUtc ? base.getUTCHours() : base.getHours();
	const mi = useUtc ? base.getUTCMinutes() : base.getMinutes();
	const s = useUtc ? base.getUTCSeconds() : base.getSeconds();
	const total = baseMonth + months;
	const year = baseYear + Math.floor(total / 12);
	const month = ((total % 12) + 12) % 12;
	// Last day of the target month — computed with the same clock as the rest
	// so the day-of-month clamp matches the anchor's wall-clock calendar.
	const lastDay = useUtc
		? new Date(Date.UTC(year, month + 1, 0)).getUTCDate()
		: new Date(year, month + 1, 0).getDate();
	const day = Math.min(baseDay, lastDay);
	return useUtc
		? new Date(Date.UTC(year, month, day, h, mi, s, 0))
		: new Date(year, month, day, h, mi, s, 0);
}

function startOfWeek(d: Date): Date {
	const c = new Date(d);
	c.setHours(0, 0, 0, 0);
	c.setDate(c.getDate() - ((c.getDay() + 6) % 7)); // Monday anchor, matches recurrence.dart
	return c;
}

function startOfDay(d: Date): Date {
	const c = new Date(d);
	c.setHours(0, 0, 0, 0);
	return c;
}
