/// Pure helpers for the "Route History" panel on `/runs/[id]`.
///
/// Mirrors `_buildRouteComparison` in
/// `apps/mobile_android/lib/screens/run_detail_screen.dart`: filter to
/// runs on the same route + same activity_type with > 100 m of
/// movement, sort by duration ascending, then summarise the current
/// run's standing (PB / behind PB / rank). Kept pure so the component
/// stays a thin presenter and the logic is unit-testable without DOM.

export interface RouteHistoryRun {
	id: string;
	route_id: string | null;
	distance_m: number;
	duration_s: number;
	metadata?: Record<string, unknown> | null;
}

export interface RouteHistorySummary {
	rank: number;
	total: number;
	pb: RouteHistoryRun;
	isPb: boolean;
	deltaSeconds: number;
}

/// Filter to qualifying attempts on the same route + activity type
/// and sort by duration ascending. Returns the trimmed list.
///
/// Match rules (mirroring mobile):
///  - Same `route_id` (a run with no route is excluded — the panel
///    doesn't render in that case anyway).
///  - `distance_m > 100` — guards against accidental starts that
///    never moved off the start line and would otherwise look like
///    incredible PBs.
///  - Same `metadata.activity_type` (default `'run'`). A walk on
///    the same route shouldn't compete with a run.
export function qualifyingAttempts(
	currentRun: RouteHistoryRun,
	allRuns: readonly RouteHistoryRun[],
): RouteHistoryRun[] {
	if (!currentRun.route_id) return [];
	const thisActivity =
		(currentRun.metadata?.['activity_type'] as string | undefined) ?? 'run';
	return [...allRuns]
		.filter(
			(r) =>
				r.route_id === currentRun.route_id &&
				r.distance_m > 100 &&
				((r.metadata?.['activity_type'] as string | undefined) ?? 'run') ===
					thisActivity,
		)
		.sort((a, b) => a.duration_s - b.duration_s);
}

/// Build the summary row the component renders. Returns `null` when
/// there's nothing meaningful to show — caller should hide the card
/// rather than render an empty state.
export function summariseHistory(
	currentRunId: string,
	attempts: readonly RouteHistoryRun[],
): RouteHistorySummary | null {
	if (attempts.length < 2) return null;
	const pb = attempts[0];
	const idx = attempts.findIndex((r) => r.id === currentRunId);
	if (idx < 0) return null;
	const current = attempts[idx];
	return {
		rank: idx + 1,
		total: attempts.length,
		pb,
		isPb: pb.id === currentRunId,
		deltaSeconds: current.duration_s - pb.duration_s,
	};
}

/// "+1:23" / "−0:45" / "0:00". Sign is always rendered. Used for the
/// "behind PB" line.
export function formatSignedDelta(seconds: number): string {
	const sign = seconds > 0 ? '+' : seconds < 0 ? '−' : '';
	const total = Math.abs(seconds);
	const h = Math.floor(total / 3600);
	const m = Math.floor((total % 3600) / 60);
	const s = total % 60;
	if (h > 0) {
		return `${sign}${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	}
	return `${sign}${m}:${String(s).padStart(2, '0')}`;
}
