// Gym personal-record computation (Phase 4 multi-modal, decisions §63;
// spec: docs/features/multi_modal.md § Gym).
//
// Pure functions — no Svelte / Supabase dependencies, so the module runs
// under `npx tsx --test`. The Dart twin is apps/mobile_android/lib/gym_prs.dart
// (parity pair — keep algorithm, edge cases, outputs, and test counts in
// lockstep). Callers shape gym_sets rows into the plain `GymSetLike` shape.
//
// Three PR metrics per (user, exercise) the spec calls for — "heaviest set /
// most volume / best rep-PR":
//   weight  — heaviest single set (max weight_kg).
//   volume  — biggest single-set volume (reps × weight_kg).
//   e1rm    — best estimated one-rep-max (Epley), which is the meaningful
//             "rep PR": a 5×100 kg outranks a 1×105 kg in real strength.
// All three are single-set metrics so they're deterministic and a typo in
// one set can't poison a session aggregate.

export interface GymSetLike {
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
}

export type PrKind = 'weight' | 'volume' | 'e1rm';

export interface ExercisePr {
	/// Display spelling — the original `exercise_name` of the first set (in
	/// input order) that maps to this normalised key. Deterministic across
	/// TS/Dart given the same input order.
	exerciseName: string;
	/// Heaviest single-set weight, kg. Null if no set had a positive weight.
	heaviestWeightKg: number | null;
	/// Reps performed at the heaviest weight (for "100 kg × 5" display).
	heaviestWeightReps: number | null;
	/// Best single-set volume (reps × weight_kg), kg. Null if none qualified.
	bestVolumeKg: number | null;
	/// Best estimated one-rep-max (Epley), kg, rounded to 1 dp. Null if none.
	bestEst1RmKg: number | null;
}

/// Reps beyond this are clamped for the e1rm estimate — Epley loses accuracy
/// past ~10-12 reps, and an endurance set (e.g. 30 reps) would otherwise
/// manufacture an absurd 1RM and a phantom PR. The set still counts; only the
/// rep multiplier saturates.
export const kE1rmMaxReps = 12;

/// Estimated one-rep-max via the Epley formula `w · (1 + reps/30)`, with a
/// true single (reps === 1) reported as the lifted weight itself rather than
/// the formula's slight 3.3% inflation. Returns 0 for non-positive inputs.
export function estimatedOneRepMax(weightKg: number, reps: number): number {
	if (!(weightKg > 0) || !(reps > 0)) return 0;
	if (reps === 1) return weightKg;
	const r = Math.min(reps, kE1rmMaxReps);
	return weightKg * (1 + r / 30);
}

/// Normalise a free-text exercise name for grouping: whitespace folded to
/// single spaces and trimmed, the runtime-divergent case mappings applied by
/// hand, then lower-cased. "Bench Press", "bench  press" and "  Bench press "
/// all collapse to one PR bucket.
///
/// Every step is spelled out rather than delegated to a runtime default,
/// because this value is PERSISTED and a third rail derives it in SQL. The
/// trim is a regex over the single space the fold leaves, not `String.trim()`,
/// whose class differs from Dart's and from `btrim`'s.
export function normaliseExerciseName(name: string): string {
	return name
		.replace(EXERCISE_WS, ' ')
		.replace(/^ +| +$/g, '')
		.replace(EXERCISE_CASE_FOLD, (c) => EXERCISE_CASE_MAP[c])
		.toLowerCase();
}

/// The whitespace class all THREE rails fold, spelled out rather than left to
/// each runtime's default.
///
/// This value is PERSISTED as `gym_routine_exercises.exercise_key`, and the
/// server derives it too: `normalise_exercise_name()` (migration
/// `20270623000001`) is the SQL twin, and every gym RPC that groups or matches
/// on an exercise goes through it. A disagreement splits or merges a lifter's
/// history, so the three must name the identical set --
/// `scripts/check_shared_constants.mjs` reads all three and fails the PR when
/// they drift. Mirrors `kExerciseWhitespace` in `gym_prs.dart`.
const EXERCISE_WS =
	/[\t\n\v\f\r \u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000\ufeff]+/g;

/// The code points where the three rails' own case folding was measured to
/// disagree, mapped by hand so that none of them decides.
///
/// U+0130 is the one that matters: JS applies Unicode's FULL lowercase mapping
/// and yields `i` + U+0307, where Dart's simple folding and libc's `towlower`
/// both yield a bare `i` -- so a Turkish lifter's name keyed one way on web and
/// another way on the phone and the server, on a STORED key. The four
/// titlecase digraphs are the same shape one step rarer. Everything outside
/// this table is left to each rail's own `lower()`; the residual disagreement
/// is confined to Cherokee, Coptic, Glagolitic, Georgian Mtavruli and the
/// Cyrillic/Latin Extended-B additions, which no exercise name reaches.
/// decisions.md § 790. Mirrors `kExerciseCaseFold` in `gym_prs.dart`.
const EXERCISE_CASE_FOLD = /[\u0130\u01c5\u01c8\u01cb\u01f2]/g;
const EXERCISE_CASE_MAP: Record<string, string> = {
	'\u0130': 'i',
	'\u01c5': '\u01c6',
	'\u01c8': '\u01c9',
	'\u01cb': '\u01cc',
	'\u01f2': '\u01f3'
};

