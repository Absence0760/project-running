/// Pure challenge progress + ranking helpers, shared with the mobile twin
/// (apps/mobile_android/lib/challenge_progress.dart). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// `metricFromActivity` is the SAME metric-extraction the SQL aggregate
/// (challenge_leaderboard / recompute_challenge_completion) performs, so an
/// offline-optimistic client estimate computed from local stores can't drift
/// from the server board.

export type ChallengeMetric = 'distance' | 'duration' | 'vert' | 'activity_count' | 'streak_days';

/** Fraction of the goal reached, clamped to 0..1. Null goal (pure-ranking
 * board) → null: there is no bar to fill. */
export function progressFraction(value: number, goal: number | null): number | null {
	if (goal === null || goal <= 0) return null;
	const frac = value / goal;
	if (frac < 0) return 0;
	if (frac > 1) return 1;
	return frac;
}

/** True once the goal is met (>=). Null goal → false (nothing to complete). */
export function isComplete(value: number, goal: number | null): boolean {
	if (goal === null || goal <= 0) return false;
	return value >= goal;
}

/** Locale/unit-agnostic structured parts for a progress label. The CALLER
 * localises + unit-formats (km/mi, h/m, count, days) — this layer only carries
 * the raw numbers + the metric so formatting stays a single concern at the UI
 * edge. `fraction` is null for a goal-less board. */
export interface ProgressParts {
	metric: ChallengeMetric;
	value: number;
	goal: number | null;
	fraction: number | null;
	complete: boolean;
}

export function progressParts(
	metric: ChallengeMetric,
	value: number,
	goal: number | null,
): ProgressParts {
	return {
		metric,
		value,
		goal,
		fraction: progressFraction(value, goal),
		complete: isComplete(value, goal),
	};
}

/** One activity's contribution to a metric. `summary` mirrors the activities
 * view's summary jsonb (distance_m / duration_s strings). For activity_count
 * and streak_days a single activity always contributes 1 (the day-distinctness
 * of streak_days is resolved by the caller over a day-set, not per activity).
 * Returns 0 when the activity type doesn't match the filter, or when the run is
 * a DNF — mirroring the server aggregate (`challenge_leaderboard` /
 * `recompute_challenge_completion`, ADR 231), which excludes DNF'd runs from
 * every metric, so a client-side optimistic estimate can't drift by counting a
 * just-DNF'd run's distance. `is_dnf` rides the activities-view runs summary
 * (migration `20270408_001`); gym/meal activities never carry it. */
export function metricFromActivity(
	summary: {
		distance_m?: number | string | null;
		duration_s?: number | string | null;
		elevation_gain_m?: number | string | null;
		activity_type?: string | null;
		is_dnf?: boolean | null;
	},
	metric: ChallengeMetric,
	activityTypeFilter: string | null,
): number {
	if (activityTypeFilter !== null && (summary.activity_type ?? 'run') !== activityTypeFilter) {
		return 0;
	}
	if (summary.is_dnf === true) return 0;
	switch (metric) {
		case 'distance':
			return numberOf(summary.distance_m);
		case 'duration':
			return numberOf(summary.duration_s);
		case 'vert':
			return numberOf(summary.elevation_gain_m);
		case 'activity_count':
			return 1;
		case 'streak_days':
			return 1;
	}
}

function numberOf(v: number | string | null | undefined): number {
	if (v === null || v === undefined) return 0;
	const n = typeof v === 'number' ? v : Number(v);
	return Number.isFinite(n) ? n : 0;
}

export interface RankableEntry {
	user_id: string | null;
	team_club_id?: string | null;
	value: number;
}

export interface RankedEntry<T extends RankableEntry> {
	entry: T;
	rank: number;
}

/** Deterministic leaderboard ordering + dense rank assignment, mirroring the
 * SQL `rank() over (order by value desc)` plus a stable tie-break: value
 * descending, then user_id ascending (team_club_id for a team board), so two
 * refreshes never swap equal rows. Equal values share a rank (1,1,3 — standard
 * competition ranking, matching SQL `rank()`). */
export function rankParticipants<T extends RankableEntry>(entries: T[]): RankedEntry<T>[] {
	const sorted = [...entries].sort(compareEntries);
	const out: RankedEntry<T>[] = [];
	let rank = 0;
	let seen = 0;
	let prevValue: number | null = null;
	for (const entry of sorted) {
		seen += 1;
		if (prevValue === null || entry.value !== prevValue) {
			rank = seen;
			prevValue = entry.value;
		}
		out.push({ entry, rank });
	}
	return out;
}

