/**
 * Diary day — which calendar day the nutrition surface is showing, and the
 * fetch windows, storage keys and write timestamps that day implies.
 *
 * `/nutrition` resolved every one of those from `new Date()`, so a forgotten
 * yesterday could never be back-filled and no past day could be reviewed —
 * even though `/nutrition/[date]/[slot]` is already parameterised by date and
 * `createFoodEntry` / `logMealTemplate` / `logRecipe` all already accept a
 * `started_at`. The data layer was ready; only the surface was today-locked.
 *
 * Two rules this module exists to hold:
 *
 * - **Days step through the calendar, never by a fixed 24 hours.** A local day
 *   is 23 or 25 hours across a DST transition, so a millisecond step repeats or
 *   skips a day and an exclusive window end lands at 23:00 of the same day,
 *   hiding the last hour's entries ([decisions.md § 589] — that exact bug was
 *   fixed in the mobile nutrition day window). Every step here goes through
 *   `new Date(y, m, d + n)`, which normalises through the calendar.
 * - **The diary never shows a future day.** A `started_at` in the future sits
 *   outside every "today" window the rings, the dashboard card and the Coach
 *   context read, so a hand-edited or stale `?date=` resolves to today rather
 *   than to a day nobody can have eaten.
 *
 * Web-only; the mobile mirror is tracked in docs/product/followups.md.
 */

/// Query parameter carrying the viewed day on `/nutrition`.
export const DIARY_DATE_PARAM = 'date';

/// A local calendar date, `m` 1-based so it reads like the ISO string.
export interface CalendarDate {
	y: number;
	m: number;
	d: number;
}

/// Local zero-padded `YYYY-MM-DD` for a Date — the diary's day identity and
/// the `[date]` route segment. Local, not UTC: a 23:30 entry belongs to the
/// day the user was living, not to tomorrow in Greenwich.
export function isoDateOf(d: Date): string {
	const mm = String(d.getMonth() + 1).padStart(2, '0');
	const dd = String(d.getDate()).padStart(2, '0');
	return `${d.getFullYear()}-${mm}-${dd}`;
}

/// Strict `YYYY-MM-DD` parse. Null for anything that is not a real calendar
/// date — including one the calendar does not have (`2026-02-30`), which
/// `new Date` would otherwise normalise into March and show as the wrong day.
export function parseIsoDate(iso: string | null | undefined): CalendarDate | null {
	if (!iso) return null;
	const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(iso);
	if (!match) return null;
	const y = Number(match[1]);
	const m = Number(match[2]);
	const d = Number(match[3]);
	const probe = new Date(y, m - 1, d);
	// Also rejects a two-digit year: `new Date(26, …)` means 1926, so the
	// round-trip fails and `0026-02-01` never resolves to a usable day.
	if (probe.getFullYear() !== y || probe.getMonth() !== m - 1 || probe.getDate() !== d) {
		return null;
	}
	return { y, m, d };
}

/// The day the diary should show for a `?date=` value: the parameter when it
/// is a real, non-future calendar date, else today. Fail-safe by design — a
/// typo'd, stale or hand-edited URL lands on today rather than on an empty day
/// the user cannot explain.
export function resolveDiaryDate(param: string | null | undefined, now: Date): string {
	const today = isoDateOf(now);
	if (!parseIsoDate(param)) return today;
	// Zero-padded fixed-width dates sort lexicographically in calendar order,
	// so a string compare is the whole future test.
	return (param as string) > today ? today : (param as string);
}

/// `iso` moved `deltaDays` calendar days, clamped so the diary never steps
/// past today. An unparseable input resolves to today.
export function stepDiaryDate(iso: string, deltaDays: number, now: Date): string {
	const today = isoDateOf(now);
	const base = parseIsoDate(iso);
	if (!base) return today;
	const stepped = isoDateOf(new Date(base.y, base.m - 1, base.d + deltaDays));
	return stepped > today ? today : stepped;
}

export function isDiaryToday(iso: string, now: Date): boolean {
	return iso === isoDateOf(now);
}

