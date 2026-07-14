/**
 * "Year in running" recap — pure aggregator. Takes a year's worth of
 * Run rows and emits the headline numbers a wrap-up card needs:
 * total distance, total runs, total time, top week, longest run,
 * longest streak, monthly breakdown, etc. The Svelte route reads this
 * back into a Spotify-Wrapped-style hero layout.
 *
 * Pure module — no Supabase, no DOM. Tested in `recap.test.ts`.
 */

import type { Run } from '../types';
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

/**
 * A "trophy" earned over the year — the Strava-Year-in-Sport-style badge
 * grid. Derived purely from the aggregate (plus the optional photo /
 * personal-record counts the page supplies). Only *earned* badges are
 * emitted; at most one per category (the highest tier reached).
 */
export interface RecapBadge {
	id: string;
	icon: string; // material-symbols glyph name
	label: string;
	detail: string;
}

/**
 * Counts the recap can't derive from `Run` rows alone — the page fetches
 * them and passes them in. Both optional so the pure aggregate still works
 * standalone (e.g. the share-image builder, which doesn't fetch them).
 */
export interface RecapExtras {
	/** run_photos attached to the year's runs. */
	photoCount?: number;
	/** personal_records rows achieved during the year (the app's
	 * achievement primitive — segment KOM "crowns" need a global
	 * leaderboard aggregation and are intentionally not counted here). */
	personalRecordCount?: number;
}

export interface YearInRunningRecap {
	year: number;
	/** Present only on a monthly recap (1-based). Absent on the annual card. */
	month?: number;
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
	photoCount: number;
	personalRecordCount: number;
	badges: RecapBadge[];
}

/** Inputs the badge tiers read, gathered once during the build. */
interface BadgeInputs {
	totalDistanceM: number;
	runCount: number;
	bestStreakDays: number;
	totalElevationM: number;
	longestRunM: number;
	activeMonths: number;
	distinctActivities: number;
	earliestStartLocal: string | null;
	latestStartLocal: string | null;
	photoCount: number;
	personalRecordCount: number;
}

/**
 * Earned-only trophy grid. Each category lists tiers high→low; the first
 * threshold met wins, so a 1,200 km year shows "1,000 km club", not three
 * distance badges. Pure + deterministic so it's unit-testable.
 */
