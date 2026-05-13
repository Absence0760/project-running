/**
 * Pure run-streak computation. A "streak" is a sequence of
 * consecutive *local* days that each contain at least one run.
 *
 * Strava-style grace rule: a missing today does not break the
 * streak — the streak continues to count as long as yesterday had a
 * run. The streak only resets when a full day goes by without one.
 * This keeps the morning-after-a-late-run UX honest (you ran on
 * Monday evening, you wake up Tuesday, the dashboard still shows
 * your streak alive until end-of-Tuesday).
 *
 * Mirrors `apps/mobile_android/lib/streaks.dart`. Keep in lockstep —
 * the shared-library-syncer agent watches the pair.
 */

export interface RunStreaks {
	/** Days in the user's current active streak (0 if broken). */
	current: number;
	/** Longest historical streak (>= current). */
	best: number;
}

/** Return YYYY-MM-DD in the *local* timezone of the given Date. */
function localDayKey(d: Date): string {
	const y = d.getFullYear();
	const m = String(d.getMonth() + 1).padStart(2, '0');
	const day = String(d.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

/**
 * One UTC day in milliseconds. We add and subtract from the *date
 * portion* of a Date rather than this constant when stepping through
 * days, because DST transitions break the "24h per day" assumption.
 * The helper is here for the rare case the caller needs a quick
 * upper-bound comparison.
 */
export const MS_PER_DAY = 24 * 60 * 60 * 1000;

/**
 * Walk one day backwards from `d` in local time. DST-safe: builds a
 * new Date from y/m/d-1 rather than subtracting 86_400_000 ms (which
 * would cross a DST boundary as a 23/25-hour day).
 */
function previousLocalDay(d: Date): Date {
	return new Date(d.getFullYear(), d.getMonth(), d.getDate() - 1);
}

/**
 * Compute `{ current, best }` from a list of run start timestamps.
 *
 * @param runStarts UTC `Date`s representing each run's `started_at`.
 *                  Order doesn't matter — the helper bucketises by
 *                  local day and dedupes internally.
 * @param today Anchor for "current" (usually `new Date()`). Local
 *              date is what counts. Future-dated runs are ignored.
 */
export function computeRunStreaks(runStarts: Date[], today: Date): RunStreaks {
	if (runStarts.length === 0) return { current: 0, best: 0 };

	const todayKey = localDayKey(today);

	// Distinct local-day keys for every run, clamped to <= today so a
	// runner whose phone clock is ahead by an hour doesn't get a
	// phantom day in the future.
	const dayKeys = new Set<string>();
	for (const r of runStarts) {
		const k = localDayKey(r);
		if (k <= todayKey) dayKeys.add(k);
	}
	if (dayKeys.size === 0) return { current: 0, best: 0 };

	const sortedKeys = [...dayKeys].sort();

	// Best streak — walk the sorted set, increment on consecutive days,
	// reset on gap, track max.
	let best = 1;
	let run = 1;
	for (let i = 1; i < sortedKeys.length; i++) {
		const prev = sortedKeys[i - 1];
		const here = sortedKeys[i];
		// "Consecutive" means here is exactly previous-+1-day in local
		// time. Build prev's Date and step forward one local day.
		const [py, pm, pd] = prev.split('-').map((s) => parseInt(s, 10));
		const expected = localDayKey(new Date(py, pm - 1, pd + 1));
		if (here === expected) {
			run += 1;
			if (run > best) best = run;
		} else {
			run = 1;
		}
	}

	// Current streak — walk back from today. Strava grace: if today
	// has no run, start counting from yesterday instead. The streak
	// is whatever consecutive run of days ends at that anchor.
	let anchor = new Date(today.getFullYear(), today.getMonth(), today.getDate());
	if (!dayKeys.has(localDayKey(anchor))) {
		// Try yesterday — the grace day.
		anchor = previousLocalDay(anchor);
		if (!dayKeys.has(localDayKey(anchor))) {
			return { current: 0, best };
		}
	}
	let current = 0;
	while (dayKeys.has(localDayKey(anchor))) {
		current += 1;
		anchor = previousLocalDay(anchor);
	}
	return { current, best };
}
