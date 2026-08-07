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
 *   2. A SEGMENT is HARD when its average velocity is at or above 88% of
 *      threshold (T-pace) velocity. Daniels puts T-pace at ~88% vVO2max, so
 *      88% of T-velocity lands at ~78% vVO2max — the top of the easy zone /
 *      first ventilatory threshold, which is exactly the 80/20 low/high
 *      boundary. Everything slower is EASY.
 *   3. The split is weighted by TIME (the 80/20 literature measures time in
 *      zone, not session count); run counts are reported alongside for the
 *      sub-line.
 *
 * A run is classified from the finest time-resolved evidence it carries, NOT
 * from one whole-run average — see `effortSegments`. One whole-run average
 * cannot represent a session that deliberately mixes intensities: a warmup and
 * easy recovery jogs dilute the mean well below the hard boundary even when the
 * work intervals were run past it, so the exact VO2max session the runner's
 * plan prescribed landed wholly in the "easy" bucket and suppressed the
 * `tooHard` verdict (issue #676). A mixed session now contributes to BOTH
 * buckets. It counts as one HARD run in the run tallies whenever any of its time
 * classified hard — a session with quality work in it is a quality session, the
 * same way Daniels and Seiler count sessions by their hardest content.
 *
 * `easySeconds + hardSeconds` is therefore *classified* time, which can fall
 * short of the summed `duration_s` when a slice of a run has no trustworthy
 * pace behind it (see the segment floor). The card reports shares, so a
 * dropped sliver moves nothing; attributing it by assumption would.
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

import { METADATA_KEYS } from '../core/schema';
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

/// A slice of one run's elapsed time with a distance to derive its pace from.
export interface EffortSegment {
	seconds: number;
	metres: number;
}

/// Floors a metadata-derived slice must clear before its own average pace is
/// trusted. Both are below any deliberately-run rep — a 100 m stride is ~17 s —
/// and above the artefact they exist for: a double-tapped lap key, or a step the
/// runner skipped the instant it armed, leaves a few metres over a few seconds
/// whose "pace" is start/stop latency rather than effort, and would otherwise
/// flip a whole easy run to hard. Sub-floor slices are not dropped, they fall
/// into the residual and are classified with it.
export const kMinSegmentSeconds = 10;
export const kMinSegmentMetres = 20;

function usableSlice(seconds: unknown, metres: unknown): boolean {
	return (
		typeof seconds === 'number' &&
		Number.isFinite(seconds) &&
		seconds >= kMinSegmentSeconds &&
		typeof metres === 'number' &&
		Number.isFinite(metres) &&
		metres >= kMinSegmentMetres
	);
}

/// Both readers below take `duration` + `distance` and nothing else: a slice is
/// accepted only when BOTH are usable, so the seconds and the metres a segment
/// consumes always travel together. Accepting a reported pace without its
/// distance would leave those metres in the residual, making the residual read
/// faster than it ran.
function slicesFrom(
	v: unknown,
	durationKey: string,
	distanceKey: string,
): EffortSegment[] | null {
	if (!Array.isArray(v)) return null;
	const out: EffortSegment[] = [];
	for (const raw of v) {
		if (raw == null || typeof raw !== 'object') continue;
		const row = raw as Record<string, unknown>;
		if (!usableSlice(row[durationKey], row[distanceKey])) continue;
		out.push({ seconds: row[durationKey] as number, metres: row[distanceKey] as number });
	}
	return out.length > 0 ? out : null;
}

/// The run's time broken into the finest slices its own row can support, each
/// carrying the distance its pace derives from.
///
/// `metadata.workout_step_results` first — it IS the executed workout's
/// structure, one row per expanded step with the actual distance and elapsed
/// time of each rep and each recovery jog. Then `metadata.laps`, which covers
/// the session the runner segmented by hand (and the Garmin FIT / watch-sync
/// imports that carry lap messages). Both are registered shapes — see
/// docs/backend/metadata.md — read off a schemaless jsonb bag, so every field is
/// validated rather than trusted.
///
/// Whatever elapsed time and distance those slices leave unattributed becomes
/// one residual segment classified at its own average pace. That single
/// mechanism covers the two ways the slices fall short of the whole run — time
/// run outside the workout or after the last lap press, and the sub-floor
/// slivers above — without ever assuming which bucket the leftovers belong in.
///
/// With no usable breakdown the result is the whole run as one segment, which is
/// the original behaviour and still the honest answer for a steady run.
export function effortSegments(run: Run): EffortSegment[] {
	const bag = run.metadata;
	const slices =
		bag == null
			? null
			: (slicesFrom(bag[METADATA_KEYS.workout_step_results], 'duration_s', 'actual_distance_m') ??
				slicesFrom(bag[METADATA_KEYS.laps], 'duration_s', 'distance_m'));
	if (slices == null) return [{ seconds: run.duration_s, metres: run.distance_m }];

	let seconds = run.duration_s;
	let metres = run.distance_m;
	for (const s of slices) {
		seconds -= s.seconds;
		metres -= s.metres;
	}
	if (usableSlice(seconds, metres)) slices.push({ seconds, metres });
	return slices;
}

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
		let easy = 0;
		let hard = 0;
		for (const seg of effortSegments(r)) {
			const paceSecPerKm = seg.seconds / (seg.metres / 1000);
			if (!(paceSecPerKm > 0)) continue;
			// Same inversion as runTss: faster pace (smaller s/km) → higher fraction.
			const velocityFraction = threshold / paceSecPerKm;
			if (velocityFraction >= kHardVelocityFraction) hard += seg.seconds;
			else easy += seg.seconds;
		}
		if (easy + hard <= 0) continue;
		easySeconds += easy;
		hardSeconds += hard;
		// Any hard time makes it a hard session; see the header note.
		if (hard > 0) hardRuns += 1;
		else easyRuns += 1;
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
