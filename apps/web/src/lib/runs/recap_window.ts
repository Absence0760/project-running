/**
 * Fetch shaping for the recap cards.
 *
 * `buildYearInRunningRecap` / `buildMonthInRunningRecap` take one flat run
 * list and filter it internally, so both pages used to hand them every run the
 * account has ever recorded — `select('*')`, no window, ~3,000 rows to render
 * a card built from ~250 of them (a monthly card, ~20).
 *
 * Only one recap output reads a run from outside the recap period: the streak.
 * `computeRunStreaks` is handed the whole list and buckets it by local day, so
 * a streak running 28 Dec → 3 Jan is the January card's best streak. It reads
 * nothing but `started_at`. Everything else is filtered to the recap year
 * first. That asymmetry is what this module exploits: fetch the year at the
 * recap column set, fetch one column for the rest of history, and rebuild the
 * flat list the engine expects.
 *
 * Pure — no Supabase, no DOM (the reads live in `core/data`). Web-only: it
 * shapes a fetch, it is not part of the `recap` TS↔Dart parity pair.
 */

import type { Run } from '../types';

export interface RecapWindow {
	/** Inclusive lower bound on `started_at`, as an ISO instant. */
	fromIso: string;
	/** Exclusive upper bound on `started_at`, as an ISO instant. */
	beforeIso: string;
}

/**
 * The instant window covering local calendar year `year`.
 *
 * Built from local midnights rather than `${year}-01-01T00:00:00Z` because the
 * recap buckets a run with `Date#getFullYear`, i.e. by the runner's local
 * year: east of UTC, a 31 Dec 23:00 local run is already 1 Jan in UTC, and a
 * UTC-bounded window would drop it out of the card it belongs to.
 */
export function recapYearWindow(year: number): RecapWindow {
	return {
		fromIso: new Date(year, 0, 1).toISOString(),
		beforeIso: new Date(year + 1, 0, 1).toISOString(),
	};
}

/** True when `startedAt` falls inside `win`. */
export function isInRecapWindow(startedAt: string, win: RecapWindow): boolean {
	const t = Date.parse(startedAt);
	if (Number.isNaN(t)) return false;
	return t >= Date.parse(win.fromIso) && t < Date.parse(win.beforeIso);
}

/**
 * A run outside the recap window, carried for its start timestamp alone.
 *
 * The engine reaches an out-of-window run only through `computeRunStreaks`;
 * every other read is behind the in-year filter, which by construction these
 * rows fail. The remaining fields are zeroed rather than plausible so that a
 * future reader who forgets that gets an obviously-empty run rather than a
 * quietly wrong total.
 */
function streakOnlyRun(startedAt: string): Run {
	return {
		id: `streak:${startedAt}`,
		user_id: '',
		started_at: startedAt,
		distance_m: 0,
		duration_s: 0,
		elevation_gain_m: 0,
		route_id: null,
		track_url: null,
		source: 'app',
		activity_type: 'run',
		metadata: null,
	} as unknown as Run;
}

/**
 * Rebuild the flat run list the recap engine expects from a windowed read:
 * the window's runs verbatim, plus a start-timestamp-only stub for every run
 * outside it.
 *
 * `allStartedAt` is every run's `started_at` including the window's own — the
 * cheapest read is unfiltered — so the window is subtracted here rather than
 * on the wire. `recap_window.test.ts` pins that the result produces a recap
 * identical to the one built from the full rows.
 */
export function mergeRecapRuns(
	windowed: Run[],
	allStartedAt: readonly string[],
	win: RecapWindow,
): Run[] {
	const out = [...windowed];
	for (const startedAt of allStartedAt) {
		if (!isInRecapWindow(startedAt, win)) out.push(streakOnlyRun(startedAt));
	}
	return out;
}
