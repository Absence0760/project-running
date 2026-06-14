// Training engine: VDOT from a recent race, Riegel equivalence between race
// distances, pace targets by intensity zone, and an 8-16 week plan generator.
//
// Deliberately small and self-contained — no external deps. Tested under
// apps/web/tests/training.test.ts. If you change a number in here, run the
// tests before assuming the plan still looks right.
//
// Design choice: Riegel + goal-pace multipliers for training paces, not the
// full Daniels VDOT table. Daniels' percentages (E=70%, M=84%, T=88%, I=98%,
// R=105% of VDOT) are implicit in `vo2max = f(velocity)` — there's no clean
// inverse. The standard implementation is a lookup table. For MVP, multipliers
// of goal pace land within ~5 s/km of the Daniels tables for typical runners
// and carry zero table data. If users complain about pace accuracy, swap
// `paceFor` for a Daniels-table lookup without changing the public surface.

export type GoalEvent = 'distance_5k' | 'distance_10k' | 'distance_half' | 'distance_full' | 'custom';
export type WorkoutKind =
	| 'easy'
	| 'long'
	| 'recovery'
	| 'tempo'
	| 'interval'
	| 'marathon_pace'
	| 'walk_run'
	| 'race'
	| 'rest';
export type PlanPhase = 'base' | 'build' | 'peak' | 'taper' | 'race';

export const GOAL_DISTANCES_M: Record<Exclude<GoalEvent, 'custom'>, number> = {
	distance_5k: 5000,
	distance_10k: 10_000,
	distance_half: 21_097.5,
	distance_full: 42_195
};

const DEFAULT_PLAN_WEEKS: Record<Exclude<GoalEvent, 'custom'>, number> = {
	distance_5k: 8,
	distance_10k: 8,
	distance_half: 12,
	distance_full: 16
};

export function defaultPlanWeeks(goal: GoalEvent): number {
	return goal === 'custom' ? 12 : DEFAULT_PLAN_WEEKS[goal];
}

/// Default week count for a beginner C25K walk-run plan. The continuous-run
/// default (`defaultPlanWeeks('distance_5k')` = 8) is one week shorter than
/// the `WALK_RUN_PROGRESSION` table, so feeding it to the walk-run generator
/// drops the final graduation week (the single continuous run). Callers that
/// build a beginner plan should size `weeks` from this, not `defaultPlanWeeks`.
/// Persona round-5 runner-new.
export function walkRunDefaultWeeks(): number {
	return WALK_RUN_PROGRESSION.length;
}

// ─────────────────────── VDOT (Daniels) ───────────────────────

/**
 * Compute Daniels VDOT from a race time.
 *
 * `vo2 = -4.6 + 0.182258 v + 0.000104 v²` where v is m/min.
 * `pct = 0.8 + 0.1894393 e^(-0.012778 T) + 0.2989558 e^(-0.1932605 T)` where T is minutes.
 * `vdot = vo2 / pct`.
 *
 * Source: Daniels, J. — Daniels' Running Formula, 3rd ed.
 */
export function vdotFromRace(distanceMetres: number, timeSeconds: number): number {
	const minutes = timeSeconds / 60;
	const v = distanceMetres / minutes; // m/min
	const vo2 = -4.6 + 0.182258 * v + 0.000104 * v * v;
	const pct =
		0.8 +
		0.1894393 * Math.exp(-0.012778 * minutes) +
		0.2989558 * Math.exp(-0.1932605 * minutes);
	return vo2 / pct;
}

// ─────────────────────── Riegel equivalence ───────────────────────

/**
 * Predict a time at a different distance given a known race result. Uses
 * Riegel's 1981 formula `t2 = t1 * (d2/d1)^1.06`, widely regarded as
 * accurate within 1–2% for endurance races across the 5k–marathon range.
 */
export function riegelPredict(
	knownDistanceM: number,
	knownTimeSec: number,
	targetDistanceM: number,
	exponent = 1.06
): number {
	return knownTimeSec * Math.pow(targetDistanceM / knownDistanceM, exponent);
}

export type PredictionConfidence = 'high' | 'moderate' | 'low';

/// Machine-readable reason code for the binding limit on a prediction's
/// confidence. The UI maps these to localized prose; tests assert on
/// the code so the wording can change without churning the suite.
export type PredictionReason = 'similar' | 'extrapolated' | 'stale' | 'limited';

export interface PredictionQuality {
	confidence: PredictionConfidence;
	reason: PredictionReason;
}

/// Beyond this Riegel extrapolation factor (target/known distance, or
/// its reciprocal) the prediction is little better than a guess — a
/// marathon predicted from a 5k is ~8.4x. Caps confidence at 'low'.
const RIEGEL_FAR_FACTOR = 4;

