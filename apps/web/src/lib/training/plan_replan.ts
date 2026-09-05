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
	/// The runner explicitly dropped this workout (skipped_at stamped) — it's
	/// off the books, so a make-up is never proposed for it.
	skipped: boolean;
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

/// Bleed a week's worth of load: scale every non-long, non-rest FUTURE workout
/// of the first non-taper week after `afterWeekIndex` by `EASE_OFF_SCALE`.
/// `weeks` must already be sorted by `weekIndex`; pass `-1` to ease the
/// earliest eligible week. Exported because two callers need to deload
/// identically — the over-running rule below, and the adaptive layer's
/// deep-fatigue override (`plan_adaptive_replan.ts`) — and a second copy of
/// these skip rules would drift.
export function easeOffNextWeek(
	weeks: ReplanWeek[],
	afterWeekIndex: number,
	skipWorkoutIds: ReadonlySet<string> = new Set<string>(),
): ReplanChange[] {
	const nextWeek = weeks.find(
		(w) => w.weekIndex > afterWeekIndex && !isTaper(w.phase) &&
			w.workouts.some((wo) => !wo.isPast),
	);
	if (!nextWeek) return [];
	const changes: ReplanChange[] = [];
	for (const wo of nextWeek.workouts) {
		if (wo.isPast || wo.kind === 'rest' || wo.kind === 'long') continue;
		if (wo.targetDistanceM == null || wo.targetDistanceM <= 0) continue;
		if (skipWorkoutIds.has(wo.id)) continue;
		changes.push({
			workoutId: wo.id,
			scheduledDate: wo.scheduledDate,
			reason: 'ease_over_running',
			field: 'target_distance_m',
			fromMetres: wo.targetDistanceM,
			toMetres: Math.round(wo.targetDistanceM * EASE_OFF_SCALE),
		});
	}
	return changes;
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

	// Earliest future, non-taper long run available to absorb a make-up. Only
	// the minimum is ever read, so this scans rather than sorts: a strict `<`
	// keeps the FIRST of two long runs sharing a date — the plan's own
	// week-then-workout order — with no dependence on a sort's stability. The
	// Dart twin and the firmware port scan identically, so all three rails pick
	// the same session out of a double-long-run day.
	let nextLong: ReplanWorkout | null = null;
	for (const week of weeks) {
		if (isTaper(week.phase)) continue;
		for (const wo of week.workouts) {
			if (wo.isPast || wo.kind !== 'long') continue;
			if (nextLong === null || wo.scheduledDate < nextLong.scheduledDate) nextLong = wo;
		}
	}

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
			if (wo.kind !== 'long' || !wo.isPast || wo.completed || wo.skipped) continue;
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
			// The skip set keeps the ease pass from double-touching a workout the
			// make-up pass already changed.
			changes.push(
				...easeOffNextWeek(
					weeks,
					lastComplete.weekIndex,
					new Set(changes.map((c) => c.workoutId)),
				),
			);
		}
	}

	return { changes, onTrack: changes.length === 0 };
}
