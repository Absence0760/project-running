/**
 * Pure candidate-selection logic for the workout re-link picker.
 *
 * Re-linking a completed run to a different planned workout must not
 * let one run count toward two workouts' `plan_progress` — so the
 * picker must NOT offer a run that's already linked (auto-matched or
 * manually) to *another* workout. The data layer fetches the owner's
 * runs + the set of run ids already linked anywhere in the owner's
 * plans; this function decides which of those runs are eligible, and
 * in what order, for a given workout.
 *
 * Kept pure (no Supabase, no auth) so it can be unit-tested directly —
 * the data-layer wrapper in `core/data.ts` is exercised by Playwright.
 */

export interface RelinkCandidateRun {
	id: string;
	/** ISO timestamp the run started (`runs.started_at`). */
	started_at: string;
	/** Metres covered (`runs.distance_m`). */
	distance_m: number;
	/** Seconds of moving/elapsed time (`runs.duration_s`). */
	duration_s: number;
}

export interface RelinkFilterInput {
	/** The owner's runs, any order. */
	runs: RelinkCandidateRun[];
	/**
	 * Run ids already linked (via `completed_run_id`) to ANY of the
	 * owner's plan workouts — including the workout being re-linked.
	 */
	linkedRunIds: Iterable<string>;
	/**
	 * The current `completed_run_id` of the workout being re-linked, if
	 * any. It lives in `linkedRunIds` but must stay selectable so the
	 * picker can show the current pick (and re-confirming it is a no-op
	 * rather than a hidden row). Pass null when the workout is unlinked.
	 */
	currentRunId: string | null;
	/** The workout's `scheduled_date` (ISO `YYYY-MM-DD`). */
	scheduledDate: string;
	/**
	 * Half-window in days around `scheduledDate`; a run started within
	 * ±windowDays of the scheduled date is in-window. Defaults to 7.
	 */
	windowDays?: number;
}

const MS_PER_DAY = 86_400_000;
export const DEFAULT_RELINK_WINDOW_DAYS = 7;

/** Calendar-day distance between a run's start and the scheduled date. */
function dayGap(runStartIso: string, scheduledDate: string): number {
	const a = new Date(runStartIso);
	// Compare against the scheduled calendar date at local midnight.
	const [y, m, d] = scheduledDate.split('-').map(Number);
	const scheduled = new Date(y, (m ?? 1) - 1, d ?? 1);
	const runDay = new Date(a.getFullYear(), a.getMonth(), a.getDate());
	return Math.abs(Math.round((runDay.getTime() - scheduled.getTime()) / MS_PER_DAY));
}

/**
 * Eligible re-link candidates for a workout, newest-first.
 *
 * A run is eligible when it is in-window (within ±windowDays of the
 * scheduled date) AND not already linked to a *different* workout. The
 * workout's own current run stays eligible regardless of window so the
 * current pick is always visible.
 */
export function filterRelinkCandidates(
	input: RelinkFilterInput
): RelinkCandidateRun[] {
	const window = input.windowDays ?? DEFAULT_RELINK_WINDOW_DAYS;
	const linked = new Set(input.linkedRunIds);
	// The current run is allowed even though it's in `linked`.
	if (input.currentRunId) linked.delete(input.currentRunId);

	return input.runs
		.filter((r) => {
			// Never offer a run linked to another workout — that would
			// double-count it in plan_progress.
			if (linked.has(r.id)) return false;
			// The current pick is always in; everything else must be
			// inside the date window.
			if (r.id === input.currentRunId) return true;
			return dayGap(r.started_at, input.scheduledDate) <= window;
		})
		.sort(
			(a, b) =>
				new Date(b.started_at).getTime() - new Date(a.started_at).getTime()
		);
}
