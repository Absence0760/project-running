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

/// Normalise a free-text exercise name for grouping: trimmed, lower-cased,
/// internal whitespace collapsed. "Bench Press", "bench  press" and
/// "  Bench press " all collapse to one PR bucket.
export function normaliseExerciseName(name: string): string {
	return name.trim().toLowerCase().replace(/\s+/g, ' ');
}

function round1(n: number): number {
	return Math.round(n * 10) / 10;
}

/// Compute the PR table across a flat set list, keyed by normalised exercise
/// name. Sets with a blank exercise name are ignored. Insertion order of the
/// returned Map follows first appearance of each exercise in `sets`.
export function computeExercisePrs(sets: GymSetLike[]): Map<string, ExercisePr> {
	const out = new Map<string, ExercisePr>();
	for (const s of sets) {
		const key = normaliseExerciseName(s.exercise_name ?? '');
		if (key === '') continue;
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
