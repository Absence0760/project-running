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

// ─────────────────────── Training paces ───────────────────────

export interface TrainingPaces {
	easy: number; // seconds per km
	marathon: number;
	tempo: number;
	interval: number;
	repetition: number;
}

/**
 * Derive the five Daniels intensity-zone paces as multipliers of goal-race
 * pace. Numbers chosen so the output sits close to Daniels' published tables
 * across the 3:00–5:00/km goal-pace band. `goalPaceSecPerKm` is the runner's
 * target pace for the goal race.
 */
export function pacesFromGoalPace(goalPaceSecPerKm: number): TrainingPaces {
	// Goal pace sits between marathon and tempo intensity for most runners.
	// These multipliers are a simplification of Daniels' percentages and are
	// stable across the typical distance/goal-time grid; see the regression
	// tests in training.test.ts.
	return {
		easy: Math.round(goalPaceSecPerKm * 1.22),
		marathon: Math.round(goalPaceSecPerKm * 1.06),
		tempo: Math.round(goalPaceSecPerKm * 0.97),
		interval: Math.round(goalPaceSecPerKm * 0.9),
		repetition: Math.round(goalPaceSecPerKm * 0.85)
	};
}

/**
 * Resolve the runner's training paces from whichever anchor they gave us.
 * Priority: an explicit recent 5k time (use Riegel to predict goal-distance
 * pace) → a goal time on the target distance (use directly) → fall back to a
 * conservative "10:00/km as goal" so the plan still generates for someone
 * without any race history.
 */
