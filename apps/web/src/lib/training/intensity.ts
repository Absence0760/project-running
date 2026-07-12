/**
 * Easy/hard intensity-distribution derivation for the dashboard
 * "Easy / hard balance" card (backlog #11, advanced analytics polish).
 *
 * Classifies each recent run as easy or hard and reports the time-weighted
 * split against the ~80/20 guideline (Seiler's polarised-training finding:
 * most endurance training should sit below the first ventilatory threshold).
 *
 * Heuristic — pace vs the runner's own VDOT-derived threshold:
 *
 *   1. Threshold pace comes from `currentVdot` + `thresholdPaceSecPerKmFromVdot`
 *      — the SAME derivation the TSS / training-load engine uses, so this card
 *      can never disagree with the fitness/fatigue/form chart about what
 *      "threshold" means for this runner.
 *   2. A run is HARD when its average velocity is at or above 88% of
 *      threshold (T-pace) velocity. Daniels puts T-pace at ~88% vVO2max, so
 *      88% of T-velocity lands at ~78% vVO2max — the top of the easy zone /
 *      first ventilatory threshold, which is exactly the 80/20 low/high
 *      boundary. Everything slower is EASY.
 *   3. The split is weighted by TIME (the 80/20 literature measures time in
 *      zone, not session count); run counts are reported alongside for the
 *      sub-line.
 *
 * Known limitation, shared with the TSS engine: the threshold anchors to the
 * best qualifying run in the last 90 days, so a runner whose every run is an
 * identical effort reads as mostly hard — which is also the classic
 * "everything moderate" pattern the 80/20 guideline warns about.
 *
 * Pure: no Supabase, no DOM, no rune state — unit-tests under `tsx --test`.
 * Web-only by design (no Dart twin); deliberately kept off the enforced
 * web↔mobile parity list.
 */

import type { Run } from '../types';
import {
	currentVdot,
	qualifyingRuns,
	thresholdPaceSecPerKmFromVdot,
} from './fitness';

export type IntensityVerdict = 'onGuideline' | 'tooHard' | 'allEasy';

export interface IntensityStats {
	/// Trailing window the classification covers, in whole weeks.
	windowWeeks: number;
	/// Qualifying runs classified inside the window.
	totalRuns: number;
	easyRuns: number;
	hardRuns: number;
	/// Time-weighted split, seconds per class.
	easySeconds: number;
	hardSeconds: number;
	/// easySeconds / (easySeconds + hardSeconds) as a 0..100 rounded pct.
	easyTimePct: number;
	hardTimePct: number;
	verdict: IntensityVerdict;
	/// The T-pace the classification was anchored on (s/km), for the footnote.
	thresholdPaceSecPerKm: number;
}

/// A run is hard at or above this fraction of threshold velocity
/// (~78% vVO2max ≈ the first ventilatory threshold — the 80/20 boundary).
export const kHardVelocityFraction = 0.88;

/// The guideline the card compares against: ~80% of training time easy.
export const kGuidelineEasyShare = 0.8;

/// Easy-time share at or above this reads as on-guideline; a small tolerance
/// below the 0.8 target so a 76/24 week isn't scolded. Below it: too much
/// intensity. Documented threshold, pinned by a unit test.
export const kOnGuidelineMinEasyShare = 0.75;

/// Fewer classified runs than this can't support a distribution claim, so
/// the card self-hides rather than judging a 2-run sample.
export const kMinClassifiedRuns = 4;

/// Classify the last `windowDays` of qualifying runs into easy vs hard.
/// Returns null when no threshold pace can be derived (no qualifying run in
/// the 90-day VDOT window) or the sample is too small — the card self-hides.
/// `now` defaults to the real clock; pass an explicit date in tests.
export function computeIntensity(
	runs: Run[],
	windowDays = 56,
	now: Date = new Date(),
): IntensityStats | null {
	if (windowDays < 1) return null;
	const nowMs = now.getTime();
	const threshold = thresholdPaceSecPerKmFromVdot(currentVdot(runs, nowMs));
	if (threshold == null) return null;

	const cutoffMs = nowMs - windowDays * 86_400_000;
	let easyRuns = 0;
	let hardRuns = 0;
	let easySeconds = 0;
	let hardSeconds = 0;
	for (const r of qualifyingRuns(runs)) {
		const t = new Date(r.started_at).getTime();
		if (!Number.isFinite(t) || t < cutoffMs || t > nowMs) continue;
		const paceSecPerKm = r.duration_s / (r.distance_m / 1000);
		if (!(paceSecPerKm > 0)) continue;
		// Same inversion as runTss: faster pace (smaller s/km) → higher fraction.
		const velocityFraction = threshold / paceSecPerKm;
		if (velocityFraction >= kHardVelocityFraction) {
			hardRuns += 1;
			hardSeconds += r.duration_s;
		} else {
			easyRuns += 1;
			easySeconds += r.duration_s;
		}
	}

	const totalRuns = easyRuns + hardRuns;
	const totalSeconds = easySeconds + hardSeconds;
	if (totalRuns < kMinClassifiedRuns || totalSeconds <= 0) return null;

	const easyShare = easySeconds / totalSeconds;
	const verdict: IntensityVerdict =
		hardSeconds === 0
			? 'allEasy'
			: easyShare >= kOnGuidelineMinEasyShare
				? 'onGuideline'
				: 'tooHard';

	const easyTimePct = Math.round(easyShare * 100);
	return {
		windowWeeks: Math.round(windowDays / 7),
		totalRuns,
		easyRuns,
		hardRuns,
		easySeconds,
		hardSeconds,
		easyTimePct,
		hardTimePct: 100 - easyTimePct,
		verdict,
		thresholdPaceSecPerKm: threshold,
	};
}
