/**
 * Adaptive re-plan (plan generator v2, P1 — decisions §144). Where
 * `replanRemaining` reacts to a single signal (a missed long run, last
 * week over), this gates a re-plan on a MULTI-WEEK adherence TREND: it
 * only proposes changes when the last few completed weeks show a
 * sustained drift, suppressing single-week noise the manual re-plan would
 * act on.
 *
 * Pure + suggestion-only (no Supabase / DOM): classify the trailing
 * completed weeks' drift, and when a trend is flagged delegate the actual
 * future-only deltas to `replanRemaining` — this layer decides WHETHER and
 * WHY, the shipped engine decides WHAT. Past + taper stay frozen because
 * `replanRemaining` already freezes them; this layer never widens that.
 *
 * P1 is intensity/volume-only off adherence drift; fitness (TSB/ATL/CTL)
 * gating is P2 and is the first phase that reads health-derived load, so
 * it carries a CISO sign-off gate (see §144 / the design doc). Do not add
 * a fitness signal here without that review.
 *
 * Mirrors `apps/mobile_android/lib/plan_adaptive_replan.dart` — keep in
 * lockstep (TS↔Dart parity pair, equal test counts).
 */

import { weeklyDrift, type DriftDirection } from './plan_adherence';
import { replanRemaining, type ReplanChange, type ReplanWeek } from './plan_replan';

/// How many trailing COMPLETED weeks define the trend. Three weeks is long
/// enough to be a trend, short enough to react inside a training block.
export const ADAPTIVE_TREND_WINDOW = 3;

/// At least this many flagged weeks (in one direction) within the window
/// make a trend. Two-of-three is the "sustained, not noise" bar.
export const ADAPTIVE_TREND_MIN = 2;

export type AdaptiveReason = 'trend_underfitness' | 'trend_overtraining' | 'on_track';

/// How strongly the window agrees with the trend direction. `high` = every
/// examined week agrees; `medium` = the minimum quorum; `low` = on track.
export type AdaptiveConfidence = 'high' | 'medium' | 'low';

export interface AdaptiveReplanResult {
	/// Future-only changes from `replanRemaining` (empty when the trend is
	/// flagged but no SAFE change applies — e.g. under-running easy volume,
	/// which is deliberately never crammed).
	changes: ReplanChange[];
	reason: AdaptiveReason;
	confidence: AdaptiveConfidence;
	/// True when nothing needs changing.
	onTrack: boolean;
	/// Drift direction of each examined trailing week, oldest→newest, for a
	/// transparent "why" in the UI.
	trailingDirections: DriftDirection[];
}

/// Classify the trailing completed weeks' adherence trend and, when a
/// sustained drift is found, return the future-only changes `replanRemaining`
/// would make. Fails toward `on_track` whenever a trend can't be established.
export function adaptiveReplanRemaining(input: {
	weeks: ReplanWeek[];
	/// ISO today (YYYY-MM-DD).
	today: string;
}): AdaptiveReplanResult {
	const weeks = [...input.weeks].sort((a, b) => a.weekIndex - b.weekIndex);

	// Only completed weeks that modelled real volume can carry a trend — an
	// in-progress week or a pre-distance week is not yet evidence.
	const completed = weeks.filter((w) => w.isComplete && w.plannedMetres > 0);
	const window = completed.slice(-ADAPTIVE_TREND_WINDOW);
	const drifts = window.map((w) => weeklyDrift(w.plannedMetres, w.actualMetres));
	const trailingDirections = drifts.map((d) => d.direction);

	const under = drifts.filter((d) => d.flagged && d.direction === 'under').length;
	const over = drifts.filter((d) => d.flagged && d.direction === 'over').length;

	let reason: AdaptiveReason = 'on_track';
	if (under >= ADAPTIVE_TREND_MIN && under > over) reason = 'trend_underfitness';
	else if (over >= ADAPTIVE_TREND_MIN && over > under) reason = 'trend_overtraining';

	if (reason === 'on_track') {
		return { changes: [], reason, confidence: 'low', onTrack: true, trailingDirections };
	}

	const agree = reason === 'trend_underfitness' ? under : over;
	const confidence: AdaptiveConfidence = agree >= window.length ? 'high' : 'medium';

	const { changes } = replanRemaining({ weeks, today: input.today });
	return { changes, reason, confidence, onTrack: changes.length === 0, trailingDirections };
}