function round1(n: number): number {
	return Math.round(n * 10) / 10;
}

/// Compute the PR table across a flat set list, keyed by normalised exercise
/// name. Sets with a blank exercise name are ignored. Insertion order of the
/// returned Map follows first appearance of each exercise in `sets`.
/// Fold one set into a running PR map (max of each metric). The shared
/// per-set body of [computeExercisePrs] + [RunningPrTracker] so the two can't
/// diverge. A blank exercise name is ignored.
function accumulateSet(out: Map<string, ExercisePr>, s: GymSetLike): void {
	const key = normaliseExerciseName(s.exercise_name ?? '');
	if (key === '') return;
	const weight = numericOrNull(s.weight_kg);
	const reps = numericOrNull(s.reps);

	let pr = out.get(key);
	if (!pr) {
		pr = {
			exerciseName: s.exercise_name,
			heaviestWeightKg: null,
			heaviestWeightReps: null,
			bestVolumeKg: null,
			bestEst1RmKg: null,
		};
		out.set(key, pr);
	}

	if (weight != null && weight > 0) {
		// Heaviest weight; ties broken by more reps at that weight.
		if (
			pr.heaviestWeightKg == null ||
			weight > pr.heaviestWeightKg ||
			(weight === pr.heaviestWeightKg && (reps ?? 0) > (pr.heaviestWeightReps ?? 0))
		) {
			pr.heaviestWeightKg = weight;
			pr.heaviestWeightReps = reps ?? null;
		}
		if (reps != null && reps > 0) {
			const volume = weight * reps;
			if (pr.bestVolumeKg == null || volume > pr.bestVolumeKg) {
				pr.bestVolumeKg = round1(volume);
			}
			const e1rm = estimatedOneRepMax(weight, reps);
			if (pr.bestEst1RmKg == null || e1rm > pr.bestEst1RmKg) {
				pr.bestEst1RmKg = round1(e1rm);
			}
		}
	}
}

export function computeExercisePrs(sets: GymSetLike[]): Map<string, ExercisePr> {
	const out = new Map<string, ExercisePr>();
	for (const s of sets) accumulateSet(out, s);
	return out;
}

export interface WorkoutPrResult {
	/// Display spelling of the exercise that set the PR(s).
	exerciseName: string;
	/// Which metrics this workout's sets newly bettered vs. all prior sets.
	kinds: PrKind[];
}

/// Which PRs a workout newly set, given every set logged BEFORE it. A kind is
/// reported only when this workout strictly beats the prior best for that
/// exercise+metric (or there was no prior set at all). Drives the History-row
/// "PR" badge and the per-exercise chips on the detail screen.
///
/// `priorSets` must exclude the workout's own sets — pass only sets from
/// earlier workouts. Order within each list is irrelevant to the result.
export function workoutPrs(
	priorSets: GymSetLike[],
	workoutSets: GymSetLike[],
): WorkoutPrResult[] {
	const prior = computeExercisePrs(priorSets);
	const current = computeExercisePrs(workoutSets);
	const results: WorkoutPrResult[] = [];

	for (const [key, cur] of current) {
		const before = prior.get(key);
		const kinds: PrKind[] = [];
		if (beats(cur.heaviestWeightKg, before?.heaviestWeightKg)) kinds.push('weight');
		if (beats(cur.bestVolumeKg, before?.bestVolumeKg)) kinds.push('volume');
		if (beats(cur.bestEst1RmKg, before?.bestEst1RmKg)) kinds.push('e1rm');
		if (kinds.length > 0) results.push({ exerciseName: cur.exerciseName, kinds });
	}
	return results;
}

/// Single-pass PR detector for the chronological "did THIS workout set a PR vs
/// everything before it?" question asked once per workout when walking
/// oldest→newest. Maintains ONE running PR map and folds each workout's sets in
/// after judging it — O(total sets) with one normalise per set, versus calling
/// [workoutPrs] in a loop with a growing priorSets array (which re-derives the
/// full prior map every workout: O(workouts × prior sets)). Results are
/// identical to that loop because the metric updates are order-independent maxes.
export class RunningPrTracker {
	private readonly running = new Map<string, ExercisePr>();

	/// Judge [workoutSets] against all sets folded in so far, then fold them in.
	/// Same semantics as [workoutPrs]`(everythingBefore, workoutSets)`.
	judge(workoutSets: GymSetLike[]): WorkoutPrResult[] {
		const current = computeExercisePrs(workoutSets);
		const results: WorkoutPrResult[] = [];
		for (const [key, cur] of current) {
			const before = this.running.get(key);
			const kinds: PrKind[] = [];
			if (beats(cur.heaviestWeightKg, before?.heaviestWeightKg)) kinds.push('weight');
			if (beats(cur.bestVolumeKg, before?.bestVolumeKg)) kinds.push('volume');
			if (beats(cur.bestEst1RmKg, before?.bestEst1RmKg)) kinds.push('e1rm');
			if (kinds.length > 0) results.push({ exerciseName: cur.exerciseName, kinds });
		}
		for (const s of workoutSets) accumulateSet(this.running, s);
		return results;
	}
}

/// True when `current` is a real value that strictly exceeds `prior`
/// (treating an absent prior as "any positive value is a PR").
function beats(current: number | null, prior: number | null | undefined): boolean {
	if (current == null) return false;
	if (prior == null) return true;
	return current > prior;
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}
