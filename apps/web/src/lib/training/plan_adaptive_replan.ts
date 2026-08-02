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
 * P2 (THIS FILE, gated): an optional `fitness` input adds a DIRECTION GATE over
 * the already-computed CTL/ATL/TSB series (`training_load.ts`) — no new
 * collection, no new column, no new hop. Three arms:
 *
 *   1. add volume only when form allows — an "under-run, do more" trend is
 *      SUPPRESSED while TSB < 0, because you never pile volume onto a fatigue
 *      hole;
 *   2. override to DELOAD when TSB is deeply negative AND acute load is high
 *      against the chronic base — the load signal then outranks whatever the
 *      adherence trend said, in either direction;
 *   3. suggest nothing on disagreement (arm 1's outcome).
 *
 * The fitness snapshot is a parameter and dies here: nothing in
 * `AdaptiveReplanResult` carries a load number back out, and this module logs
 * nothing — so a TSB can reach a suggestion but can never reach a log line, a
 * plan row, or the network. That is a stated condition of the sign-off, so it
 * is enforced structurally rather than by convention.
 *
 * This is the first phase that reads health-derived load into a prescription,
 * so the whole input is behind a FAIL-CLOSED deploy gate — web
 * `PUBLIC_ADAPTIVE_FITNESS_GATE` (see `adaptive_fitness_flag.ts`), mobile
 * `ADAPTIVE_FITNESS_GATE` in dotenv, both parsed by `adaptiveFitnessGateEnabled`
 * below so the two platforms cannot drift. Unset → the caller passes no fitness
 * → behaviour is exactly P1. Flipping the flag on for a prod build is the
 * CISO / Security-Analyst sign-off-gated action (decisions §144 + §150).
 *
 * Mirrors `apps/mobile_android/lib/plan_adaptive_replan.dart` — keep in lockstep
 * (TS↔Dart parity pair, equal test counts).
 */

import { isTruthyFlagValue } from '../core/env_flag';
import { weeklyDrift, type DriftDirection } from './plan_adherence';
import {
	easeOffNextWeek,
	replanRemaining,
	type ReplanChange,
	type ReplanWeek,
} from './plan_replan';

/// How many trailing COMPLETED weeks define the trend.
export const ADAPTIVE_TREND_WINDOW = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
export const ADAPTIVE_TREND_MIN = 2;

/// TSB at or below this counts as DEEPLY negative — form is in the hole, not
/// merely down after one hard week. Conventional reading of the CTL/ATL/TSB
/// model puts −10..−25 in the productive-training band and past −25 into
/// overreaching, so that is where "stop adding, start bleeding" sits.
export const ADAPTIVE_DEEP_FATIGUE_TSB = -25;

/// Acute:chronic workload ratio at or above which acute load counts as HIGH
/// against the base the runner has actually absorbed. 1.3 is the conventional
/// injury-risk threshold. Required alongside the TSB floor so a runner whose
/// whole load is simply large (high ATL and high CTL together) isn't told to
/// deload — only one carrying acute load their chronic base doesn't support.
export const ADAPTIVE_HIGH_ACWR = 1.3;

export type AdaptiveReason =
	| 'trend_underfitness'
	| 'trend_overtraining'
	/// P2 arm 2: the fitness signal overrode the direction to a deload.
	| 'deload_fatigue'
	| 'on_track';

/// How strongly the window agrees with the trend direction.
export type AdaptiveConfidence = 'high' | 'medium' | 'low';

/// P2: the runner's current training-load state, sourced from the
/// ALREADY-COMPUTED training_load.ts series (no new data collection). Consumed
/// in-memory to pick a direction; never echoed back out, logged, or persisted.
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
	/// fitness signal contradicts the adherence trend (fatigued runner) and
	/// nothing is proposed in its place. A deload override reports its outcome
	/// through `reason` instead.
	fitnessGated: boolean;
}

/// Pure parse of the P2 fitness-gate deploy flag. Truthy only for an explicit
/// `1` / `true` / `yes` / `on` (case-insensitive, trimmed); anything else —
/// including unset / empty / `false` / `0` — is off. Fail-closed: the whole
/// health-derived-load → prescription path stays unreachable until CISO /
/// Security-Analyst sign-off flips the flag at deploy time. The web env binding
/// lives in `adaptive_fitness_flag.ts`; the mobile binding reads dotenv — both
/// call this so the parse can't drift.
export function adaptiveFitnessGateEnabled(raw: string | null | undefined): boolean {
	return isTruthyFlagValue(raw);
}

/// Deeply fatigued: form in the hole AND acute load high against a real chronic
/// base. Non-finite or absent chronic load fails closed (a runner with no
/// chronic base has nothing for acute load to be "high" against).
function isDeeplyFatigued(f: AdaptiveFitness): boolean {
	if (!Number.isFinite(f.tsb) || !Number.isFinite(f.atl) || !Number.isFinite(f.ctl)) {
		return false;
	}
	if (!(f.ctl > 0)) return false;
	return f.tsb <= ADAPTIVE_DEEP_FATIGUE_TSB && f.atl >= f.ctl * ADAPTIVE_HIGH_ACWR;
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes `replanRemaining` would make.
/// Fails toward `on_track` whenever a trend can't be established. When `fitness`
/// is supplied (P2), the load signal gates the direction: an under-fitness ramp
/// is suppressed for a fatigued runner, and deep fatigue overrides to a deload.
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

	const fitness = input.fitness ?? null;

	// P2 arm 2 — deep-fatigue DELOAD OVERRIDE. Checked before the adherence
	// arms because it is the only branch where the runner is at genuine risk:
	// whatever the plan says they ran, the load says bleed it off. Never adds
	// volume (the make-up pass is skipped entirely), so it is also a strict
	// tightening of arm 1 rather than a competing rule.
	if (fitness != null && isDeeplyFatigued(fitness)) {
		const lastComplete = [...weeks].reverse().find((w) => w.isComplete);
		const changes = easeOffNextWeek(weeks, lastComplete?.weekIndex ?? -1);
		return {
			changes,
			reason: 'deload_fatigue',
			// The load signal crossed both thresholds — nothing about the week
			// window makes it more or less certain.
			confidence: 'high',
			onTrack: changes.length === 0,
			trailingDirections,
			fitnessGated: false,
		};
	}

	// P2 arms 1 + 3 — direction gate: don't pile volume onto a fatigued runner.
	// When the adherence trend says "do more" but form (TSB) is negative, the
	// signals disagree → suggest nothing, flagged as fitness-gated.
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
