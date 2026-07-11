/**
 * Plan-progress derivations — the two stats the plan-detail header was
 * missing: the longest long run completed so far, and the overall
 * base→build→peak→taper arc the current week sits in. Pure (no Supabase
 * / DOM); the UI formats + localizes the results.
 */

/// Canonical phase ordering. Plans don't always use every phase, and the
/// rows aren't guaranteed to be stored in order, so the marker derives
/// its sequence from this rather than from row order.
export const PLAN_PHASE_ORDER = ['base', 'build', 'peak', 'taper', 'race'] as const;
export type PlanPhaseName = (typeof PLAN_PHASE_ORDER)[number];

/// The distinct phases the plan moves through, de-duplicated and sorted
/// into canonical order. Drives the overall phase marker.
export function orderedPlanPhases(weeks: { phase: string }[]): PlanPhaseName[] {
	const present = new Set(weeks.map((w) => w.phase));
	return PLAN_PHASE_ORDER.filter((p) => present.has(p));
}

interface LongRunWorkout {
	kind: string;
	target_distance_m: number | null;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
}

/// Longest long run completed so far, in metres. Prefers the actual
/// recorded distance of the linked run (looked up in `actualById` by
/// run id); falls back to the workout's planned target when the run
/// isn't in the supplied map (e.g. it dropped off the recent-runs
/// window). Returns null when no long run has been completed yet.
export function longestCompletedLongRunMetres(
	workouts: LongRunWorkout[],
	actualById: Map<string, number> = new Map(),
): number | null {
	let max: number | null = null;
	for (const w of workouts) {
		if (w.kind !== 'long') continue;
		const completed = w.manually_completed === true || w.completed_run_id != null;
		if (!completed) continue;
		const actual = w.completed_run_id != null ? actualById.get(w.completed_run_id) : undefined;
		// A non-positive actual (degenerate / distance-less linked run) is
		// treated as missing, falling back to the planned target — `actual ??`
		// would keep a 0 and drop the long run from the max entirely.
		const dist = actual != null && actual > 0 ? actual : (w.target_distance_m ?? 0);
		if (dist > 0 && (max == null || dist > max)) max = dist;
	}
	return max;
}

interface DistanceWorkout {
	kind: string;
	target_distance_m: number | null;
	completed_run_id?: string | null;
	manually_completed?: boolean | null;
	skipped_at?: string | null;
}

export interface PlanDistanceProgress {
	/// Total metres actually banked so far — completed workouts only,
	/// preferring the linked run's real distance over the planned target.
	completedMetres: number;
	/// Total metres the plan asks for — every non-rest workout still on the
	/// books (skipped workouts drop out, mirroring the progress ring).
	plannedMetres: number;
}

/// Plan-wide distance banked vs planned, in metres. The workout-count
/// progress ring can read 80% off a run of short easy days while the real
/// training volume lags; this is the mileage view of the same plan.
///
/// `plannedMetres` sums every non-rest, non-skipped workout's target — a
/// deliberately skipped session leaves the denominator (same rule as the
/// ring) so a skipped long run doesn't make the runner look permanently
/// behind. `completedMetres` sums completed workouts, preferring the linked
/// run's actual distance (looked up in `actualById`) over the planned
/// target — so over- and under-running both show honestly, and it can
/// exceed `plannedMetres` when the runner banks more than prescribed.
export function planDistanceBanked(
	workouts: DistanceWorkout[],
	actualById: Map<string, number> = new Map(),
): PlanDistanceProgress {
	let completedMetres = 0;
	let plannedMetres = 0;
	for (const w of workouts) {
		if (w.kind === 'rest') continue;
		const skipped = w.skipped_at != null;
		const completed = w.manually_completed === true || w.completed_run_id != null;
		if (!skipped) plannedMetres += w.target_distance_m ?? 0;
		if (completed) {
			const actual =
				w.completed_run_id != null ? actualById.get(w.completed_run_id) : undefined;
			completedMetres += actual != null && actual > 0 ? actual : (w.target_distance_m ?? 0);
		}
	}
	return { completedMetres, plannedMetres };
}
