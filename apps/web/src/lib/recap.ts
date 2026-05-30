/**
 * "Year in running" recap — pure aggregator. Takes a year's worth of
 * Run rows and emits the headline numbers a wrap-up card needs:
 * total distance, total runs, total time, top week, longest run,
 * longest streak, monthly breakdown, etc. The Svelte route reads this
 * back into a Spotify-Wrapped-style hero layout.
 *
 * Pure module — no Supabase, no DOM. Tested in `recap.test.ts`.
 */

import type { Run } from './types';
import { computeRunStreaks } from './streaks';

export interface RecapMonthBucket {
	/** 1-based month (1=Jan … 12=Dec). */
	month: number;
	distanceM: number;
	durationS: number;
	runCount: number;
}

export interface RecapWeekTop {
	/** Monday of the top week, as a YYYY-MM-DD string. */
	weekStart: string;
	distanceM: number;
	runCount: number;
}

export interface YearInRunningRecap {
	year: number;
	runCount: number;
	totalDistanceM: number;
	totalDurationS: number;
	totalElevationM: number;
	longestRunM: number;
	fastestPaceSecPerKm: number | null; // best clean pace across runs
	bestStreakDays: number;
	currentStreakDays: number; // streak as of Dec 31 of the year
	earliestStartLocal: string | null; // hh:mm of earliest start time
	latestStartLocal: string | null;
	monthly: RecapMonthBucket[]; // length 12, sparse months still appear with zeros
	topWeek: RecapWeekTop | null;
	uniqueRouteCount: number;
	mostUsedActivity: string | null; // "run" / "walk" / "hike" / "cycle"
}

const MS_PER_DAY = 24 * 60 * 60 * 1000;

function isWithinYear(d: Date, year: number): boolean {
	return d.getFullYear() === year;
}

/** Monday of the local week as a YYYY-MM-DD string. */
function mondayOf(d: Date): string {
	const local = new Date(d.getFullYear(), d.getMonth(), d.getDate());
	const dow = (local.getDay() + 6) % 7; // 0=Mon, 6=Sun
	local.setDate(local.getDate() - dow);
	const y = local.getFullYear();
	const m = String(local.getMonth() + 1).padStart(2, '0');
	const day = String(local.getDate()).padStart(2, '0');
	return `${y}-${m}-${day}`;
}

function hhmm(d: Date): string {
	const local = d; // already local via JS Date
	return `${String(local.getHours()).padStart(2, '0')}:${String(local.getMinutes()).padStart(2, '0')}`;
}

/**
 * Returns a Run's elevation_gain in metres. audit/metadata-keys
 * (May 2026) dropped the `elevation_gain_m` fallback: no writer in
 * the codebase ever set the key, it was not in docs/backend/metadata.md,
 * and the fallback branch was dead code that confused dead-key
 * audits.
 */
function elevationOf(r: Run): number {
	const raw = r as unknown as { elevation_m?: number | null };
	return raw.elevation_m ?? 0;
}

/**
 * Build the year-in-running aggregate from a list of Runs.
 *
 * Pass *all* of the user's runs, not just the ones in the target year;
 * the helper filters internally so the streak computation can extend
 * across the year boundary (a streak that started in November counts
 * even though it crossed into the next year).
 */
