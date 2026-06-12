/**
 * Adaptive re-plan (plan generator v2). Where `replanRemaining` reacts to a
 * single signal (a missed long run, last week over), this gates a re-plan on a
 * MULTI-WEEK adherence TREND: it only proposes changes when the last few
 * completed weeks show a sustained drift, suppressing single-week noise the
 * manual re-plan would act on.
 *
 * Pure + suggestion-only (no Supabase / DOM): classify the trailing completed
 * weeks' drift, and when a trend is flagged delegate the actual future-only
 * deltas to `replanRemaining` — this layer decides WHETHER and WHY, the shipped
 * engine decides WHAT. Past + taper stay frozen because `replanRemaining`
 * already freezes them; this layer never widens that.
 *
 * P1 (shipped, decisions §144): intensity/volume-only off adherence drift.
 *
 * P2 (THIS FILE, gated): an optional `fitness` input adds a DIRECTION GATE — an
 * adherence "you've under-run, do more" trend is SUPPRESSED when the runner is
 * already fatigued (TSB < 0), because the two signals disagree and you never
 * pile volume onto a fatigue hole. This is the first phase that reads
 * health-derived load (TSB/ATL/CTL from training_load.ts) into a prescription,
 * so it is GATED ON CISO / SECURITY-ANALYST SIGN-OFF before it ships (see
 * reviews/plan-generator-v2-p2-ciso-note.md). Lives on branch
 * feat/gen-v2-p2-fitness; do not merge to main until signed off.
 *
 * Mirrors `apps/mobile_android/lib/plan_adaptive_replan.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import { weeklyDrift, type DriftDirection } from './plan_adherence';
import { replanRemaining, type ReplanChange, type ReplanWeek } from './plan_replan';

/// How many trailing COMPLETED weeks define the trend.
export const ADAPTIVE_TREND_WINDOW = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
export const ADAPTIVE_TREND_MIN = 2;

export type AdaptiveReason = 'trend_underfitness' | 'trend_overtraining' | 'on_track';

/// How strongly the window agrees with the trend direction.
export type AdaptiveConfidence = 'high' | 'medium' | 'low';

/// P2: the runner's current training-load state, sourced from the
/// ALREADY-COMPUTED training_load.ts series (no new data collection). Only the
/// sign of `tsb` (form) is consulted; never logged or persisted.
export interface AdaptiveFitness {
	/// Training Stress Balance (form). Negative = fatigued.
	tsb: number;
	/// Acute load (fatigue).
	atl: number;
	/// Chronic load (fitness).
	ctl: number;
}

export interface AdaptiveReplanResult {
	changes: ReplanChange[];
	reason: AdaptiveReason;
	confidence: AdaptiveConfidence;
	onTrack: boolean;
	trailingDirections: DriftDirection[];
	/// P2: true when a would-be add-volume suggestion was withheld because the
	/// fitness signal contradicts the adherence trend (fatigued runner).
	fitnessGated: boolean;
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes `replanRemaining` would make.
/// Fails toward `on_track` whenever a trend can't be established. When `fitness`
/// is supplied (P2), an under-fitness ramp is suppressed for a fatigued runner.
export function adaptiveReplanRemaining(input: {
	weeks: ReplanWeek[];
	/// ISO today (YYYY-MM-DD).
	today: string;
	/// P2 (gated): current fitness/fatigue. Omit for the P1 behaviour.
	fitness?: AdaptiveFitness | null;
}): AdaptiveReplanResult {
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);

	const completed = weeks.filter((w) => w.isComplete && w.plannedMetres > 0);
	const window = completed.slice(-ADAPTIVE_TREND_WINDOW);
	const drifts = window.map((w) => weeklyDrift(w.plannedMetres, w.actualMetres));
	const trailingDirections = drifts.map((d) => d.direction);

	const under = drifts.filter((d) => d.flagged && d.direction === 'under').length;
	const over = drifts.filter((d) => d.flagged && d.direction === 'over').length;

	let reason: AdaptiveReason = 'on_track';
	if (under >= ADAPTIVE_TREND_MIN && under > over) reason = 'trend_underfitness';
	else if (over >= ADAPTIVE_TREND_MIN && over > under) reason = 'trend_overtraining';

	// P2 direction gate: don't pile volume onto a fatigued runner. When the
	// adherence trend says "do more" but form (TSB) is negative, the signals
	// disagree → suggest nothing (fail to on_track), flagged as fitness-gated.
	const fitness = input.fitness ?? null;
	if (reason === 'trend_underfitness' && fitness != null && fitness.tsb < 0) {
		return {
			changes: [],
			reason: 'on_track',
			confidence: 'low',
			onTrack: true,
			trailingDirections,
			fitnessGated: true,
		};
	}

	if (reason === 'on_track') {
		return {
			changes: [],
			reason,
			confidence: 'low',
			onTrack: true,
			trailingDirections,
			fitnessGated: false,
		};
	}

	const agree = reason === 'trend_underfitness' ? under : over;
	const confidence: AdaptiveConfidence = agree >= window.length ? 'high' : 'medium';

	const { changes } = replanRemaining({ weeks, today: input.today });
	return {
		changes,
		reason,
		confidence,
		onTrack: changes.length === 0,
		trailingDirections,
		fitnessGated: false,
	};
}