/// Grade the data quality behind a Riegel race-time prediction. The
/// three levers are how far we extrapolate from the anchoring effort
/// (distance gap), how recent that effort is, and how many qualifying
/// recent efforts back it up. Pure — the caller supplies the anchor's
/// distance, its age in days, and the count of qualifying recent runs.
export function predictionConfidence(input: {
	/// Distance of the best recent effort the Riegel projection is anchored to.
	knownDistanceM: number;
	/// Target race distance.
	targetDistanceM: number;
	/// Age in days of the anchoring effort.
	daysSinceBest: number;
	/// Number of qualifying recent runs (the size of the pool the anchor came from).
	qualifyingRunCount: number;
}): PredictionQuality {
	const { knownDistanceM, targetDistanceM, daysSinceBest, qualifyingRunCount } = input;
	if (knownDistanceM <= 0 || targetDistanceM <= 0 || qualifyingRunCount <= 0) {
		return { confidence: 'low', reason: 'limited' };
	}
	const ratio = targetDistanceM / knownDistanceM;
	const factor = Math.max(ratio, 1 / ratio);

	// Extrapolating far past the anchoring effort dominates every other
	// signal — no amount of recency or sample size rescues a marathon
	// predicted off a parkrun.
	if (factor > RIEGEL_FAR_FACTOR) {
		return { confidence: 'low', reason: 'extrapolated' };
	}

	// A factor up to 2 (5k↔10k, 10k↔half-ish) is the band Riegel handles
	// well; beyond that error grows fast even within the 4x cap.
	const closeDistance = factor <= 2;
	const recent = daysSinceBest <= 30;
	const wellSampled = qualifyingRunCount >= 3;

	if (closeDistance && recent && wellSampled) {
		return { confidence: 'high', reason: 'similar' };
	}

	// One or more levers are soft. Report the binding constraint, with
	// distance gap first (it hurts the prediction most).
	if (!closeDistance) return { confidence: 'moderate', reason: 'extrapolated' };
	if (!recent) {
		// An effort older than two months is too stale to anchor a
		// race-day prediction at all, not just a soft caveat.
		return daysSinceBest > 60
			? { confidence: 'low', reason: 'stale' }
			: { confidence: 'moderate', reason: 'stale' };
	}
	// Close + recent but thinly sampled.
	return { confidence: 'moderate', reason: 'limited' };
}

// ─────────────────────── Training paces ───────────────────────

export interface TrainingPaces {
	easy: number; // seconds per km
	marathon: number;
	tempo: number;
	interval: number;
	repetition: number;
}

/// Optional gender hint for pace derivation. Matches the `gender`
/// column on `user_profiles`. Persona-hunt Round 3 finding Woman #3.
export type TrainingGender = 'male' | 'female' | 'nonbinary' | null;

// Female runners' actual VDOT plotted on Daniels' male-default curve
// under-predicts their training paces by ~3%. Applied as a uniform
// pace-time multiplier (slightly slower seconds/km in every band).
// Persona-hunt Round 3 finding Woman #3.
//
// Why 3% as the single calibration constant:
//  - Sport-science literature suggests female calibration corrections
//    in the 2-5% range depending on intensity zone. A single uniform
//    multiplier under-prescribes at the extreme bands but is the right
//    shape for the data we have (no per-band gender x VDOT calibration
//    has been published with the rigour required to override Daniels).
//  - Uniform multiplier keeps the helper a pure single-line tweak.
//  - The conservative direction (slower) is the right error mode —
//    over-prescribing female athletes' paces is the harm we're fixing.
//
// `male` and `null` use the original (male-derived) curve. `nonbinary`
// also defaults to the original — no validated calibration exists for
// non-binary athletes, and a wrong adjustment is worse than no
// adjustment.
const FEMALE_PACE_CALIBRATION = 1.03;

function genderPaceMultiplier(gender: TrainingGender | undefined): number {
	return gender === 'female' ? FEMALE_PACE_CALIBRATION : 1.0;
}

// Masters (50+) recovery calibration. Persona-hunt finding Older #30:
// the default week schedules the first quality session 48h after the
// Sunday long run and steps back volume every 4th week. Both are tuned
// for younger physiology — masters athletes recover more slowly, so
// the literature (and every masters-specific plan) widens hard-day
// spacing to ~72h and shortens the build/recover cycle. When `age >=
// MASTERS_AGE` we (a) push the first quality day from Tue→Wed (72h
// after the long run) and the second from Thu→Fri, and (b) step volume
// back every 3rd week instead of every 4th. Pace bands are left on the
// shared Daniels curve — no validated age×VDOT pace table exists, and
// the harm being fixed here is recovery density, not pace. See
// docs/architecture/decisions.md § masters-recovery-calibration.
const MASTERS_AGE = 50;

export function isMastersAge(age: number | null | undefined): boolean {
	return age != null && age >= MASTERS_AGE;
}

/**
 * Derive the five Daniels intensity-zone paces as multipliers of goal-race
 * pace. Numbers chosen so the output sits close to Daniels' published tables
 * across the 3:00–5:00/km goal-pace band. `goalPaceSecPerKm` is the runner's
 * target pace for the goal race.
 *
 * Optional `gender` parameter applies the female-specific calibration —
 * see [decisions.md § 76](docs/architecture/decisions.md#76-training-pace-derivation-applies-a-3-female-specific-calibration-to-the-daniels-curve) and the
 * `FEMALE_PACE_CALIBRATION` constant above for the rationale.
 */
