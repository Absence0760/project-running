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
 * Returns 0 when the activity type doesn't match the filter. */
export function metricFromActivity(
	summary: {
		distance_m?: number | string | null;
		duration_s?: number | string | null;
		elevation_gain_m?: number | string | null;
		activity_type?: string | null;
	},
	metric: ChallengeMetric,
	activityTypeFilter: string | null,
): number {
	if (activityTypeFilter !== null && (summary.activity_type ?? 'run') !== activityTypeFilter) {
		return 0;
	}
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
