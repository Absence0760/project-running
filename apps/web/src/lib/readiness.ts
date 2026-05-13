/**
 * Readiness-to-run score. Combines training balance (form / TSB),
 * last night's sleep, and resting-HR drift vs a baseline into a
 * single 0–100 number the dashboard can show.
 *
 * Garmin's "Body Battery", Whoop's "Recovery" and Oura's "Readiness"
 * are the precedents. We compute deltas around a neutral baseline of
 * 75; positive contributors push it up, negative ones drag it down,
 * and the result is clamped to 0–100.
 *
 * Pure — no Supabase, no DOM. Mirrors
 * `apps/mobile_android/lib/readiness.dart`. Keep in lockstep — the
 * shared-library-syncer agent watches the pair.
 */

export interface ReadinessInputs {
	/** Training Stress Balance (Form). Positive = fresh, negative = fatigued. Pass null if unknown. */
	tsb: number | null;
	/** Hours of sleep last night. Pass null if unknown. */
	sleepHours?: number | null;
	/** This morning's resting heart rate, in bpm. Pass null if unknown. */
	restingHrBpm?: number | null;
	/** 30-day baseline resting heart rate. Pass null if unknown. */
	baselineRestingHrBpm?: number | null;
}

export type ReadinessBand = 'low' | 'moderate' | 'high';

export interface ReadinessContribution {
	/** Short label — UI surfaces it in a per-input list. */
	name: string;
	/** Signed delta this input added to the score. */
	delta: number;
	/** One-line reason. */
	note: string;
}

export interface Readiness {
	/** Final score in 0..100. */
	score: number;
	/** Bucket — drives card colour and tone of advice. */
	band: ReadinessBand;
	/** One-line guidance, picked from the dominant contributor. */
	advice: string;
	/** Per-input breakdown so the UI can show "why". */
	contributors: ReadinessContribution[];
}

/** Neutral starting point. A user with no inputs at all gets 75. */
const BASELINE_SCORE = 75;

function clamp(v: number, lo: number, hi: number): number {
	return Math.min(hi, Math.max(lo, v));
}

function bandFor(score: number): ReadinessBand {
	if (score >= 70) return 'high';
	if (score >= 40) return 'moderate';
	return 'low';
}

/**
 * Score the contribution from Training Stress Balance.
 *
 * TSB convention (matches `lib/training_load.ts`):
 *  - TSB ≈ 0   → neutral / maintenance form
 *  - TSB > +5  → fresh; small positive on score
 *  - TSB < -10 → fatigued; large negative on score
 *  - TSB > +25 → over-tapered, slightly negative again ("detraining
 *               risk" / blunted edge — small but real)
 */
function scoreTsb(tsb: number | null): ReadinessContribution | null {
	if (tsb == null) return null;
	let delta = 0;
	let note = '';
	if (tsb < -20) {
		delta = -20;
		note = 'Heavy fatigue — recent training stress is well above your fitness';
	} else if (tsb < -10) {
		delta = -12;
		note = 'Fatigued from recent training';
	} else if (tsb < -5) {
		delta = -6;
		note = 'Slight fatigue';
	} else if (tsb <= 5) {
		delta = 0;
		note = 'Form is neutral';
	} else if (tsb <= 15) {
		delta = 8;
		note = 'Fresh and well-recovered';
	} else if (tsb <= 25) {
		delta = 5;
		note = 'Very fresh — borderline tapered';
	} else {
		delta = -3;
		note = 'Over-tapered — edge may be blunted';
	}
	return { name: 'Form (TSB)', delta, note };
}

function scoreSleep(hours: number | null | undefined): ReadinessContribution | null {
	if (hours == null) return null;
	let delta = 0;
	let note = '';
	if (hours < 5) {
		delta = -25;
		note = 'Very little sleep — recovery is compromised';
	} else if (hours < 6.5) {
		delta = -12;
		note = 'Short on sleep';
	} else if (hours < 7.5) {
		delta = -3;
		note = 'A little under target sleep';
	} else if (hours <= 9) {
		delta = 5;
		note = 'Well rested';
	} else {
		delta = 0;
		note = 'Extended sleep — recovery should be solid';
	}
	return { name: 'Sleep', delta, note };
}

function scoreRestingHr(
	resting: number | null | undefined,
	baseline: number | null | undefined,
): ReadinessContribution | null {
	if (resting == null || baseline == null) return null;
	const diff = resting - baseline;
	let delta = 0;
	let note = '';
	if (diff > 10) {
		delta = -18;
		note = `Resting HR ${diff} bpm above baseline — strong sign of illness or under-recovery`;
	} else if (diff > 5) {
		delta = -10;
		note = `Resting HR ${diff} bpm above baseline`;
	} else if (diff > 2) {
		delta = -4;
		note = 'Resting HR slightly elevated';
	} else if (diff >= -2) {
		delta = 0;
		note = 'Resting HR at baseline';
	} else {
		delta = 3;
		note = 'Resting HR below baseline — well recovered';
	}
	return { name: 'Resting HR', delta, note };
}

/** Pick the contributor that pushed the score the most (in absolute terms). */
function dominantAdvice(contributors: ReadinessContribution[], band: ReadinessBand): string {
	if (contributors.length === 0) {
		// No signals at all. Fall back to a band-aware suggestion.
		return band === 'high'
			? 'Looks like a good day to push the pace.'
			: 'Connect sleep + HR data for a real readiness picture.';
	}
	const dom = contributors.slice().sort((a, b) => Math.abs(b.delta) - Math.abs(a.delta))[0];
	const tail =
		band === 'low'
			? 'Consider an easy day or a rest day.'
			: band === 'moderate'
				? 'A steady or moderate effort fits today.'
				: 'You’re primed for a harder effort if planned.';
	return `${dom.note}. ${tail}`;
}

export function computeReadiness(inputs: ReadinessInputs): Readiness {
	const contributors: ReadinessContribution[] = [];
	const tsb = scoreTsb(inputs.tsb);
	if (tsb) contributors.push(tsb);
	const sleep = scoreSleep(inputs.sleepHours ?? null);
	if (sleep) contributors.push(sleep);
	const hr = scoreRestingHr(
		inputs.restingHrBpm ?? null,
		inputs.baselineRestingHrBpm ?? null,
	);
	if (hr) contributors.push(hr);

	const sum = contributors.reduce((s, c) => s + c.delta, 0);
	const score = clamp(Math.round(BASELINE_SCORE + sum), 0, 100);
	const band = bandFor(score);
	return {
		score,
		band,
		advice: dominantAdvice(contributors, band),
		contributors,
	};
}