export function pacesFromGoalPace(
	goalPaceSecPerKm: number,
	gender: TrainingGender = null
): TrainingPaces {
	// Goal pace sits between marathon and tempo intensity for most runners.
	// These multipliers are a simplification of Daniels' percentages and are
	// stable across the typical distance/goal-time grid; see the regression
	// tests in training.test.ts.
	const g = genderPaceMultiplier(gender);
	return {
		easy: Math.round(goalPaceSecPerKm * 1.22 * g),
		marathon: Math.round(goalPaceSecPerKm * 1.06 * g),
		tempo: Math.round(goalPaceSecPerKm * 0.97 * g),
		interval: Math.round(goalPaceSecPerKm * 0.9 * g),
		repetition: Math.round(goalPaceSecPerKm * 0.85 * g)
	};
}

/// The conservative goal pace (sec/km) used when the runner gave us neither a
/// recent race nor a goal time. ~10:00/km — slow enough that the derived easy
/// pace won't injure a returning runner, but it's a placeholder, not a
/// personalised number. `resolveTrainingPacesWithMeta` flags when it's in play
/// so the caller can disclose it instead of presenting it as real. Persona
/// round-5 runner-comeback.
const FALLBACK_GOAL_PACE_SEC_PER_KM = 600;

/**
 * Resolve the runner's training paces plus whether they came from a real
 * fitness anchor or the conservative fallback. Priority: an explicit recent 5k
 * time (use Riegel to predict goal-distance pace) → a goal time on the target
 * distance (use directly) → fall back to a conservative "10:00/km as goal" so
 * the plan still generates for someone without any race history.
 *
 * `isFallback` is true only in that last case. The numbers are always usable
 * (the plan generates regardless); the flag exists so the wizard can label the
 * preview "estimated — add a recent run for personalised paces" rather than
 * presenting a placeholder as a confident prescription. Persona round-5
 * runner-comeback.
 */
export function resolveTrainingPacesWithMeta(input: {
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	gender?: TrainingGender;
}): { paces: TrainingPaces; isFallback: boolean } {
	let goalPaceSecPerKm: number;
	let isFallback = false;
	if (input.recent5kSec) {
		const predicted = riegelPredict(5000, input.recent5kSec, input.goalDistanceM);
		goalPaceSecPerKm = predicted / (input.goalDistanceM / 1000);
	} else if (input.goalTimeSec) {
		goalPaceSecPerKm = input.goalTimeSec / (input.goalDistanceM / 1000);
	} else {
		goalPaceSecPerKm = FALLBACK_GOAL_PACE_SEC_PER_KM;
		isFallback = true;
	}
	return { paces: pacesFromGoalPace(goalPaceSecPerKm, input.gender ?? null), isFallback };
}

/**
 * Resolve the runner's training paces from whichever anchor they gave us.
 * Priority: an explicit recent 5k time (use Riegel to predict goal-distance
 * pace) → a goal time on the target distance (use directly) → fall back to a
 * conservative "10:00/km as goal" so the plan still generates for someone
 * without any race history. Thin wrapper over `resolveTrainingPacesWithMeta`
 * for callers that don't need the fallback flag.
 */
export function resolveTrainingPaces(input: {
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	gender?: TrainingGender;
}): TrainingPaces {
	return resolveTrainingPacesWithMeta(input).paces;
}

// ─────────────────────── Phase schedule ───────────────────────

export function phaseFor(weekIndex: number, totalWeeks: number): PlanPhase {
	const base = Math.floor(totalWeeks * 0.3);
	const build = Math.floor(totalWeeks * 0.4);
	const peak = Math.floor(totalWeeks * 0.2);
	// Remaining weeks → taper. Final week is always 'race'.
	if (weekIndex >= totalWeeks - 1) return 'race';
	if (weekIndex < base) return 'base';
	if (weekIndex < base + build) return 'build';
	if (weekIndex < base + build + peak) return 'peak';
	return 'taper';
}

// ─────────────────────── Workout structure ───────────────────────

/**
 * Structured-workout descriptor stored in `plan_workouts.structure`. Tempo,
 * interval, and repetition workouts use this; easy/long/recovery/rest do
 * not. See `docs/features/training.md` for the shape spec.
 */
export interface WorkoutStructure {
	warmup?: { distance_m?: number; duration_s?: number; pace: 'easy' };
	// A rep / recovery may be expressed by distance (distance_m) or by time
	// (duration_s) — the runner reads whichever is present (distance wins).
	// Walk-run (C25K / Galloway) sessions use duration-based reps with a
	// 'walk' recovery; see docs/features/training.md § walk-run.
	repeats?: {
		count: number;
		distance_m?: number;
		duration_s?: number;
		pace_sec_per_km: number;
		recovery_distance_m?: number;
		recovery_duration_s?: number;
		recovery_pace: 'easy' | 'jog' | 'walk';
	};
	steady?: { distance_m?: number; duration_s?: number; pace_sec_per_km: number };
	cooldown?: { distance_m?: number; duration_s?: number; pace: 'easy' };
}

