/// Multi-metric user goals, ported from `apps/mobile_android/lib/goals.dart`.
/// Four target kinds — distance, time, average pace, run count — over a
/// week or month period. Pace targets are distance-weighted and exclude
/// cycling (a single long bike ride would otherwise dominate the
/// average and make the metric meaningless for runners).
///
/// Stored in `localStorage` under a single JSON blob, mirroring the
/// local-first shape of the Android version. Not bag-synced today —
/// goals are highly personal and per-user, and the universal settings
/// bag is already carrying a scalar `weekly_mileage_goal_m` for the
/// simple case. When a user wants cross-device sync, promote this to
/// the bag as `run_goals` (array) with a new registered key.

import type { Run } from './types';

export type GoalPeriod = 'week' | 'month';

export interface RunGoal {
	id: string;
	period: GoalPeriod;
	title?: string;
	distanceMetres?: number;
	timeSeconds?: number;
	/// Lower-is-better target. Stored canonically as seconds per
	/// kilometre regardless of the user's display unit; the editor
	/// converts on the way in and out.
	paceSecPerKm?: number;
	runCount?: number;
}

export interface TargetProgress {
	kind: 'distance' | 'time' | 'pace' | 'runCount';
	label: string;
	currentLabel: string;
	targetLabel: string;
	percent: number;
	complete: boolean;
}

export interface GoalProgress {
	goal: RunGoal;
	targets: TargetProgress[];
	overallPercent: number;
	complete: boolean;
	runCount: number;
}

const STORAGE_KEY = 'run_app.goals_v1';

// Serialize to the Android-compatible snake_case wire format so goals
// survive a round-trip through backup/restore and the future settings-bag
// promotion. Aligns with goals.dart's toJson() keys.
function goalToWire(g: RunGoal): Record<string, unknown> {
	const w: Record<string, unknown> = { id: g.id, period: g.period };
	if (g.title != null) w.title = g.title;
	if (g.distanceMetres != null) w.distance_m = g.distanceMetres;
	if (g.timeSeconds != null) w.time_s = g.timeSeconds;
	if (g.paceSecPerKm != null) w.pace_s_per_km = g.paceSecPerKm;
	if (g.runCount != null) w.run_count = g.runCount;
	return w;
}

// Accept both the legacy camelCase keys (written by earlier web versions)
// and the canonical snake_case keys (Android + current web).
function goalFromWire(raw: Record<string, unknown>): RunGoal {
	return {
		id: raw.id as string,
		period: (raw.period as GoalPeriod) ?? 'week',
		title: (raw.title as string | undefined),
		distanceMetres: (raw.distance_m ?? raw.distanceMetres) as number | undefined,
		timeSeconds: (raw.time_s ?? raw.timeSeconds) as number | undefined,
		paceSecPerKm: (raw.pace_s_per_km ?? raw.paceSecPerKm) as number | undefined,
		runCount: (raw.run_count ?? raw.runCount) as number | undefined,
	};
}

export function loadGoals(): RunGoal[] {
	if (typeof localStorage === 'undefined') return [];
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		if (!raw) return [];
		const list = JSON.parse(raw);
		if (!Array.isArray(list)) return [];
		return list
			.filter((g) => g && typeof g === 'object' && typeof g.id === 'string')
			.map((g) => goalFromWire(g as Record<string, unknown>));
	} catch {
		return [];
	}
}

export function saveGoals(goals: RunGoal[]): void {
	if (typeof localStorage === 'undefined') return;
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(goals.map(goalToWire)));
	} catch {
		/* quota — noop */
	}
}