export function buildYearInRunningRecap(runs: Run[], year: number): YearInRunningRecap {
	const inYear: Run[] = [];
	for (const r of runs) {
		const d = new Date(r.started_at);
		if (isWithinYear(d, year)) inYear.push(r);
	}

	let totalDistance = 0;
	let totalDuration = 0;
	let totalElevation = 0;
	let longest = 0;
	let fastestPaceSecPerKm: number | null = null;
	let earliestMin: number | null = null;
	let latestMin: number | null = null;
	let earliestRun: Date | null = null;
	let latestRun: Date | null = null;

	// Activity-type tally — `runs.metadata.activity_type` is the
	// canonical key on the row, but it lives in a jsonb bag. Treat
	// missing values as "run" which matches the default elsewhere.
	const activityCounts = new Map<string, number>();
	const monthly: RecapMonthBucket[] = Array.from({ length: 12 }, (_, i) => ({
		month: i + 1,
		distanceM: 0,
		durationS: 0,
		runCount: 0,
	}));
	const weeklyTotals = new Map<string, { distanceM: number; runCount: number }>();
	const uniqueRoutes = new Set<string>();

	for (const r of inYear) {
		const d = new Date(r.started_at);
		totalDistance += r.distance_m;
		totalDuration += r.duration_s;
		totalElevation += elevationOf(r);
		if (r.distance_m > longest) longest = r.distance_m;

		// Pace, in s/km, only on runs with non-trivial distance so a 200 m
		// stroll doesn't dominate.
		if (r.distance_m > 500 && r.duration_s > 0) {
			const pace = r.duration_s / (r.distance_m / 1000);
			if (fastestPaceSecPerKm == null || pace < fastestPaceSecPerKm) {
				fastestPaceSecPerKm = pace;
			}
		}

		const startMin = d.getHours() * 60 + d.getMinutes();
		if (earliestMin == null || startMin < earliestMin) {
			earliestMin = startMin;
			earliestRun = d;
		}
		if (latestMin == null || startMin > latestMin) {
			latestMin = startMin;
			latestRun = d;
		}

		const md = monthly[d.getMonth()];
		md.distanceM += r.distance_m;
		md.durationS += r.duration_s;
		md.runCount += 1;

		const wk = mondayOf(d);
		const cur = weeklyTotals.get(wk) ?? { distanceM: 0, runCount: 0 };
		cur.distanceM += r.distance_m;
		cur.runCount += 1;
		weeklyTotals.set(wk, cur);

		if (r.route_id) uniqueRoutes.add(r.route_id);

		const meta = (r as unknown as { metadata?: { activity_type?: string } }).metadata;
		const activity = meta?.activity_type ?? 'run';
		activityCounts.set(activity, (activityCounts.get(activity) ?? 0) + 1);
	}

	let topWeek: RecapWeekTop | null = null;
	for (const [weekStart, totals] of weeklyTotals.entries()) {
		if (topWeek == null || totals.distanceM > topWeek.distanceM) {
			topWeek = { weekStart, distanceM: totals.distanceM, runCount: totals.runCount };
		}
	}

	let mostUsedActivity: string | null = null;
	for (const [name, count] of activityCounts.entries()) {
		if (mostUsedActivity == null || count > (activityCounts.get(mostUsedActivity) ?? 0)) {
			mostUsedActivity = name;
		}
	}

	// Streaks — pass the *full* run set (not just inYear) because a
	// streak that started in the previous year still counts the days
	// it covered in this year. Anchor "today" at Dec 31 23:59 local.
	const endOfYear = new Date(year, 11, 31, 23, 59);
	const streaks = computeRunStreaks(
		runs.map((r) => new Date(r.started_at)),
		endOfYear,
	);

	return {
		year,
		runCount: inYear.length,
		totalDistanceM: totalDistance,
		totalDurationS: totalDuration,
		totalElevationM: totalElevation,
		longestRunM: longest,
		fastestPaceSecPerKm,
		bestStreakDays: streaks.best,
		currentStreakDays: streaks.current,
		earliestStartLocal: earliestRun ? hhmm(earliestRun) : null,
		latestStartLocal: latestRun ? hhmm(latestRun) : null,
		monthly,
		topWeek,
		uniqueRouteCount: uniqueRoutes.size,
		mostUsedActivity,
	};
}

/** Smallish utility for the share-card copy. */
export function recapHeadline(recap: YearInRunningRecap, kmOrMi: 'km' | 'mi'): string {
	if (recap.runCount === 0) return `No runs in ${recap.year} yet.`;
	const total =
		kmOrMi === 'mi'
			? (recap.totalDistanceM / 1609.344).toFixed(0) + ' mi'
			: (recap.totalDistanceM / 1000).toFixed(0) + ' km';
	return `${recap.year}: ${total} across ${recap.runCount} runs.`;
}

export const __TEST_ONLY__ = { mondayOf, MS_PER_DAY };