// ─────────────────────── Plan generation ───────────────────────

export interface GeneratedWorkout {
	scheduled_date: string; // ISO date YYYY-MM-DD
	kind: WorkoutKind;
	target_distance_m: number | null;
	target_duration_seconds: number | null;
	target_pace_sec_per_km: number | null;
	target_pace_tolerance_sec: number | null;
	structure: WorkoutStructure | null;
	notes: string | null;
}

export interface GeneratedWeek {
	week_index: number;
	phase: PlanPhase;
	target_volume_m: number;
	notes: string | null;
	workouts: GeneratedWorkout[];
}

export interface GeneratePlanInput {
	goalEvent: GoalEvent;
	goalDistanceM?: number; // required if goalEvent === 'custom'
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
	startDate: string; // ISO date
	daysPerWeek: number; // 3–7
	weeks?: number;
	/// Optional gender from `user_profiles.gender` — applies the
	/// female-specific calibration to derived training paces.
	/// Persona-hunt Round 3 finding Woman #3.
	gender?: TrainingGender;
	/// Optional age (years) from `user_profiles.date_of_birth`. At or above
	/// MASTERS_AGE it applies the masters recovery calibration — wider
	/// hard-day spacing + a 3-week build/recover cycle. Persona-hunt
	/// finding Older #30.
	age?: number | null;
	/// When true, produce a beginner C25K-style walk-run plan instead of the
	/// continuous-running plan. The goal stays a 5k; every session is a
	/// `walk_run` workout of timed run/walk intervals (persona #22).
	beginnerWalkRun?: boolean;
}

export interface GeneratedPlan {
	weeks: GeneratedWeek[];
	paces: TrainingPaces;
	vdot: number | null;
	endDate: string; // ISO date
	goalDistanceM: number;
	/// True when `paces` are the conservative 10:00/km fallback (no recent
	/// race, no goal time) rather than derived from real fitness. The plan
	/// is still valid; the caller should disclose the paces are estimated.
	/// Persona round-5 runner-comeback.
	pacesAreFallback: boolean;
}

/**
 * Generate a full plan from (goal, start date, days/week, fitness anchor).
 * Phase breakdown is 30 / 40 / 20 / 10 of base / build / peak / taper with
 * the final week always a 'race' week. Mileage ramps with a step-back every
 * fourth week to cap cumulative fatigue.
 */
export function generatePlan(input: GeneratePlanInput): GeneratedPlan {
	const goalDistanceM =
		input.goalEvent === 'custom'
			? input.goalDistanceM!
			: GOAL_DISTANCES_M[input.goalEvent];
	const totalWeeks = input.weeks ?? defaultPlanWeeks(input.goalEvent);
	const { paces, isFallback: pacesAreFallback } = resolveTrainingPacesWithMeta({
		goalDistanceM,
		goalTimeSec: input.goalTimeSec,
		recent5kSec: input.recent5kSec,
		gender: input.gender
	});
	const vdot = input.recent5kSec
		? vdotFromRace(5000, input.recent5kSec)
		: input.goalTimeSec
		? vdotFromRace(goalDistanceM, input.goalTimeSec)
		: null;

	const startDate = parseISO(input.startDate);

	if (input.beginnerWalkRun) {
		return generateWalkRunPlan(input, goalDistanceM, paces, vdot, startDate, pacesAreFallback);
	}

	const weeks: GeneratedWeek[] = [];
	const masters = isMastersAge(input.age);

	for (let i = 0; i < totalWeeks; i++) {
		const phase = phaseFor(i, totalWeeks);
		// Mileage curve: ramp from 0.6× peak at week 0 up to 1.0× at peak-end,
		// then drop to 0.5× in taper and 0.35× in race week.
		const peakWeeklyKm = peakVolumeKm(
			goalDistanceM,
			input.daysPerWeek,
			!!(input.goalTimeSec || input.recent5kSec)
		);
		const fraction = mileageFraction(i, totalWeeks, phase, masters);
		const weeklyKm = Math.round(peakWeeklyKm * fraction);
		const workouts = generateWeek({
			weekIndex: i,
			phase,
			weekStart: addDays(startDate, i * 7),
			daysPerWeek: input.daysPerWeek,
			weeklyKm,
			paces,
			goalDistanceM,
			goalPaceSecPerKm: paces.marathon * (goalDistanceM >= 21_000 ? 1 : 0.95),
			masters
		});
		// The stated weekly volume must equal what the week actually
		// prescribes. The emitted workouts are rounded/floored per-day
		// (easy filler clamps to >=3 km, intervals/tempo/long carry their
		// own distances), so `weeklyKm * 1000` overstated the real ask by
		// ~25-70% on small-volume (5k/half) plans. Sum the emitted
		// distances so the headline number is honest. Quality + long run
		// stay uncapped (that's training design); only the stated total
		// is reconciled.
		weeks.push({
			week_index: i,
			phase,
			target_volume_m: workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0),
			notes: weekNote(phase, i, totalWeeks, masters),
			workouts
		});
	}

	const endDate = addDays(startDate, totalWeeks * 7 - 1);
	return {
		weeks,
		paces,
		vdot,
		endDate: formatISO(endDate),
		goalDistanceM,
		pacesAreFallback
	};
}

