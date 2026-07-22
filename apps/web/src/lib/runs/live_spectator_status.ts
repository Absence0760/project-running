/// Status decisions for the /live/[id] spectator surface (issue #603).
/// The page must never fabricate movement: a real run with no live data
/// resolves to an honest `finished` or `waiting` state, decided from the
/// saved row + whether any ping backlog survived. Kept pure so the
/// boundaries are unit-testable; the page glue is e2e-tested.

/// A saved end this far in the past is unambiguous even with clock skew
/// between the recorder's phone and the viewer's browser.
export const FINISHED_SLACK_MS = 2 * 60 * 1000;

export type PostHydrateStatus = 'live' | 'finished' | 'waiting';

function runEndMs(startedAtIso: string, durationS: number): number | null {
	if (!durationS || durationS <= 0) return null;
	const startMs = new Date(startedAtIso).getTime();
	if (!Number.isFinite(startMs)) return null;
	return startMs + durationS * 1000;
}

/// The stale-share-link fast path: the row already places the run's end
/// comfortably in the past, so the page can freeze on the saved totals
/// without opening realtime at all. `duration_s` can be a *projected*
/// duration while a run is in progress (fixtures / race entries), so a
/// zero or future end never counts as finished here.
export function isFinishedStale(
	startedAtIso: string,
	durationS: number,
	nowMs: number,
): boolean {
	const end = runEndMs(startedAtIso, durationS);
	return end != null && end < nowMs - FINISHED_SLACK_MS;
}

/// Decide the page state once the ping backlog has been checked.
///
/// - Any surviving backlog wins: pings are ground truth, the run renders
///   live whatever the row's duration claims.
/// - No backlog + the row's end already passed → `finished`. This is the
///   reload-just-after-stopping case: the recorder wipes `live_run_pings`
///   on stop and the saved row carries the final duration, but the end is
///   still inside FINISHED_SLACK_MS — the old code fell through to the
///   synthesised demo loop here (issue #603).
/// - Otherwise → `waiting`: an in-progress broadcast stub (duration 0)
///   whose first ping hasn't arrived, or a projected end still in the
///   future. The caller keeps the subscription open.
export function statusAfterHydrate(opts: {
	startedAtIso: string;
	durationS: number;
	hadBacklog: boolean;
	nowMs: number;
}): PostHydrateStatus {
	if (opts.hadBacklog) return 'live';
	const end = runEndMs(opts.startedAtIso, opts.durationS);
	if (end != null && end <= opts.nowMs) return 'finished';
	return 'waiting';
}
