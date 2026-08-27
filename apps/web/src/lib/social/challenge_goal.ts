/// Pure challenge-goal entry helpers, shared with the mobile twin
/// (apps/mobile_android/lib/challenge_goal.dart). Keep the two in lockstep:
/// algorithm, edge cases, outputs, and test counts must match.
///
/// `challenges.goal_value` is stored in the unit the SQL aggregate sums in —
/// metres for `distance` and `vert`, seconds for `duration`, a bare count for
/// `activity_count` and `streak_days`. That is not what a person types: nobody
/// enters a 100 km challenge as `100000`. `challengeGoalUnit` names the unit
/// the field asks for and `challengeGoalToStored` is the conversion into the
/// column, the same entry/exit split `paceSecPerUnit` / `paceSecPerKm` keeps
/// for a typed pace.
///
/// `checkChallengeGoal` is the client half of `challenges_goal_ck` (migration
/// `20270615_001`): both halves must agree, or a refusal the constraint makes
/// reaches the author as a raw postgres 23514 naming neither bound.

import type { ChallengeMetric } from './challenge_progress';

const METRES_PER_MILE = 1609.344;
const FEET_PER_METRE = 3.28084;
const SECONDS_PER_HOUR = 3600;
const DAY_MS = 86_400_000;

/// The kind of unit a goal for a metric is typed in. `distance` and
/// `elevation` resolve further against the reader's own km/mi preference;
/// the other three are preference-free.
export type ChallengeGoalUnit = 'distance' | 'elevation' | 'hours' | 'activities' | 'days';

export function challengeGoalUnit(metric: ChallengeMetric): ChallengeGoalUnit {
	switch (metric) {
		case 'duration':
			return 'hours';
		case 'vert':
			return 'elevation';
		case 'activity_count':
			return 'activities';
		case 'streak_days':
			return 'days';
		case 'distance':
			return 'distance';
	}
}

/// A goal typed in the unit `challengeGoalUnit` names, converted into the unit
/// `challenges.goal_value` and the leaderboard aggregate both use.
export function challengeGoalToStored(
	typed: number,
	metric: ChallengeMetric,
	unit: 'km' | 'mi',
): number {
	switch (challengeGoalUnit(metric)) {
		case 'hours':
			return typed * SECONDS_PER_HOUR;
		case 'elevation':
			return unit === 'mi' ? typed / FEET_PER_METRE : typed;
		case 'distance':
			return unit === 'mi' ? typed * METRES_PER_MILE : typed * 1000;
		case 'activities':
		case 'days':
			return typed;
	}
}

/// The inverse, for pre-filling the editor with an existing challenge's goal.
/// Web-only: editing an existing challenge has no mobile surface (§ 24), so
/// the Dart twin carries no counterpart.
export function challengeGoalFromStored(
	stored: number,
	metric: ChallengeMetric,
	unit: 'km' | 'mi',
): number {
	switch (challengeGoalUnit(metric)) {
		case 'hours':
			return stored / SECONDS_PER_HOUR;
		case 'elevation':
			return unit === 'mi' ? stored * FEET_PER_METRE : stored;
		case 'distance':
			return unit === 'mi' ? stored / METRES_PER_MILE : stored / 1000;
		case 'activities':
		case 'days':
			return stored;
	}
}

/// The most distinct active days a `streak_days` board can ever count inside
/// `[startMs, endMs)`.
///
/// The aggregate counts `count(distinct (started_at at time zone 'UTC')::date)`
/// over the half-open window, so the ceiling is the number of calendar dates a
/// window of that length can touch — maximised when it opens just after
/// midnight, which is `floor(length / one day) + 1`. Deliberately the LOOSE
/// bound: a window ending exactly at midnight UTC touches one date fewer, and
/// refusing a goal the aggregate could in principle award is worse than
/// admitting one it cannot. `challenges_goal_ck` computes the same expression
/// in SQL, so the two never disagree on a row that can exist.
///
/// 0 for a window that is empty or inverted — `challenges_window_ck` refuses
/// those outright and the caller flags the window before the goal.
export function maxStreakDaysInWindow(startMs: number, endMs: number): number {
	if (!Number.isFinite(startMs) || !Number.isFinite(endMs)) return 0;
	if (endMs <= startMs) return 0;
	return Math.floor((endMs - startMs) / DAY_MS) + 1;
}

/// Why a stored goal cannot be saved. `not_positive` covers the whole
/// non-positive range including 0: the completion RPC compares `value >= goal`
/// with no floor, so a stored 0 awards the badge to every participant on the
/// nightly sweep while both clients render the challenge as goal-less.
export type ChallengeGoalRefusal = 'not_positive' | 'exceeds_window';

/// Grade a STORED goal against the row it would be written to. Null goal —
/// a pure-ranking board — is always fine. Null when the goal is acceptable.
export function checkChallengeGoal(
	stored: number | null,
	metric: ChallengeMetric,
	startMs: number,
	endMs: number,
): ChallengeGoalRefusal | null {
	if (stored === null) return null;
	if (!Number.isFinite(stored) || stored <= 0) return 'not_positive';
	// Only streak_days is bounded by the window. A `duration` goal is NOT:
	// the aggregate sums `duration_s` over runs whose START falls inside the
	// window, and a run started a minute before it closes carries its whole
	// duration — a 112-hour Moab finish included. The other three metrics are
	// unbounded outright.
	if (metric === 'streak_days' && stored > maxStreakDaysInWindow(startMs, endMs)) {
		return 'exceeds_window';
	}
	return null;
}