// ─────────────────────── Beginner walk-run (C25K) ───────────────────────

/// Simplified, monotonic C25K-style progression: each week is a uniform
/// run/walk interval that lengthens the run and trims the walk, graduating
/// to a continuous ~25-minute run. `count - 1` walk breaks sit between the
/// runs; week 9 has a single continuous run (no recovery). Real C25K mixes
/// interval lengths mid-program; we keep it uniform-per-week so the plan is
/// legible and the TS↔Dart parity stays tractable.
export const WALK_RUN_PROGRESSION: ReadonlyArray<{
	runSec: number;
	walkSec: number;
	count: number;
}> = [
	{ runSec: 60, walkSec: 90, count: 8 },
	{ runSec: 90, walkSec: 120, count: 7 },
	{ runSec: 120, walkSec: 120, count: 6 },
	{ runSec: 180, walkSec: 120, count: 5 },
	{ runSec: 300, walkSec: 120, count: 4 },
	{ runSec: 480, walkSec: 150, count: 3 },
	{ runSec: 600, walkSec: 120, count: 3 },
	{ runSec: 900, walkSec: 180, count: 2 },
	{ runSec: 1500, walkSec: 0, count: 1 }
];
const WALK_RUN_WARMUP_S = 300;
const WALK_RUN_COOLDOWN_S = 300;
const WALK_PACE_SEC_PER_KM = 700; // ~11:40/km brisk walk, for distance estimates

function walkRunWorkout(
	scheduledDate: string,
	weekIndex: number,
	easyPaceSecPerKm: number
): GeneratedWorkout {
	const prog = WALK_RUN_PROGRESSION[Math.min(weekIndex, WALK_RUN_PROGRESSION.length - 1)];
	const hasRecovery = prog.count > 1 && prog.walkSec > 0;
	const repeats: NonNullable<WorkoutStructure['repeats']> = {
		count: prog.count,
		duration_s: prog.runSec,
		pace_sec_per_km: easyPaceSecPerKm,
		recovery_pace: 'walk',
		...(hasRecovery ? { recovery_duration_s: prog.walkSec } : {})
	};
	const totalRunSec = prog.count * prog.runSec;
	const totalWalkSec =
		(hasRecovery ? (prog.count - 1) * prog.walkSec : 0) +
		WALK_RUN_WARMUP_S +
		WALK_RUN_COOLDOWN_S;
	const estDistanceM = Math.round(
		(totalRunSec * 1000) / easyPaceSecPerKm + (totalWalkSec * 1000) / WALK_PACE_SEC_PER_KM
	);
	return {
		scheduled_date: scheduledDate,
		kind: 'walk_run',
		target_distance_m: estDistanceM,
		target_duration_seconds: totalRunSec + totalWalkSec,
		target_pace_sec_per_km: easyPaceSecPerKm,
		target_pace_tolerance_sec: null,
		structure: {
			warmup: { duration_s: WALK_RUN_WARMUP_S, pace: 'easy' },
			repeats,
			cooldown: { duration_s: WALK_RUN_COOLDOWN_S, pace: 'easy' }
		},
		notes: hasRecovery
			? `Walk ${WALK_RUN_WARMUP_S / 60} min, then run ${prog.runSec}s / walk ${prog.walkSec}s × ${prog.count}, walk ${WALK_RUN_COOLDOWN_S / 60} min.`
			: `Walk ${WALK_RUN_WARMUP_S / 60} min, run ${Math.round(prog.runSec / 60)} min continuous, walk ${WALK_RUN_COOLDOWN_S / 60} min. Graduation week.`
	};
}

