/**
 * Week-over-week and month-over-month trend deltas for the dashboard summary
 * stats (backlog #11, advanced analytics polish).
 *
 * Reports how the runner's distance / time / run-count is trending by comparing
 * the CURRENT period-to-date against the SAME to-date window of the PRIOR
 * period — week-to-date vs prior-week-to-date, month-to-date vs
 * prior-month-to-date. Comparing equal-length elapsed windows is what keeps a
 * mid-week glance honest: a partial current week is measured against the same
 * partial slice of last week, not against last week's full total (which would
 * always read "down" until the week is over).
 *
 * All boundaries are LOCAL-time and honour the `week_start_day` preference, so
 * the week delta agrees with the dashboard's "This Week" stat card and the
 * ThisWeekStrip ribbon that sit beside it.
 *
 * Pure: no Supabase, no DOM, no rune state — unit-tested under `tsx --test`.
 * Web-only by design (no Dart twin); deliberately kept off the enforced
 * web↔mobile parity list.
 */

export type WeekStartDay = 'monday' | 'sunday';
export type TrendDirection = 'up' | 'down' | 'flat';

export interface MetricDelta {
	current: number;
	prior: number;
	/// current - prior (signed).
	delta: number;
	direction: TrendDirection;
	/// Rounded percentage change vs the prior window; null when the prior
	/// window is zero (a % change off a zero base is undefined, not infinite).
	pct: number | null;
}

export interface PeriodTrend {
	distanceM: MetricDelta;
	durationS: MetricDelta;
	runs: MetricDelta;
}

export interface TrendDeltas {
	week: PeriodTrend;
	month: PeriodTrend;
}

interface RunLike {
	started_at: string;
	distance_m: number;
	duration_s: number;
}

interface WindowTotals {
	distanceM: number;
	durationS: number;
	runs: number;
}

function summarise(runs: RunLike[], startMs: number, endMs: number): WindowTotals {
	let distanceM = 0;
	let durationS = 0;
	let count = 0;
	for (const r of runs) {
		const t = new Date(r.started_at).getTime();
		if (!Number.isFinite(t) || t < startMs || t >= endMs) continue;
		distanceM += Number.isFinite(r.distance_m) ? r.distance_m : 0;
		durationS += Number.isFinite(r.duration_s) ? r.duration_s : 0;
		count += 1;
	}
	return { distanceM, durationS, runs: count };
}

function metric(current: number, prior: number): MetricDelta {
	const delta = current - prior;
	const direction: TrendDirection = delta > 0 ? 'up' : delta < 0 ? 'down' : 'flat';
	const pct = prior > 0 ? Math.round((delta / prior) * 100) : null;
	return { current, prior, delta, direction, pct };
}

function trendFor(cur: WindowTotals, prev: WindowTotals): PeriodTrend {
	return {
		distanceM: metric(cur.distanceM, prev.distanceM),
		durationS: metric(cur.durationS, prev.durationS),
		runs: metric(cur.runs, prev.runs),
	};
}

function startOfWeek(now: Date, weekStart: WeekStartDay): Date {
	const ws = new Date(now);
	const offset = weekStart === 'sunday' ? now.getDay() : (now.getDay() + 6) % 7;
	ws.setDate(now.getDate() - offset);
	ws.setHours(0, 0, 0, 0);
	return ws;
}

const WEEK_MS = 7 * 86_400_000;

export function computeTrendDeltas(
	runs: RunLike[],
	weekStart: WeekStartDay = 'monday',
	now: Date = new Date(),
): TrendDeltas {
	const nowMs = now.getTime();

	// Week-to-date vs the same slice of last week.
	const weekStartMs = startOfWeek(now, weekStart).getTime();
	const weekElapsed = nowMs - weekStartMs;
	const priorWeekStartMs = weekStartMs - WEEK_MS;
	const priorWeekEndMs = priorWeekStartMs + weekElapsed;
	const week = trendFor(
		summarise(runs, weekStartMs, nowMs),
		summarise(runs, priorWeekStartMs, priorWeekEndMs),
	);

	// Month-to-date vs the same slice of last month. Cap the prior window at
	// the current month's start so a longer current month can't bleed the
	// comparison into days that already belong to this month.
	const monthStartMs = new Date(now.getFullYear(), now.getMonth(), 1).getTime();
	const monthElapsed = nowMs - monthStartMs;
	const prevMonthStartMs = new Date(now.getFullYear(), now.getMonth() - 1, 1).getTime();
	const priorMonthEndMs = Math.min(prevMonthStartMs + monthElapsed, monthStartMs);
	const month = trendFor(
		summarise(runs, monthStartMs, nowMs),
		summarise(runs, prevMonthStartMs, priorMonthEndMs),
	);

	return { week, month };
}
