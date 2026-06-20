// Multi-distance race-time predictor — richer surface over the existing
// Riegel + VDOT engine (training.ts) and the qualifying-run gate (fitness.ts).
//
// The plan-detail RaceDayPanel predicts ONE distance (the plan goal) off the
// single best recent run. This helper projects the WHOLE standard race ladder
// (5K / 10K / Half / Marathon) at once and grades each prediction's confidence
// independently, so a runner with a recent 10K sees a high-confidence 10K and
// a clearly-flagged low-confidence marathon side by side.
//
// Two improvements over "best single run, one distance":
//
//   1. Recency-weighted anchor. Rather than taking the literal best Riegel
//      projection (which a months-old PR can win), each qualifying effort is
//      Riegel-equivalenced to a common reference distance, then the anchor is
//      the recency-weighted best — a recent strong effort outranks a stale PR.
//      The weight is an exponential half-life decay on the effort's age, so a
//      fitness that has moved on isn't anchored to last spring's parkrun.
//   2. Per-distance confidence. Each ladder rung reuses `predictionConfidence`
//      from training.ts with the SAME thresholds the single-distance panel
//      uses, so the grade a runner sees here matches what they'd see on the
//      plan panel for the same distance.
//
// Pure — no Supabase / Svelte. Reuses riegelPredict + predictionConfidence so
// the numbers can't drift from the rest of the engine. TS↔Dart parity pair
// (race_predictor.dart).

import { riegelPredict, predictionConfidence, type PredictionQuality } from './training';

/// The standard race ladder we project, in metres. Matches GOAL_DISTANCES_M
/// in training.ts (5K / 10K / Half / Marathon) — the distances a runner
/// recognises and trains toward. Kept as an ordered list so the ladder
/// renders shortest-to-longest.
export const RACE_LADDER_M: readonly number[] = [5000, 10_000, 21_097.5, 42_195];

/// A single qualifying effort feeding the predictor. Deliberately the minimal
/// shape (distance, time, age) so the caller maps a Run row down to it without
/// dragging the full type in — mirrors how training_load.ts takes RunForLoad.
export interface EffortForPrediction {
	distanceM: number;
	durationS: number;
	/// Age of the effort in days at prediction time (>= 0).
	ageDays: number;
}

export interface LadderPrediction {
	/// Target race distance in metres (one of RACE_LADDER_M).
	distanceM: number;
	/// Predicted finish time in seconds.
	predictedSec: number;
	/// Predicted average pace in seconds per km.
	paceSecPerKm: number;
	/// Data-quality grade for THIS rung — graded against the anchor effort's
	/// distance gap to this target, the anchor's age, and the sample size.
	quality: PredictionQuality;
}

export interface RacePrediction {
	/// The anchor effort the whole ladder is projected from.
	anchor: {
		distanceM: number;
		durationS: number;
		ageDays: number;
	};
	/// Number of qualifying efforts that fed the anchor selection.
	qualifyingCount: number;
	/// One prediction per ladder rung, shortest-to-longest.
	rungs: LadderPrediction[];
}

/// Half-life (days) of the recency weight applied when picking the anchor
/// effort. At 30 days an effort counts half as much as a same-quality effort
/// today; at 60 days, a quarter. Chosen to match the ~30-day "recent" cliff
/// in `predictionConfidence` — an effort past that window should not out-anchor
/// a fresh one purely because it was faster when the runner was fitter.
export const ANCHOR_RECENCY_HALFLIFE_DAYS = 30;

/// Reference distance the anchor comparison is normalised to. 10K sits in the
/// middle of the ladder, so equivalencing every effort to it minimises the
/// average Riegel extrapolation across the candidate pool. The choice only
/// affects WHICH effort wins the anchor slot, never the final per-rung
/// predictions (those project directly from the chosen anchor's real
/// distance + time).
const ANCHOR_REFERENCE_M = 10_000;

/// Recency weight for an effort `ageDays` old: 0.5 ^ (age / halflife), clamped
/// so a future-dated effort (clock skew) can't exceed weight 1.
function recencyWeight(ageDays: number): number {
	const age = Math.max(0, ageDays);
	return Math.pow(0.5, age / ANCHOR_RECENCY_HALFLIFE_DAYS);
}

/// Build the multi-distance race prediction from a pool of qualifying efforts.
///
/// Returns null when the pool is empty — the caller hides the surface rather
/// than showing a fabricated ladder (fail-closed, same as the single-distance
/// panel which shows nothing without a qualifying run).
///
/// Anchor selection: each effort is Riegel-equivalenced to ANCHOR_REFERENCE_M,
/// giving a common-distance time; the effort whose recency-weighted equivalent
/// time is fastest wins. Weighting divides the equivalent time by the recency
/// weight, so a stale effort's effective time is inflated — a recent effort of
/// the same raw quality beats it. The final ladder then projects from the
/// chosen anchor's ACTUAL distance + time, so the predictions are honest Riegel
/// equivalences, not weighted fabrications.
export function predictRaceLadder(efforts: EffortForPrediction[]): RacePrediction | null {
	const pool = efforts.filter(
		(e) => e.distanceM > 0 && e.durationS > 0 && Number.isFinite(e.ageDays),
	);
	if (pool.length === 0) return null;

	let best: EffortForPrediction | null = null;
	let bestEffectiveSec = Infinity;
	for (const e of pool) {
		const equivSec = riegelPredict(e.distanceM, e.durationS, ANCHOR_REFERENCE_M);
		const weight = recencyWeight(e.ageDays);
		// Guard a zero weight (an absurdly old effort) so it can't divide to
		// Infinity and then never lose to a finite candidate via the strict <.
		const effectiveSec = weight > 0 ? equivSec / weight : Infinity;
		if (effectiveSec < bestEffectiveSec) {
			bestEffectiveSec = effectiveSec;
			best = e;
		}
	}
	// Every effort had weight 0 (all impossibly old) — fall back to the raw
	// fastest equivalent so we still anchor on something rather than null out.
	if (best == null) {
		bestEffectiveSec = Infinity;
		for (const e of pool) {
			const equivSec = riegelPredict(e.distanceM, e.durationS, ANCHOR_REFERENCE_M);
			if (equivSec < bestEffectiveSec) {
				bestEffectiveSec = equivSec;
				best = e;
			}
		}
	}
	const anchor = best as EffortForPrediction;

	const rungs: LadderPrediction[] = RACE_LADDER_M.map((distanceM) => {
		const predictedSec = riegelPredict(anchor.distanceM, anchor.durationS, distanceM);
		return {
			distanceM,
			predictedSec,
			paceSecPerKm: predictedSec / (distanceM / 1000),
			quality: predictionConfidence({
				knownDistanceM: anchor.distanceM,
				targetDistanceM: distanceM,
				daysSinceBest: Math.round(anchor.ageDays),
				qualifyingRunCount: pool.length,
			}),
		};
	});

	return {
		anchor: {
			distanceM: anchor.distanceM,
			durationS: anchor.durationS,
			ageDays: anchor.ageDays,
		},
		qualifyingCount: pool.length,
		rungs,
	};
}