/// Milliseconds from `now` to the next local midnight — the one instant at
/// which the day the diary calls "Today" stops being today.
///
/// Stepped through the calendar like every other step in this module, so a DST
/// day is 23 or 25 hours long and the wakeup still lands on midnight. A fixed
/// 86_400_000 would fire an hour early on a fall-back day and an hour late on a
/// spring-forward one ([decisions.md § 589]).
export function msUntilNextLocalMidnight(now: Date): number {
	const next = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1);
	return next.getTime() - now.getTime();
}

/// Whether the diary can step forward — false on today, and on any day a bad
/// `?date=` resolved forward to today.
export function canStepForward(iso: string, now: Date): boolean {
	return iso < isoDateOf(now);
}

export interface DiaryWindow {
	/// Inclusive start instant (local midnight of the window's first day).
	startIso: string;
	/// Exclusive end instant (local midnight of the day *after* `iso`).
	endIso: string;
}

/// Half-open `[startIso, endIso)` instant window covering the `days` calendar
/// days ending on — and including — `iso`. Null when `iso` is not a calendar
/// date, so a caller that skipped `resolveDiaryDate` fetches nothing rather
/// than a wrong day.
export function diaryWindow(iso: string, days = 1): DiaryWindow | null {
	const base = parseIsoDate(iso);
	if (!base || days < 1) return null;
	const start = new Date(base.y, base.m - 1, base.d - (days - 1));
	const end = new Date(base.y, base.m - 1, base.d + 1);
	return { startIso: start.toISOString(), endIso: end.toISOString() };
}

/// Whether a row's `started_at` falls inside a diary window.
///
/// Compared as **instants**, never as strings. Postgres hands back
/// `2026-08-13T04:00:00+00:00` while [diaryWindow] builds `…T04:00:00.000Z`;
/// those are the same moment but `'+' < '.'`, so a lexicographic compare drops
/// a row landing exactly on the boundary — which for a local-midnight window is
/// precisely the row most likely to be there. A malformed timestamp is out.
export function isWithinWindow(startedAt: string | null | undefined, window: DiaryWindow): boolean {
	if (!startedAt) return false;
	const at = new Date(startedAt).getTime();
	if (!Number.isFinite(at)) return false;
	return at >= new Date(window.startIso).getTime() && at < new Date(window.endIso).getTime();
}

/// The `n` local dates ending on — and including — `iso`, oldest first. These
/// are the trend chart's buckets, so they must be the same `YYYY-MM-DD` an
/// entry's `started_at` maps to through [isoDateOf].
export function trailingDates(iso: string, n: number): string[] {
	const base = parseIsoDate(iso);
	if (!base || n < 1) return [];
	const out: string[] = [];
	for (let i = n - 1; i >= 0; i--) {
		out.push(isoDateOf(new Date(base.y, base.m - 1, base.d - i)));
	}
	return out;
}

/// The `started_at` an entry logged while viewing `iso` should carry.
///
/// On today it is simply now, so meal ordering keeps its real clock time. On a
/// past day it is the same wall-clock time on that date: inside the day in
/// every case, and monotonic across a logging session so several back-filled
/// items keep the order they were entered. On a spring-forward date a
/// non-existent local time normalises forward an hour — still the same day,
/// which is all the window cares about.
export function entryTimestampFor(iso: string, now: Date): string {
	const base = parseIsoDate(iso);
	if (!base || isDiaryToday(iso, now)) return now.toISOString();
	return new Date(
		base.y,
		base.m - 1,
		base.d,
		now.getHours(),
		now.getMinutes(),
		now.getSeconds(),
		now.getMilliseconds(),
	).toISOString();
}

/// Day component of the water tracker's localStorage key.
///
/// Deliberately **not** the zero-padded [isoDateOf] form: the shipped key was
/// built from unpadded `getMonth() + 1` / `getDate()`, and padding it here
/// would orphan the count of everyone who had already drunk something on the
/// day this shipped. The ugliness buys continuity; nothing else reads it.
export function waterDayKey(iso: string): string {
	const base = parseIsoDate(iso);
	if (!base) return iso;
	return `${base.y}-${base.m}-${base.d}`;
}
