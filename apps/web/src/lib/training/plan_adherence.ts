/**
 * Plan-adherence feedback — does the runner's actual training match the
 * plan? Two signals, both pure (no Supabase / DOM):
 *
 *  1. Weekly mileage drift — flags when actual weekly volume runs more
 *     than ±20% off the plan. BOTH directions matter: under-running
 *     loses the adaptation; over-running the easy weeks is the classic
 *     way a motivated runner digs a fatigue hole (decisions §34 readiness
 *     covers the recovery side, this covers the plan-compliance side).
 *
 *  2. Missed-long-run advice — a simple make-up / skip recommendation
 *     for a long run the runner blew past, driven by training phase and
 *     proximity to a recovery week. The long run is the one session worth
 *     a make-up decision; quality sessions are cheaper to drop.
 *
 * The UI maps the returned reason codes to localized prose; tests assert
 * on the codes so wording can change without churning the suite.
 */

/// Beyond ±this fraction off the planned weekly volume, surface a drift
/// flag. 20% is roughly one easy run's worth on a typical week — small
/// enough to catch a real trend, large enough not to nag on noise.
export const PLAN_DRIFT_THRESHOLD = 0.2;

export type DriftDirection = 'under' | 'over' | 'on_track';

export interface WeeklyDrift {
	plannedMetres: number;
	actualMetres: number;
	/// (actual − planned) / planned. Positive = over-running, negative =
	/// under-running. 0 when there's no planned volume to compare against.
	driftFraction: number;
	direction: DriftDirection;
	/// True when |driftFraction| exceeds the threshold AND there's a real
	/// plan to drift from (planned volume > 0).
	flagged: boolean;
}

/// Compare a week's actual mileage to its planned volume. Returns a
/// neutral, unflagged result when the week has no planned volume (a
/// pure rest week, or a week before the plan models distance) so the
/// caller never shows a drift flag against a zero baseline.
export function weeklyDrift(
	plannedMetres: number,
	actualMetres: number,
	threshold = PLAN_DRIFT_THRESHOLD,
): WeeklyDrift {
	if (!(plannedMetres > 0)) {
		return {
			plannedMetres: Math.max(0, plannedMetres),
			actualMetres: Math.max(0, actualMetres),
			driftFraction: 0,
			direction: 'on_track',
			flagged: false,
		};
	}
	const actual = Math.max(0, actualMetres);
	const driftFraction = (actual - plannedMetres) / plannedMetres;
	let direction: DriftDirection = 'on_track';
	if (driftFraction > threshold) direction = 'over';
	else if (driftFraction < -threshold) direction = 'under';
	return {
		plannedMetres,
		actualMetres: actual,
		driftFraction,
		direction,
		flagged: direction !== 'on_track',
	};
}

export type MakeUpRecommendation = 'make_up' | 'skip';

export type MissedWorkoutReason =
	| 'key_session' // base/build long run — worth making up
	| 'taper' // late in the plan, adding load now hurts more than it helps
	| 'recovery_soon' // a step-back week is imminent; let the body take the down week
	| 'not_long_run'; // quality session, not worth a dedicated make-up

export interface MissedWorkoutAdvice {
	recommendation: MakeUpRecommendation;
	reason: MissedWorkoutReason;
}

export interface MissedWorkoutInput {
	/// Workout kind from the plan (`long`, `tempo`, …).
	kind: string;
	/// Whether the missed workout sits in the taper phase of the plan.
	isTaper: boolean;
	/// Whether the very next week is a recovery / step-back week. Null when
	/// unknown (treated as "not imminent").
	recoveryWeekImminent: boolean | null;
}

/// Recommend whether to make up or skip a missed workout. Only the long
/// run earns a make-up decision; everything else is cheaper to drop than
/// to cram. For a long run: skip in the taper (freshness > one more long
/// run) or when a recovery week is about to absorb the deficit anyway;
/// otherwise make it up, because the long run is the plan's keystone.
export function missedWorkoutAdvice(input: MissedWorkoutInput): MissedWorkoutAdvice {
	if (input.kind !== 'long') {
		return { recommendation: 'skip', reason: 'not_long_run' };
	}
	if (input.isTaper) {
		return { recommendation: 'skip', reason: 'taper' };
	}
	if (input.recoveryWeekImminent === true) {
		return { recommendation: 'skip', reason: 'recovery_soon' };
	}
	return { recommendation: 'make_up', reason: 'key_session' };
}
