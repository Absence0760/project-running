/**
 * Training-plan re-planning around missed sessions (roadmap Phase 3 — the
 * last real training-engine gap, Runna's headline feature). Pure: takes a
 * snapshot of the plan (weeks + workouts + per-week actual mileage) and
 * returns a list of proposed changes to FUTURE workouts. The caller
 * previews the diff and applies it via the existing per-row update path.
 *
 * Deliberately conservative — this rewrites someone's training, so the
 * rules are the safe, defensible ones a coach would actually use, not an
 * aggressive optimiser:
 *
 *  - The past is frozen. Nothing dated before today is touched.
 *  - The taper is sacred. Weeks in the `taper` / `race` phase are never
 *    modified — freshness for race day beats any make-up.
 *  - Missed *easy* volume is let go (you don't cram missed easy miles —
 *    that's how runners get hurt). Only the long run is worth a make-up,
 *    matching `missedWorkoutAdvice`.
 *  - A make-up never spikes the next long run by more than 15%.
 *  - Cumulative over-running triggers a one-week ease-off, not a scolding.
 *  - The goal race date never moves (it isn't an input the engine can
 *    change — callers keep `end_date` fixed).
 *
 * Reuses `weeklyDrift` + `missedWorkoutAdvice` from `plan_adherence.ts`.
 * Mirrors `apps/mobile_android/lib/plan_replan.dart` — keep in lockstep.
 */

import { weeklyDrift, missedWorkoutAdvice } from './plan_adherence';

/// Cap on how far a make-up may stretch the next long run, so honouring a
/// missed 30 km run can't turn a planned 18 km long run into a 30 km spike.
export const MAKE_UP_MAX_INCREASE = 0.15;

/// Multiplier applied to the next week's non-long workouts when the
/// runner has been over-running — bleed off accumulated fatigue.
export const EASE_OFF_SCALE = 0.85;

const TAPER_PHASES = new Set(['taper', 'race']);

export interface ReplanWorkout {
	id: string;
	/// ISO scheduled date (YYYY-MM-DD).
	scheduledDate: string;
	kind: string;
	targetDistanceM: number | null;
	completed: boolean;
	/// scheduledDate strictly before today.
	isPast: boolean;
}

export interface ReplanWeek {
	weekIndex: number;
	phase: string;
	plannedMetres: number;
	/// Summed actual run mileage dated inside this week's window.
	actualMetres: number;
	/// Every day in the week is before today.
	isComplete: boolean;
	workouts: ReplanWorkout[];
}

export type ReplanReason = 'make_up_long' | 'ease_over_running';

export interface ReplanChange {
	workoutId: string;
	scheduledDate: string;
	reason: ReplanReason;
	/// Only future workout distances change — the past is never mutated.
	field: 'target_distance_m';
	fromMetres: number;
	toMetres: number;
}

export interface ReplanResult {
	changes: ReplanChange[];
	/// True when nothing needs changing — the plan is on track.
	onTrack: boolean;
}

function isTaper(phase: string): boolean {
	return TAPER_PHASES.has(phase);
}

/// Whether a step-back week (a >15% planned-volume drop) immediately
/// follows `week` — mirrors the heuristic the plan-detail adherence
/// surface uses.
function recoveryWeekImminent(weeks: ReplanWeek[], idx: number): boolean {
	const cur = weeks[idx];
	const next = weeks.find((w) => w.weekIndex === cur.weekIndex + 1);
	if (!next || !(cur.plannedMetres > 0) || !(next.plannedMetres > 0)) return false;
	return next.plannedMetres < cur.plannedMetres * 0.85;
}

export function replanRemaining(input: {
	weeks: ReplanWeek[];
	/// ISO today (YYYY-MM-DD).
	today: string;
}): ReplanResult {
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);
	const changes: ReplanChange[] = [];

	// Future, non-taper workouts available to absorb a make-up or ease-off.
	const futureLongRuns = weeks
		.flatMap((w) => (isTaper(w.phase) ? [] : w.workouts))
		.filter((wo) => !wo.isPast && wo.kind === 'long')
		.sort((a, b) => (a.scheduledDate < b.scheduledDate ? -1 : 1));

	// ── 1. Missed long runs in past weeks → make up in the future ──
	// The missed run itself is FROZEN (past) — we never mutate it; it just
	// triggers a forward make-up. The adherence banner already surfaces it.
	// With several outstanding missed long runs the make-up honours the
	// LARGEST one (the most demanding session to recover) — a 30 km miss
	// outranks an earlier 24 km miss — not whichever happened first.
	let maxMissedLong = 0;
	for (let i = 0; i < weeks.length; i++) {
		const week = weeks[i];
		for (const wo of week.workouts) {
			if (wo.kind !== 'long' || !wo.isPast || wo.completed) continue;
			const advice = missedWorkoutAdvice({
				kind: 'long',
				isTaper: isTaper(week.phase),
				recoveryWeekImminent: recoveryWeekImminent(weeks, i),
			});
			if (advice.recommendation !== 'make_up') continue;
			maxMissedLong = Math.max(maxMissedLong, wo.targetDistanceM ?? 0);
		}
	}
	// Make up by ensuring the NEXT future long run doesn't regress below the
	// largest missed distance — capped so it can't spike.
	const nextLong = futureLongRuns[0];
	if (nextLong && maxMissedLong > 0) {
		const plannedNext = nextLong.targetDistanceM ?? 0;
		if (plannedNext > 0) {
			const capped = Math.min(maxMissedLong, Math.round(plannedNext * (1 + MAKE_UP_MAX_INCREASE)));
			if (capped > plannedNext) {
				changes.push({
					workoutId: nextLong.id,
					scheduledDate: nextLong.scheduledDate,
					reason: 'make_up_long',
					field: 'target_distance_m',
					fromMetres: plannedNext,
					toMetres: capped,
				});
			}
		}
	}

	// ── 2. Cumulative over-running → ease off the next future week ──
	// Use the most recent COMPLETE week as the signal.
	const lastComplete = [...weeks].reverse().find((w) => w.isComplete);
	if (lastComplete) {
		const drift = weeklyDrift(lastComplete.plannedMetres, lastComplete.actualMetres);
		if (drift.direction === 'over') {
			const nextWeek = weeks.find(
				(w) => w.weekIndex > lastComplete.weekIndex && !isTaper(w.phase) &&
					w.workouts.some((wo) => !wo.isPast),
			);
			if (nextWeek) {
				for (const wo of nextWeek.workouts) {
					if (wo.isPast || wo.kind === 'rest' || wo.kind === 'long') continue;
					if (wo.targetDistanceM == null || wo.targetDistanceM <= 0) continue;
					// Don't double-touch a workout already changed by the make-up pass.
					if (changes.some((c) => c.workoutId === wo.id)) continue;
					changes.push({
						workoutId: wo.id,
						scheduledDate: wo.scheduledDate,
						reason: 'ease_over_running',
						field: 'target_distance_m',
						fromMetres: wo.targetDistanceM,
						toMetres: Math.round(wo.targetDistanceM * EASE_OFF_SCALE),
					});
				}
			}
		}
	}

	return { changes, onTrack: changes.length === 0 };
}