export function resolveTrainingPaces(input: {
	goalDistanceM: number;
	goalTimeSec?: number | null;
	recent5kSec?: number | null;
}): TrainingPaces {
	let goalPaceSecPerKm: number;
	if (input.recent5kSec) {
		const predicted = riegelPredict(5000, input.recent5kSec, input.goalDistanceM);
		goalPaceSecPerKm = predicted / (input.goalDistanceM / 1000);
	} else if (input.goalTimeSec) {
		goalPaceSecPerKm = input.goalTimeSec / (input.goalDistanceM / 1000);
	} else {
		goalPaceSecPerKm = 600;
	}
	return pacesFromGoalPace(goalPaceSecPerKm);
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
 * not. See `docs/training.md` for the shape spec.
 */
export interface WorkoutStructure {
	warmup?: { distance_m: number; pace: 'easy' };
	repeats?: {
		count: number;
		distance_m: number;
		pace_sec_per_km: number;
		recovery_distance_m: number;
		recovery_pace: 'easy' | 'jog';
	};
	steady?: { distance_m: number; pace_sec_per_km: number };
	cooldown?: { distance_m: number; pace: 'easy' };
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
}

export interface GeneratedPlan {
	weeks: GeneratedWeek[];
	paces: TrainingPaces;
	vdot: number | null;
	endDate: string; // ISO date
	goalDistanceM: number;
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
	const paces = resolveTrainingPaces({
		goalDistanceM,
		goalTimeSec: input.goalTimeSec,
		recent5kSec: input.recent5kSec
	});
	const vdot = input.recent5kSec
		? vdotFromRace(5000, input.recent5kSec)
		: input.goalTimeSec
		? vdotFromRace(goalDistanceM, input.goalTimeSec)
		: null;

	const startDate = parseISO(input.startDate);
	const weeks: GeneratedWeek[] = [];

	for (let i = 0; i < totalWeeks; i++) {
		const phase = phaseFor(i, totalWeeks);
		// Mileage curve: ramp from 0.6× peak at week 0 up to 1.0× at peak-end,
		// then drop to 0.5× in taper and 0.35× in race week.
		const peakWeeklyKm = peakVolumeKm(goalDistanceM, input.daysPerWeek);
		const fraction = mileageFraction(i, totalWeeks, phase);
		const weeklyKm = Math.round(peakWeeklyKm * fraction);
		const workouts = generateWeek({
			weekIndex: i,
			phase,
			weekStart: addDays(startDate, i * 7),
			daysPerWeek: input.daysPerWeek,
			weeklyKm,
			paces,
			goalDistanceM,
			goalPaceSecPerKm: paces.marathon * (goalDistanceM >= 21_000 ? 1 : 0.95)
		});
		weeks.push({
			week_index: i,
			phase,
			target_volume_m: weeklyKm * 1000,
			notes: weekNote(phase, i, totalWeeks),
			workouts
		});
	}

	const endDate = addDays(startDate, totalWeeks * 7 - 1);
	return {
		weeks,
		paces,
		vdot,
		endDate: formatISO(endDate),
		goalDistanceM
	};
}

function peakVolumeKm(goalDistanceM: number, daysPerWeek: number): number {
	// Rough volumes: ~4× goal for 5k/10k runners, ~2.5× for half, ~1.8× for full,
	// scaled gently by training days. Tuneable; see tests for expected outputs.
	const baseMultiplier =
		goalDistanceM <= 10_000 ? 5 : goalDistanceM <= 21_100 ? 2.5 : 1.8;
	const dayFactor = 0.7 + (daysPerWeek - 3) * 0.1;
	return Math.round((goalDistanceM / 1000) * baseMultiplier * dayFactor);
}

function mileageFraction(i: number, total: number, phase: PlanPhase): number {
	if (phase === 'race') return 0.35;
	if (phase === 'taper') return 0.55;
	// Linear ramp inside base+build+peak, with a 0.8× step-back every 4th week.
	const ramp = 0.6 + (0.4 * i) / Math.max(1, total - 3);
	const stepBack = i > 0 && i % 4 === 3 ? 0.82 : 1;
	return Math.min(1, ramp * stepBack);
}

function weekNote(phase: PlanPhase, i: number, total: number): string | null {
	if (phase === 'race') return 'Race week — trust the work.';
	if (phase === 'taper') return 'Taper — volume down, sharpness stays.';
	if (i > 0 && i % 4 === 3) return 'Step-back week — recover before the next build.';
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
}

function generateWeek(w: WeekGenInput): GeneratedWorkout[] {
	const workouts: GeneratedWorkout[] = [];
	// Fixed rest day: Monday. Long run: Sunday.
	// Quality days: Tuesday (intervals or tempo), Thursday (tempo or MP).
	// Remaining active days are easy.
	const rest = 1; // Mon
	const longRun = 0; // Sun (weekday 0)
	const qualityA = 2; // Tue
	const qualityB = 4; // Thu
	const daysUsed = new Set<number>([longRun, rest]);
	if (w.daysPerWeek >= 4) daysUsed.add(qualityA);
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
		if (dow === qualityA && w.daysPerWeek >= 4 && qualityDistribution.a) {
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
	return ws.map((w) => {
		if (remove > 0 && w.kind === 'easy') {
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
		if (w.daysPerWeek >= 4) a = tempoWorkout(placeholder, 6, w.paces);
	} else if (w.phase === 'build') {
		if (w.daysPerWeek >= 4) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5) b = tempoWorkout(placeholder, 7, w.paces);
	} else if (w.phase === 'peak') {
		if (w.daysPerWeek >= 4) a = intervalsWorkout(placeholder, w.paces);
		if (w.daysPerWeek >= 5)
			b = marathonPaceWorkout(placeholder, w.paces, w.goalDistanceM);
	} else if (w.phase === 'taper') {
		if (w.daysPerWeek >= 4) a = tempoWorkout(placeholder, 4, w.paces);
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
// them from `$lib/units.svelte` at the call site.

export function fmtHms(sec: number | null | undefined): string {
	if (!sec) return '—';
	const h = Math.floor(sec / 3600);
	const m = Math.floor((sec % 3600) / 60);
	const s = Math.floor(sec % 60);
	if (h > 0) return `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`;
	return `${m}:${String(s).padStart(2, '0')}`;
}

export const WORKOUT_KIND_LABEL: Record<WorkoutKind, string> = {
	easy: 'Easy',
	long: 'Long run',
	recovery: 'Recovery',
	tempo: 'Tempo',
	interval: 'Intervals',
	marathon_pace: 'Marathon pace',
	race: 'Race',
	rest: 'Rest'
};

export const PHASE_LABEL: Record<PlanPhase, string> = {
	base: 'Base',
	build: 'Build',
	peak: 'Peak',
	taper: 'Taper',
	race: 'Race week'
};