function compareEntries(a: RankableEntry, b: RankableEntry): number {
	const byValue = b.value - a.value;
	if (byValue !== 0) return byValue;
	const ak = a.user_id ?? a.team_club_id ?? '';
	const bk = b.user_id ?? b.team_club_id ?? '';
	return ak < bk ? -1 : ak > bk ? 1 : 0;
}

const DAY_MS = 86_400_000;

/** Tolerance band around the even-pace line inside which a runner counts as
 * "on track" rather than ahead/behind — ±5 %. Shared with the Dart twin so the
 * verdict is identical on both platforms. */
export const ON_PACE_BAND = 0.05;

export type ChallengePaceStatus = 'upcoming' | 'active' | 'ended';
export type PaceVerdict = 'ahead' | 'on_track' | 'behind';

/** Locale/unit-agnostic on-pace projection for a time-boxed goal challenge. The
 * CALLER localises + unit-formats the numbers — this layer carries raw metric
 * units + the verdict enum. Everything goal-derived is null on a goal-less
 * (pure-ranking) board. */
export interface ChallengePace {
	status: ChallengePaceStatus;
	/** Fraction of the challenge window elapsed at `nowMs`, clamped 0..1. */
	elapsedFraction: number;
	/** Whole days until the window closes (ceil), floored at 0. */
	daysRemaining: number;
	/** Where an even-paced runner would be at `nowMs` (goal × elapsedFraction). */
	expectedValue: number | null;
	/** Linear projection of the final value from the current rate
	 * (value / elapsedFraction). Null before the window opens (no rate yet);
	 * equals the frozen `value` once it has closed. */
	projectedValue: number | null;
	/** Metric units still needed to reach the goal (goal − value), floored at 0. */
	remainingValue: number | null;
	/** Metric units per day needed over the remaining window to still finish.
	 * Null once complete, with no days left, or the window has closed. */
	requiredPerDay: number | null;
	/** ahead / on_track / behind vs the even-pace line, within `ON_PACE_BAND`.
	 * Null outside the active window or once the goal is already met. */
	verdict: PaceVerdict | null;
}

/** Project a joined runner's standing in a time-boxed goal challenge: where the
 * even-pace line sits now, whether they're ahead/behind it, and the daily rate
 * still needed to finish. All times are epoch ms so the helper stays pure and
 * timezone-free (the caller parses the ISO window). Mirrors the SQL-fed value
 * exactly — it only re-shapes the numbers the leaderboard already computed. */
export function challengePace(
	value: number,
	goal: number | null,
	startMs: number,
	endMs: number,
	nowMs: number,
): ChallengePace {
	const hasGoal = goal !== null && goal > 0;

	let status: ChallengePaceStatus;
	let elapsedFraction: number;
	if (nowMs < startMs) {
		status = 'upcoming';
		elapsedFraction = 0;
	} else if (nowMs >= endMs || endMs <= startMs) {
		status = 'ended';
		elapsedFraction = 1;
	} else {
		status = 'active';
		elapsedFraction = (nowMs - startMs) / (endMs - startMs);
	}

	const daysRemaining = Math.max(0, Math.ceil((endMs - nowMs) / DAY_MS));
	const expectedValue = hasGoal ? goal! * elapsedFraction : null;
	const remainingValue = hasGoal ? Math.max(0, goal! - value) : null;

	let projectedValue: number | null = null;
	if (hasGoal && status === 'active' && elapsedFraction > 0) {
		projectedValue = value / elapsedFraction;
	} else if (hasGoal && status === 'ended') {
		projectedValue = value;
	}

	let requiredPerDay: number | null = null;
	if (hasGoal && status !== 'ended' && daysRemaining > 0 && remainingValue! > 0) {
		requiredPerDay = remainingValue! / daysRemaining;
	}

	let verdict: PaceVerdict | null = null;
	if (hasGoal && status === 'active' && value < goal! && expectedValue! > 0) {
		const ratio = value / expectedValue!;
		if (ratio >= 1 + ON_PACE_BAND) verdict = 'ahead';
		else if (ratio < 1 - ON_PACE_BAND) verdict = 'behind';
		else verdict = 'on_track';
	}

	return {
		status,
		elapsedFraction,
		daysRemaining,
		expectedValue,
		projectedValue,
		remainingValue,
		requiredPerDay,
		verdict,
	};
}
