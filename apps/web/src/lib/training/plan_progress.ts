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
		const dist = actual ?? w.target_distance_m ?? 0;
		if (dist > 0 && (max == null || dist > max)) max = dist;
	}
	return max;
}
