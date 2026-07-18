/// Pure window contract for the dashboard's recency run fetch, kept out
/// of `data.ts` so it is unit-testable (data.ts pulls in the supabase
/// singleton + `$env`, which the tsx test runner can't load).
///
/// The dashboard reasons only about *recent* training — the 90-day load
/// curve, the last-12-weeks consistency card, the race predictor's
/// recency-weighted anchor, this-week / goal roll-ups, the current streak
/// and the recent-runs list. A generous 2-year window covers all of them
/// while sparing the highest-traffic page the unbounded `select('*')`
/// history scan. Lifetime headline stats (total runs, longest run) are
/// served by a separate cheap aggregate, not this window.

export const DASHBOARD_RUNS_WINDOW_DAYS = 730;

/// The ISO-less Date cutoff `fetchRunsForDashboard` filters `started_at`
/// against: `now` minus the window. Callers pass the query's
/// `.gte('started_at', dashboardRunsWindowStart(new Date()).toISOString())`.
export function dashboardRunsWindowStart(now: Date): Date {
	const start = new Date(now);
	start.setDate(start.getDate() - DASHBOARD_RUNS_WINDOW_DAYS);
	return start;
}