export function computeRecapBadges(i: BadgeInputs): RecapBadge[] {
	const out: RecapBadge[] = [];
	const km = i.totalDistanceM / 1000;
	const pick = (
		tiers: Array<{ when: boolean; id: string; icon: string; label: string; detail: string }>,
	) => {
		const hit = tiers.find((t) => t.when);
		if (hit) out.push({ id: hit.id, icon: hit.icon, label: hit.label, detail: hit.detail });
	};

	pick([
		{ when: km >= 2000, id: 'dist-2000', icon: 'public', label: '2,000 km', detail: 'Halfway round the planet' },
		{ when: km >= 1000, id: 'dist-1000', icon: 'public', label: '1,000 km club', detail: 'A four-figure year' },
		{ when: km >= 500, id: 'dist-500', icon: 'route', label: '500 km', detail: 'Serious mileage' },
		{ when: km >= 100, id: 'dist-100', icon: 'route', label: 'Century', detail: '100 km on the year' },
	]);
	pick([
		{ when: i.runCount >= 200, id: 'runs-200', icon: 'sprint', label: '200 runs', detail: 'Almost every other day' },
		{ when: i.runCount >= 100, id: 'runs-100', icon: 'sprint', label: 'Centurion', detail: '100 runs logged' },
		{ when: i.runCount >= 50, id: 'runs-50', icon: 'sprint', label: '50 runs', detail: 'A steady habit' },
	]);
	pick([
		{ when: i.longestRunM >= 50000, id: 'long-ultra', icon: 'military_tech', label: 'Ultra', detail: '50 km+ in one run' },
		{ when: i.longestRunM >= 42195, id: 'long-marathon', icon: 'military_tech', label: 'Marathon', detail: '42.2 km in one run' },
		{ when: i.longestRunM >= 21097, id: 'long-half', icon: 'military_tech', label: 'Half marathon', detail: '21.1 km in one run' },
	]);
	pick([
		{ when: i.bestStreakDays >= 30, id: 'streak-30', icon: 'local_fire_department', label: 'Month-long streak', detail: `${i.bestStreakDays} days in a row` },
		{ when: i.bestStreakDays >= 14, id: 'streak-14', icon: 'local_fire_department', label: 'Fortnight streak', detail: `${i.bestStreakDays} days in a row` },
		{ when: i.bestStreakDays >= 7, id: 'streak-7', icon: 'local_fire_department', label: 'Week streak', detail: `${i.bestStreakDays} days in a row` },
	]);
	pick([
		{ when: i.totalElevationM >= 8849, id: 'elev-everest', icon: 'terrain', label: 'Everested', detail: 'Climbed an Everest' },
		{ when: i.totalElevationM >= 5000, id: 'elev-5000', icon: 'terrain', label: '5,000 m climbed', detail: 'Vertical year' },
	]);
	pick([
		{ when: i.activeMonths >= 12, id: 'months-12', icon: 'calendar_month', label: 'Every month', detail: 'Active all 12 months' },
		{ when: i.activeMonths >= 6, id: 'months-6', icon: 'calendar_month', label: 'Half the year', detail: `Active in ${i.activeMonths} months` },
	]);
	pick([
		{ when: i.personalRecordCount >= 5, id: 'pr-5', icon: 'trophy', label: 'Record breaker', detail: `${i.personalRecordCount} personal records` },
		{ when: i.personalRecordCount >= 1, id: 'pr-1', icon: 'trophy', label: 'New PR', detail: `${i.personalRecordCount} personal record${i.personalRecordCount === 1 ? '' : 's'}` },
	]);
	pick([
		{ when: i.photoCount >= 25, id: 'photo-25', icon: 'photo_camera', label: 'Storyteller', detail: `${i.photoCount} run photos` },
		{ when: i.photoCount >= 1, id: 'photo-1', icon: 'photo_camera', label: 'Documented', detail: `${i.photoCount} run photo${i.photoCount === 1 ? '' : 's'}` },
	]);
	pick([
		{ when: i.distinctActivities >= 3, id: 'variety', icon: 'category', label: 'All-rounder', detail: `${i.distinctActivities} activity types` },
	]);
	pick([
		{ when: i.earliestStartLocal != null && i.earliestStartLocal < '06:00', id: 'early', icon: 'wb_twilight', label: 'Early bird', detail: `First steps at ${i.earliestStartLocal}` },
	]);
	pick([
		{ when: i.latestStartLocal != null && i.latestStartLocal >= '21:00', id: 'night', icon: 'bedtime', label: 'Night owl', detail: `Out at ${i.latestStartLocal}` },
	]);

	return out;
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
export function buildYearInRunningRecap(
	runs: Run[],
	year: number,
	extras: RecapExtras = {},
): YearInRunningRecap {
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

	// Activity-type tally off the real `runs.activity_type` column
	// (20261207_001). Treat missing values as "run" to match the default
	// elsewhere.
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

		// "Longest run" + "fastest pace" are run-family headline stats —
		// exclude cycling so a single long, fast bike ride doesn't masquerade
		// as the year's longest run / fastest pace in a "Year in Running"
		// card. Matches goals.ts's pace-eligibility filter. (Totals + the
		// most-used-activity tally stay all-inclusive — those are cross-modal
		// by design.)
		const isRunFamily = (r.activity_type ?? 'run') !== 'cycle';
		if (isRunFamily && r.distance_m > longest) longest = r.distance_m;

		// Pace, in s/km, only on runs with non-trivial distance so a 200 m
		// stroll doesn't dominate.
		if (isRunFamily && r.distance_m > 500 && r.duration_s > 0) {
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

		const activity = r.activity_type ?? 'run';
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

	const photoCount = Math.max(0, Math.trunc(extras.photoCount ?? 0));
	const personalRecordCount = Math.max(0, Math.trunc(extras.personalRecordCount ?? 0));
	const earliestStartLocal = earliestRun ? hhmm(earliestRun) : null;
	const latestStartLocal = latestRun ? hhmm(latestRun) : null;

	const badges = computeRecapBadges({
		totalDistanceM: totalDistance,
		runCount: inYear.length,
		bestStreakDays: streaks.best,
		totalElevationM: totalElevation,
		longestRunM: longest,
		activeMonths: monthly.filter((m) => m.runCount > 0).length,
		distinctActivities: activityCounts.size,
		earliestStartLocal,
		latestStartLocal,
		photoCount,
		personalRecordCount,
	});

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
		earliestStartLocal,
		latestStartLocal,
		monthly,
		topWeek,
		uniqueRouteCount: uniqueRoutes.size,
		mostUsedActivity,
		photoCount,
		personalRecordCount,
		badges,
	};
}

/**
 * Monthly recap — same engine, one calendar month. Reuses
 * `buildYearInRunningRecap` over the whole run set and projects out the
 * single requested month, so every per-run rule (run-family longest /
 * fastest, cross-modal totals, route + activity tallies) stays identical
 * to the annual card by construction. The headline numbers are re-derived
 * from the month's runs only; the month-scaled badges reuse the same
 * tier ladder (most year tiers simply won't trigger in a month, which is
 * the intended behaviour — a month-long streak in a single month is still
 * a month-long streak).
 *
 * `month` is 1-based (1=Jan … 12=Dec). Pass *all* runs; the helper filters
 * internally, and the streak still anchors at the end of the month.
 */
export function buildMonthInRunningRecap(
	runs: Run[],
	year: number,
	month: number,
	extras: RecapExtras = {},
): YearInRunningRecap {
	const yearRecap = buildYearInRunningRecap(runs, year, extras);
	const bucket = yearRecap.monthly[month - 1] ?? {
		month,
		distanceM: 0,
		durationS: 0,
		runCount: 0,
	};

	const inMonth: Run[] = [];
	for (const r of runs) {
		const d = new Date(r.started_at);
		if (d.getFullYear() === year && d.getMonth() + 1 === month) inMonth.push(r);
	}

	let totalElevation = 0;
	let longest = 0;
	let fastestPaceSecPerKm: number | null = null;
	let earliestMin: number | null = null;
	let latestMin: number | null = null;
	let earliestRun: Date | null = null;
	let latestRun: Date | null = null;
	const activityCounts = new Map<string, number>();
	const weeklyTotals = new Map<string, { distanceM: number; runCount: number }>();
	const uniqueRoutes = new Set<string>();

	for (const r of inMonth) {
		const d = new Date(r.started_at);
		totalElevation += elevationOf(r);
		const isRunFamily = (r.activity_type ?? 'run') !== 'cycle';
		if (isRunFamily && r.distance_m > longest) longest = r.distance_m;
		if (isRunFamily && r.distance_m > 500 && r.duration_s > 0) {
			const pace = r.duration_s / (r.distance_m / 1000);
			if (fastestPaceSecPerKm == null || pace < fastestPaceSecPerKm) fastestPaceSecPerKm = pace;
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
		const wk = mondayOf(d);
		const cur = weeklyTotals.get(wk) ?? { distanceM: 0, runCount: 0 };
		cur.distanceM += r.distance_m;
		cur.runCount += 1;
		weeklyTotals.set(wk, cur);
		if (r.route_id) uniqueRoutes.add(r.route_id);
		const activity = r.activity_type ?? 'run';
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

	const endOfMonth = new Date(year, month, 0, 23, 59); // day 0 of next month = last day of this
	const streaks = computeRunStreaks(
		runs.map((r) => new Date(r.started_at)),
		endOfMonth,
	);

	const photoCount = Math.max(0, Math.trunc(extras.photoCount ?? 0));
	const personalRecordCount = Math.max(0, Math.trunc(extras.personalRecordCount ?? 0));
	const earliestStartLocal = earliestRun ? hhmm(earliestRun) : null;
	const latestStartLocal = latestRun ? hhmm(latestRun) : null;

	const badges = computeRecapBadges({
		totalDistanceM: bucket.distanceM,
		runCount: bucket.runCount,
		bestStreakDays: streaks.best,
		totalElevationM: totalElevation,
		longestRunM: longest,
		activeMonths: bucket.runCount > 0 ? 1 : 0,
		distinctActivities: activityCounts.size,
		earliestStartLocal,
		latestStartLocal,
		photoCount,
		personalRecordCount,
	});

	return {
		year,
		month,
		runCount: bucket.runCount,
		totalDistanceM: bucket.distanceM,
		totalDurationS: bucket.durationS,
		totalElevationM: totalElevation,
		longestRunM: longest,
		fastestPaceSecPerKm,
		bestStreakDays: streaks.best,
		currentStreakDays: streaks.current,
		earliestStartLocal,
		latestStartLocal,
		monthly: yearRecap.monthly,
		topWeek,
		uniqueRouteCount: uniqueRoutes.size,
		mostUsedActivity,
		photoCount,
		personalRecordCount,
		badges,
	};
}

/** Smallish utility for the share-card copy. */
export function recapHeadline(recap: YearInRunningRecap, kmOrMi: 'km' | 'mi'): string {
	if (recap.runCount === 0) return `No runs in ${recap.year} yet.`;
	const total =
		kmOrMi === 'mi'
			? Math.round(recap.totalDistanceM / 1609.344) + ' mi'
			: Math.round(recap.totalDistanceM / 1000) + ' km';
	return `${recap.year}: ${total} across ${recap.runCount} runs.`;
}

export const __TEST_ONLY__ = { mondayOf, MS_PER_DAY };
