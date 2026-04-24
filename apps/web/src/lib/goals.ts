/// Multi-metric user goals, ported in spirit from
/// `apps/mobile_android/lib/goals.dart`. The web version intentionally
/// ships a narrower subset for now — distance / time / run-count
/// targets, week or month period. Avg-pace targets are the most
/// complex metric on Android (cycling-aware, distance-weighted) and
/// the least commonly used; revisit when a user actually asks.
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
	runCount?: number;
}

export interface TargetProgress {
	kind: 'distance' | 'time' | 'runCount';
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

export function loadGoals(): RunGoal[] {
	if (typeof localStorage === 'undefined') return [];
	try {
		const raw = localStorage.getItem(STORAGE_KEY);
		if (!raw) return [];
		const list = JSON.parse(raw);
		if (!Array.isArray(list)) return [];
		return list.filter((g) => g && typeof g === 'object' && typeof g.id === 'string');
	} catch {
		return [];
	}
}

export function saveGoals(goals: RunGoal[]): void {
	if (typeof localStorage === 'undefined') return;
	try {
		localStorage.setItem(STORAGE_KEY, JSON.stringify(goals));
	} catch {
		/* quota — noop */
	}
}

export function newGoalId(): string {
	return typeof crypto !== 'undefined' && 'randomUUID' in crypto
		? crypto.randomUUID()
		: `g_${Date.now()}_${Math.random().toString(36).slice(2, 8)}`;
}

export function periodStart(period: GoalPeriod, now: Date): Date {
	const d = new Date(now);
	d.setHours(0, 0, 0, 0);
	if (period === 'week') {
		d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
	} else {
		d.setDate(1);
	}
	return d;
}

export function periodEnd(period: GoalPeriod, now: Date): Date {
	const start = periodStart(period, now);
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

/// Pure evaluator. Given a goal and the full run list, compute progress
/// per active target. Mirrors the shape of `evaluateGoal` in
/// `goals.dart` — active-target list, aggregate percent, overall
/// completion flag.
export function evaluateGoal(
	goal: RunGoal,
	runs: Run[],
	now: Date,
): GoalProgress {
	const start = periodStart(goal.period, now).getTime();
	const end = periodEnd(goal.period, now).getTime();
	const inPeriod = runs.filter((r) => {
		const t = new Date(r.started_at).getTime();
		return t >= start && t < end;
	});
	const totalMetres = inPeriod.reduce((s, r) => s + r.distance_m, 0);
	const totalSeconds = inPeriod.reduce((s, r) => s + r.duration_s, 0);

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