export function newGoalId(): string {
	return typeof crypto !== 'undefined' && 'randomUUID' in crypto
		? crypto.randomUUID()
		: `g_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export function periodStart(
	period: GoalPeriod,
	now: Date,
	weekStartDay: 'monday' | 'sunday' = 'monday',
): Date {
	const d = new Date(now);
	d.setHours(0, 0, 0, 0);
	if (period === 'week') {
		const offset = weekStartDay === 'sunday' ? d.getDay() : (d.getDay() + 6) % 7;
		d.setDate(d.getDate() - offset);
	} else {
		d.setDate(1);
	}
	return d;
}

export function periodEnd(period: GoalPeriod, now: Date, weekStartDay: 'monday' | 'sunday' = 'monday'): Date {
	const start = periodStart(period, now, weekStartDay);
	const end = new Date(start);
	if (period === 'week') {
		end.setDate(end.getDate() + 7);
	} else {
		end.setMonth(end.getMonth() + 1);
	}
	return end;
}

function formatKm(m: number): string {
	return `${(m / 1000).toFixed(1)} km`;
}

function formatMinutes(s: number): string {
	const h = Math.floor(s / 3600);
	const m = Math.floor((s % 3600) / 60);
	if (h > 0) return `${h}h ${m}m`;
	return `${m}m`;
}

/// `secondsPerKm` -> `mm:ss/km` (or "—" if zero / negative).
export function formatPaceSecPerKm(secPerKm: number): string {
	if (!isFinite(secPerKm) || secPerKm <= 0) return '—';
	const m = Math.floor(secPerKm / 60);
	const s = Math.round(secPerKm % 60);
	return `${m}:${s.toString().padStart(2, '0')}/km`;
}

/// Pure evaluator. Given a goal and the full run list, compute progress
/// per active target. Mirrors the shape of `evaluateGoal` in
/// `goals.dart` — active-target list, aggregate percent, overall
/// completion flag.
export function evaluateGoal(
	goal: RunGoal,
	runs: Run[],
	now: Date,
	weekStartDay: 'monday' | 'sunday' = 'monday',
): GoalProgress {
	const start = periodStart(goal.period, now, weekStartDay).getTime();
	const end = periodEnd(goal.period, now, weekStartDay).getTime();
	const inPeriod = runs.filter((r) => {
		const t = new Date(r.started_at).getTime();
		return t >= start && t < end;
	});
	const totalMetres = inPeriod.reduce((s, r) => s + r.distance_m, 0);
	const totalSeconds = inPeriod.reduce((s, r) => s + r.duration_s, 0);

	// Pace calculations exclude cycling — a distance-weighted average
	// would otherwise be dominated by a single long bike ride.
	const paceEligible = inPeriod.filter(
		(r) => (r.metadata?.['activity_type'] as string | undefined) !== 'cycle',
	);

	const targets: TargetProgress[] = [];

	if (goal.distanceMetres != null && goal.distanceMetres > 0) {
		const pct = Math.min(1, totalMetres / goal.distanceMetres);
		targets.push({
			kind: 'distance',
			label: 'Distance',
			currentLabel: formatKm(totalMetres),
			targetLabel: formatKm(goal.distanceMetres),
			percent: pct,
			complete: totalMetres >= goal.distanceMetres,
		});
	}
	if (goal.timeSeconds != null && goal.timeSeconds > 0) {
		const pct = Math.min(1, totalSeconds / goal.timeSeconds);
		targets.push({
			kind: 'time',
			label: 'Time',
			currentLabel: formatMinutes(totalSeconds),
			targetLabel: formatMinutes(goal.timeSeconds),
			percent: pct,
			complete: totalSeconds >= goal.timeSeconds,
		});
	}
	if (goal.paceSecPerKm != null && goal.paceSecPerKm > 0) {
		const paceMetres = paceEligible.reduce((s, r) => s + r.distance_m, 0);
		const paceSeconds = paceEligible.reduce((s, r) => s + r.duration_s, 0);
		const current = paceMetres > 10 ? paceSeconds / (paceMetres / 1000) : 0;
		// Lower-is-better. If we don't yet have any running data, percent
		// is 0; if we beat the target, 100; otherwise (target / current).
		let percent: number;
		let complete: boolean;
		if (current <= 0) {
			percent = 0;
			complete = false;
		} else if (current <= goal.paceSecPerKm) {
			percent = 1;
			complete = true;
		} else {
			percent = Math.max(0, Math.min(1, goal.paceSecPerKm / current));
			complete = false;
		}
		targets.push({
			kind: 'pace',
			label: 'Avg pace',
			currentLabel: current > 0 ? formatPaceSecPerKm(current) : '—',
			targetLabel: formatPaceSecPerKm(goal.paceSecPerKm),
			percent,
			complete,
		});
	}
	if (goal.runCount != null && goal.runCount > 0) {
		const pct = Math.min(1, inPeriod.length / goal.runCount);
		targets.push({
			kind: 'runCount',
			label: 'Runs',
			currentLabel: `${inPeriod.length}`,
			targetLabel: `${goal.runCount}`,
			percent: pct,
			complete: inPeriod.length >= goal.runCount,
		});
	}

	const overall =
		targets.length === 0
			? 0
			: targets.reduce((s, t) => s + t.percent, 0) / targets.length;
	const complete = targets.length > 0 && targets.every((t) => t.complete);

	return {
		goal,
		targets,
		overallPercent: overall,
		complete,
		runCount: inPeriod.length,
	};
}

export function periodLabel(period: GoalPeriod): string {
	return period === 'week' ? 'This week' : 'This month';
}
