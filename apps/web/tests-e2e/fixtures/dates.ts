/**
 * Day-relative timestamps for seeded rows, built in the zone the BROWSER runs
 * in rather than the one the Node process happens to be in.
 *
 * `playwright.config.ts` pins every browser context to `timezoneId: 'UTC'`, so
 * a page that buckets rows into "today" resolves that day in UTC. A spec that
 * seeds with `new Date(y, m, d, 12, 0)` builds the day in the *runner's* zone
 * instead. The two agree only while the local and UTC calendar dates agree —
 * for part of every day in most zones they do not, the row lands on the
 * adjacent day, the surface renders nothing, and a visibility assertion fails
 * on a timeout that says nothing about why. Hosted CI runners are UTC, so the
 * seam is invisible there and red at home. See decisions.md § 728.
 *
 * Every day-relative seed goes through this module. `dates.test.ts` scans the
 * spec sources for local-zone day derivation, so a new spec cannot quietly
 * re-derive the bug.
 */

import { waterDayKey } from '../../src/lib/nutrition/diary_day';

/// The zone `playwright.config.ts` pins every browser context to. Everything
/// below is built in it; `dates.test.ts` fails if the config stops saying so.
export const BROWSER_TIMEZONE = 'UTC';

/// A wall-clock instant on the browser's calendar day `offsetDays` from today.
/// Stepped through the calendar (`Date.UTC(…, d + offsetDays, …)`), never by a
/// fixed 24 h, so the helper reads the same whatever zone it names.
function dayInstant(offsetDays: number, hour: number, minute: number): Date {
	const now = new Date();
	return new Date(
		Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate() + offsetDays, hour, minute)
	);
}

/// Zero-padded `YYYY-MM-DD` of the browser's calendar day, `offsetDays` from
/// today — the `?date=` parameter, the `/nutrition/[date]/[slot]` segment, and
/// the day key any surface groups a row under.
export function browserDate(offsetDays = 0): string {
	return dayInstant(offsetDays, 0, 0).toISOString().slice(0, 10);
}

/// The browser's calendar day an instant the app already wrote falls on. Use
/// it to read a `started_at` back: the row was stamped by the browser, so
/// formatting it in the runner's zone can name the wrong day.
export function browserDateOf(instant: string | number | Date): string {
	return new Date(instant).toISOString().slice(0, 10);
}

/// Inclusive start instant of a browser calendar day — the `gte` bound of a
/// "clear everything from today" window.
export function browserDayStart(offsetDays = 0): string {
	return dayInstant(offsetDays, 0, 0).toISOString();
}

/// A wall-clock time on a browser calendar day, as an instant to seed a
/// `started_at` with.
export function browserDayAt(offsetDays: number, hour: number, minute = 0): string {
	return dayInstant(offsetDays, hour, minute).toISOString();
}

/// Midday on a browser calendar day — the safe default for a seeded row, far
/// enough from either boundary that no rounding puts it on a neighbour.
export function noonOnBrowserDay(offsetDays = 0): string {
	return browserDayAt(offsetDays, 12);
}

/// The browser's calendar year, offset by whole years. The runner's year and
/// the browser's disagree either side of a New Year boundary, and a surface
/// that renders a year off the URL is only self-consistent when the year in
/// the URL is the one the page itself calls current.
export function browserYear(offsetYears = 0): number {
	return new Date().getUTCFullYear() + offsetYears;
}

/// The naive `YYYY-MM-DDTHH:MM` an `<input type="datetime-local">` carries.
/// The control holds no zone and the page resolves it in the browser's, so a
/// string typed from the runner's wall clock is submitted as a different
/// instant — hours out, and across a week boundary into a bucket the
/// assertion did not mean.
export function browserDatetimeLocal(instant: string | number | Date): string {
	return new Date(instant).toISOString().slice(0, 16);
}

/// The nutrition water tracker's user-scoped localStorage key for the browser
/// day `offsetDays` from today. The day component comes from the page's own
/// `waterDayKey`, so the fixture cannot drift from the shipped (deliberately
/// unpadded) key shape and silently touch a key the page never reads.
export function waterStorageKey(userId: string, offsetDays = 0): string {
	return `water_ml_${userId}_${waterDayKey(browserDate(offsetDays))}`;
}