function generateWalkRunPlan(
	input: GeneratePlanInput,
	goalDistanceM: number,
	paces: TrainingPaces,
	vdot: number | null,
	startDate: Date,
	pacesAreFallback: boolean
): GeneratedPlan {
	// Never run fewer weeks than the progression has stages — truncating it
	// drops the final graduation week (the single continuous run), which is
	// the whole point of a C25K plan. A default 5k plan arrives here with
	// weeks=8 (defaultPlanWeeks('distance_5k')) against a 9-stage table, so
	// without this floor the graduation week silently vanishes. Persona
	// round-5 runner-new. A longer request is honoured (the table's last
	// stage repeats for the extra weeks via the index clamp in walkRunWorkout).
	const totalWeeks = Math.max(input.weeks ?? WALK_RUN_PROGRESSION.length, WALK_RUN_PROGRESSION.length);
	// Beginners train 3 days/week; respect a lower request but cap at 3.
	const runDays = Math.max(1, Math.min(input.daysPerWeek, 3));
	// Spread run days across Mon/Wed/Fri-style offsets.
	const dayOffsets = [0, 2, 4, 1, 3, 5, 6].slice(0, runDays).sort((a, b) => a - b);
	const weeks: GeneratedWeek[] = [];
	for (let i = 0; i < totalWeeks; i++) {
		const weekStart = addDays(startDate, i * 7);
		const runSet = new Set(dayOffsets);
		const workouts: GeneratedWorkout[] = [];
		for (let d = 0; d < 7; d++) {
			const date = formatISO(addDays(weekStart, d));
			if (runSet.has(d)) {
				workouts.push(walkRunWorkout(date, i, paces.easy));
			} else {
				workouts.push({
					scheduled_date: date,
					kind: 'rest',
					target_distance_m: null,
					target_duration_seconds: null,
					target_pace_sec_per_km: null,
					target_pace_tolerance_sec: null,
					structure: null,
					notes: null
				});
			}
		}
		weeks.push({
			week_index: i,
			phase: i === totalWeeks - 1 ? 'race' : 'build',
			target_volume_m: workouts.reduce((s, w) => s + (w.target_distance_m ?? 0), 0),
			notes:
				i === totalWeeks - 1
					? 'Final week — you can run the distance continuously now.'
					: 'Take the walk breaks even when you feel good — they make the runs sustainable.',
			workouts
		});
	}
	return {
		weeks,
		paces,
		vdot,
		endDate: formatISO(addDays(startDate, totalWeeks * 7 - 1)),
		goalDistanceM,
		pacesAreFallback
	};
}

function peakVolumeKm(
	goalDistanceM: number,
	daysPerWeek: number,
	hasAnchor: boolean = true
): number {
	// Rough volumes: ~4× goal for 5k/10k runners, ~2.5× for half, ~1.8× for full,
	// scaled gently by training days. Tuneable; see tests for expected outputs.
	const baseMultiplier =
		goalDistanceM <= 10_000 ? 5 : goalDistanceM <= 21_100 ? 2.5 : 1.8;
	const dayFactor = 0.7 + (daysPerWeek - 3) * 0.1;
	// With no fitness anchor (no goal time, no recent 5k) we can't assume the
	// runner can absorb the full volume — a no-info 5k plan otherwise peaked
	// at ~25 km/week with a punishing week-1 (new persona #23). Scale the peak
	// down so the ramp starts somewhere a cautious runner can actually hit.
	const anchorFactor = hasAnchor ? 1 : 0.6;
	return Math.round((goalDistanceM / 1000) * baseMultiplier * dayFactor * anchorFactor);
}

// Masters recover on a 3-week cycle (step back every 3rd week); the
// default build/recover cycle is 4 weeks. Both keep the very first
// week (i === 0) at full ramp so the plan doesn't open on a step-back.
function isStepBackWeek(i: number, masters: boolean): boolean {
	if (i === 0) return false;
	return masters ? i % 3 === 2 : i % 4 === 3;
}

function mileageFraction(
	i: number,
	total: number,
	phase: PlanPhase,
	masters = false
): number {
	if (phase === 'race') return 0.35;
	if (phase === 'taper') return 0.55;
	// Linear ramp inside base+build+peak, with a 0.82× step-back on the
	// recovery week (every 3rd week for masters, every 4th otherwise).
	const ramp = 0.6 + (0.4 * i) / Math.max(1, total - 3);
	const stepBack = isStepBackWeek(i, masters) ? 0.82 : 1;
	return Math.min(1, ramp * stepBack);
}

function weekNote(phase: PlanPhase, i: number, total: number, masters = false): string | null {
	if (phase === 'race') return 'Race week — trust the work.';
	if (phase === 'taper') return 'Taper — volume down, sharpness stays.';
	if (isStepBackWeek(i, masters)) return 'Step-back week — recover before the next build.';
	return null;
}

interface WeekGenInput {
	weekIndex: number;
	phase: PlanPhase;
	weekStart: Date;
	daysPerWeek: number;
	weeklyKm: number;
	paces: TrainingPaces;
	goalDistanceM: number;
	goalPaceSecPerKm: number;
	masters?: boolean;
}

