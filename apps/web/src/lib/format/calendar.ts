// Locale-aware month + weekday names and week-start ordering for calendar
// grids (i18n-readiness W-5/W-14). PlanCalendar previously hard-coded
// English ['January', …] + ['Mon', …] arrays and always rendered
// Monday-first, ignoring the user's week_start_day. These pure helpers
// derive the names from Intl.DateTimeFormat and reorder them for the
// chosen week start.
//
// Pure (plain .ts, explicit `locale`) so they unit-test under `tsx --test`;
// the reactive caller passes the active i18n locale. Name arrays are
// memoised by locale (DateTimeFormat construction is the hot part).

export type WeekStart = 'monday' | 'sunday';

// 15th of each month, 2021 — any year/day works for month names; UTC +
// timeZone:'UTC' keeps it tz-independent.
const MONTH_REF = Array.from({ length: 12 }, (_, i) => new Date(Date.UTC(2021, i, 15)));
// 2024-01-01 is a Monday → 2024-01-01..07 walks Mon→Sun.
const WEEK_REF_MON = Array.from({ length: 7 }, (_, i) => new Date(Date.UTC(2024, 0, 1 + i)));

const monthCache = new Map<string, string[]>();
const dowCache = new Map<string, string[]>();

export function monthNames(locale?: string): string[] {
	const key = locale ?? '';
	let v = monthCache.get(key);
	if (!v) {
		const f = new Intl.DateTimeFormat(locale, { month: 'long', timeZone: 'UTC' });
		v = MONTH_REF.map((d) => f.format(d));
		monthCache.set(key, v);
	}
	return v;
}

/// Long month name for a 0-based month index (0 = January), wrapping so a
/// `month + 1` overflow is harmless.
export function monthName(index: number, locale?: string): string {
	return monthNames(locale)[((index % 12) + 12) % 12];
}

function weekdaysMonFirst(locale?: string): string[] {
	const key = locale ?? '';
	let v = dowCache.get(key);
	if (!v) {
		const f = new Intl.DateTimeFormat(locale, { weekday: 'short', timeZone: 'UTC' });
		v = WEEK_REF_MON.map((d) => f.format(d));
		dowCache.set(key, v);
	}
	return v;
}

/// Short weekday abbreviations (7), ordered to begin on the chosen week
/// start: `['Mon'…'Sun']` for monday, `['Sun','Mon'…'Sat']` for sunday.
export function weekdayAbbrevs(weekStart: WeekStart, locale?: string): string[] {
	const mon = weekdaysMonFirst(locale);
	return weekStart === 'sunday' ? [mon[6], ...mon.slice(0, 6)] : mon;
}

/// Number of blank leading cells before the 1st of a month in a grid that
/// begins on `weekStart`. `firstDay` is `Date.getDay()` (0 = Sunday).
export function leadingBlanks(firstDay: number, weekStart: WeekStart): number {
	return weekStart === 'sunday' ? firstDay : (firstDay + 6) % 7;
}