function generateWeek(w: WeekGenInput): GeneratedWorkout[] {
	const workouts: GeneratedWorkout[] = [];
	// Fixed rest day: Monday. Long run: Sunday.
	// Quality days: Tuesday (intervals or tempo), Thursday (tempo or MP).
	// Masters (Older #30) recover slower, so the first quality day moves
	// to Wednesday — 72h after the Sunday long run instead of 48h — and
	// the second to Friday, keeping ~48h between the two hard sessions.
	// Remaining active days are easy.
	const rest = 1; // Mon
	const longRun = 0; // Sun (weekday 0)
	const qualityA = w.masters ? 3 : 2; // Wed for masters, else Tue
	const qualityB = w.masters ? 5 : 4; // Fri for masters, else Thu
	const daysUsed = new Set<number>([longRun, rest]);
	// Persona-hunt Intermediate #4: a 3-day plan used to be all
	// long-run + easy with zero quality work across every phase — i.e.
	// not a training plan, just a mileage log. A 3-day intermediate
	// runner training for a half should still get one tempo/interval
	// per week (the phase decides which); 4-day plans get qualityA;
	// 5-day plans add qualityB. Race + recovery weeks still produce
	// a null `qualityDistribution.a` and fall through to easy below.
	if (w.daysPerWeek >= 3) daysUsed.add(qualityA);
	if (w.daysPerWeek >= 5) daysUsed.add(qualityB);

	const longRunKm = longRunDistance(w);
	const qualityDistribution = allocateQualityKm(w);
	const remainingKm = Math.max(
		0,
		w.weeklyKm - longRunKm - qualityDistribution.totalKm
	);
	const easyDayCount = w.daysPerWeek - [...daysUsed].filter(
		(d) => d !== rest
	).length;
	const easyKm = easyDayCount > 0 ? remainingKm / easyDayCount : 0;

	for (let dow = 0; dow < 7; dow++) {
		const date = formatISO(addDays(w.weekStart, dow));
		if (dow === rest) {
			workouts.push(emptyWorkout(date, 'rest'));
			continue;
		}
		if (dow === longRun) {
			if (w.phase === 'race') {
				workouts.push({
					scheduled_date: date,
					kind: 'race',
					target_distance_m: w.goalDistanceM,
					target_duration_seconds: null,
					target_pace_sec_per_km: Math.round(w.goalPaceSecPerKm),
					target_pace_tolerance_sec: 5,
					structure: null,
					notes: 'Race day. Execute the plan.'
				});
			} else {
				workouts.push(longRunWorkout(date, longRunKm, w));
			}
			continue;
		}
		// If this phase allocated a quality workout for this slot, use it with
		// the current date. Otherwise fall through to the easy default. The
		// previous implementation mutated qualityDistribution.a with a
		// non-null assertion even when it was null, producing a workout row
		// with only `scheduled_date` — which the DB then rejected on insert
		// because `kind` is NOT NULL. Race week (which allocates nothing)
		// was the trigger.
		if (dow === qualityA && w.daysPerWeek >= 3 && qualityDistribution.a) {
			workouts.push({ ...qualityDistribution.a, scheduled_date: date });
			continue;
		}
		if (dow === qualityB && w.daysPerWeek >= 5 && qualityDistribution.b) {
			workouts.push({ ...qualityDistribution.b, scheduled_date: date });
			continue;
		}
		workouts.push(easyWorkout(date, easyKm, w.paces));
	}

	// Trim to the requested days — remove 'rest' + empty easy days if the
	// runner asked for fewer than 7 slots. Always preserve the long run + any
	// quality sessions we allocated.
	const trimmed = limitToDays(workouts, w.daysPerWeek);
	return trimmed;
}

function limitToDays(ws: GeneratedWorkout[], days: number): GeneratedWorkout[] {
	const activeCount = ws.filter((w) => w.kind !== 'rest').length;
	if (activeCount <= days) return ws;
	// Shouldn't happen with current allocation, but guard against it: drop
	// extra 'easy' workouts from the end of the week.
	let remove = activeCount - days;
	// Drop the auto-generated filler days (easy AND recovery — a short easy
	// day is emitted as 'recovery', which the old check missed, so a 4-day
	// plan silently ran 6 days and stacked floored 3 km recoveries into an
	// impossible week-1 volume — new persona #23). Long runs + quality
	// sessions are always preserved.
	return ws.map((w) => {
		if (remove > 0 && (w.kind === 'easy' || w.kind === 'recovery')) {
			remove--;
			return { ...w, kind: 'rest' as WorkoutKind, target_distance_m: null, target_pace_sec_per_km: null };
		}
		return w;
	});
}

function longRunDistance(w: WeekGenInput): number {
	// Long run scales with the weekly volume, capped at ~35% of the week.
	return Math.round(w.weeklyKm * 0.33);
}

function longRunWorkout(
	date: string,
	km: number,
	w: WeekGenInput
): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: 'long',
		target_distance_m: km * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: w.paces.easy,
		target_pace_tolerance_sec: 20,
		structure: null,
		notes: null
	};
}

function easyWorkout(
	date: string,
	km: number,
	paces: TrainingPaces
): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind: km < 4 ? 'recovery' : 'easy',
		target_distance_m: Math.max(3, Math.round(km)) * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.easy,
		target_pace_tolerance_sec: 30,
		structure: null,
		notes: null
	};
}

function emptyWorkout(date: string, kind: WorkoutKind): GeneratedWorkout {
	return {
		scheduled_date: date,
		kind,
		target_distance_m: null,
		target_duration_seconds: null,
		target_pace_sec_per_km: null,
		target_pace_tolerance_sec: null,
		structure: null,
		notes: null
	};
}

function allocateQualityKm(
	w: WeekGenInput
): { a: GeneratedWorkout | null; b: GeneratedWorkout | null; totalKm: number } {
	const placeholder = '';
	let a: GeneratedWorkout | null = null;
	let b: GeneratedWorkout | null = null;
	if (w.phase === 'base') {
		if (w.daysPerWeek >= 3) a = tempoWorkout(placeholder, 6, w.paces);
	} else if (w.phase === 'build') {
		if (w.daysPerWeek >= 3) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5) b = tempoWorkout(placeholder, 7, w.paces);
	} else if (w.phase === 'peak') {
		if (w.daysPerWeek >= 3) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5)
			b = marathonPaceWorkout(placeholder, w.paces, w.goalDistanceM);
	} else if (w.phase === 'taper') {
		if (w.daysPerWeek >= 3) a = tempoWorkout(placeholder, 4, w.paces);
	}
	const totalKm =
		(a?.target_distance_m ?? 0) / 1000 + (b?.target_distance_m ?? 0) / 1000;
	return { a, b, totalKm };
}

function tempoWorkout(
	date: string,
	totalKm: number,
	paces: TrainingPaces
): GeneratedWorkout {
	const steady = Math.max(2, totalKm - 3);
	return {
		scheduled_date: date,
		kind: 'tempo',
		target_distance_m: totalKm * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.tempo,
		target_pace_tolerance_sec: 8,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			steady: { distance_m: steady * 1000, pace_sec_per_km: paces.tempo },
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: `Tempo: ${steady} km @ threshold.`
	};
}

function intervalsWorkout(date: string, paces: TrainingPaces): GeneratedWorkout {
	const reps = 5;
	const repDistance = 1000;
	const recovery = 400;
	return {
		scheduled_date: date,
		kind: 'interval',
		target_distance_m: 1500 + reps * (repDistance + recovery) + 1500,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.interval,
		target_pace_tolerance_sec: 5,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			repeats: {
				count: reps,
				distance_m: repDistance,
				pace_sec_per_km: paces.interval,
				recovery_distance_m: recovery,
				recovery_pace: 'jog'
			},
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: `${reps}× ${repDistance} m @ VO2 with ${recovery} m jog.`
	};
}

function marathonPaceWorkout(
	date: string,
	paces: TrainingPaces,
	goalDistanceM: number
): GeneratedWorkout {
	const mpKm = goalDistanceM >= 21_000 ? 10 : 5;
	return {
		scheduled_date: date,
		kind: 'marathon_pace',
		target_distance_m: (mpKm + 3) * 1000,
		target_duration_seconds: null,
		target_pace_sec_per_km: paces.marathon,
		target_pace_tolerance_sec: 8,
		structure: {
			warmup: { distance_m: 1500, pace: 'easy' },
			steady: { distance_m: mpKm * 1000, pace_sec_per_km: paces.marathon },
			cooldown: { distance_m: 1500, pace: 'easy' }
		},
		notes: `${mpKm} km @ goal marathon pace.`
	};
}

/// A workout is "done" if a tracked run has been auto-matched to it
/// (`completed_run_id`) or the user manually marked it from the editor
/// (`manually_completed`). Both fields can be set together once a real
/// run lands; either alone is enough to count as done.
export function isWorkoutCompleted(
	wo: { manually_completed?: boolean | null; completed_run_id?: string | null }
): boolean {
	return wo.manually_completed === true || wo.completed_run_id != null;
}

// ─────────────────────── Date helpers ───────────────────────
// Pure ISO date helpers (YYYY-MM-DD). Intentionally UTC-free — the caller
// feeds the runner's local date; all internal math is in day counts.

export function parseISO(s: string): Date {
	const [y, m, d] = s.split('-').map(Number);
	return new Date(y, m - 1, d);
}

export function formatISO(d: Date): string {
	const pad = (n: number) => String(n).padStart(2, '0');
	return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/**
 * "Today" in the *local* timezone as yyyy-mm-dd. Use this instead of
 * `new Date().toISOString().slice(0, 10)` — `toISOString` formats in UTC,
 * so in any positive-offset timezone it rolls over before midnight local
 * and the date comes out a day early. Mirror of `formatISO(new Date())`.
 */
export function todayISO(): string {
	return formatISO(new Date());
}

export function addDays(d: Date, n: number): Date {
	const c = new Date(d);
	c.setDate(c.getDate() + n);
	return c;
}

// ─────────────────────── Formatters ───────────────────────
//
// `fmtKm` / `fmtPace` (unit-aware, used by every plan surface) live in
// `./units.svelte` so that this file stays pure TS — `training.test.ts`
// runs under `tsx --test` which can't resolve Svelte runes. Import
// them from `$lib/format/units.svelte` at the call site.

export function fmtHms(sec: number | null | undefined): string {
	// `!sec` catches 0/null/NaN but a NEGATIVE is truthy and would format a
	// nonsensical negative clock (e.g. -90 → "-2:-30"); guard <= 0 too, matching
	// the Dart twin (`sec == null || sec <= 0`).
	if (!sec || sec <= 0) return '—';
	const h = Math.floor(sec / 3600);
	const m = Math.floor((sec % 3600) / 60);
	const s = Math.floor(sec % 60);
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}

