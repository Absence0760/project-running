import { estimatedOneRepMax, normaliseExerciseName } from './gym_prs';

export { estimatedOneRepMax, normaliseExerciseName };

export type ProgressionScheme =
	| 'none'
	| 'linear'
	| 'double_progression'
	| 'five_by_five'
	| 'percent_cycle'
	| 'rpe_autoreg';

export interface ProgressionSetLike {
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	/// gym_sets.set_type — raw string (matches the DB CHECK union). A ramp-up
	/// set is not evidence about the working target, so it must not be judged
	/// against it. Absent/null reads as 'working', matching the column default.
	set_type?: string | null;
}

export interface ProgressionInput {
	scheme: ProgressionScheme;
	lastSets: ProgressionSetLike[];
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	params: Record<string, unknown> | null;
}

export type ProgressionReason =
	| 'increase_weight'
	| 'increase_reps'
	| 'hold'
	| 'establish_baseline'
	| 'deload'
	| 'none';

export interface ProgressionSuggestion {
	suggestedWeightKg: number | null;
	suggestedRepsMin: number | null;
	suggestedRepsMax: number | null;
	reason: ProgressionReason;
}

function round1(n: number): number {
	return Math.round(n * 10) / 10;
}

function numericOrNull(v: unknown): number | null {
	if (typeof v === 'number' && Number.isFinite(v)) return v;
	if (typeof v === 'string') {
		const n = Number(v);
		return Number.isFinite(n) ? n : null;
	}
	return null;
}

function positiveOr(v: unknown, fallback: number): number {
	const n = numericOrNull(v);
	return n != null && n > 0 ? n : fallback;
}

/// The sets that are evidence about the working target: warmups dropped (a
/// ramp-up is not an attempt at the prescription) and rep-less rows dropped
/// (`gym_sets.reps` is nullable and CHECK-allows 0). Shared with the
/// consecutive-miss reducer so a past session is judged by exactly the sets the
/// prescriber judges the last one by.
export function completedWorkingSets(sets: ProgressionSetLike[]): ProgressionSetLike[] {
	return sets.filter((s) => {
		if ((s.set_type ?? 'working') === 'warmup') return false;
		const r = numericOrNull(s.reps);
		return r != null && r > 0;
	});
}

export interface FiveByFiveTargets {
	targetSets: number;
	targetReps: number;
}

/// The 5×5 bar for one session — how many working sets at how many reps clear
/// it. The routine's own rep target wins, then `params.targetReps`, then the
/// classic five. Exported so a caller deriving the miss streak from history
/// grades an older session by the same bar.
export function fiveByFiveTargets(input: {
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	params: Record<string, unknown> | null;
}): FiveByFiveTargets {
	const params = input.params ?? {};
	const repsMin = numericOrNull(input.targetRepsMin);
	const repsMax = numericOrNull(input.targetRepsMax);
	return {
		targetSets: positiveOr(params.targetSets, 5),
		targetReps: repsMax ?? repsMin ?? positiveOr(params.targetReps, 5),
	};
}

/// Did one session clear the bar? At least `targetSets` completed working sets,
/// every one of them reaching `targetReps`.
export function fiveByFiveSessionSucceeded(
	sets: ProgressionSetLike[],
	targets: FiveByFiveTargets,
): boolean {
	const completed = completedWorkingSets(sets);
	return (
		completed.length >= targets.targetSets &&
		completed.every((s) => (numericOrNull(s.reps) ?? 0) >= targets.targetReps)
	);
}

/// The heaviest weight the lifter actually COMPLETED — the anchor a load
/// increment is added to. Null when no completed set carried a positive weight
/// (bodyweight work). Callers must pass the completed subset: anchoring on a
/// set that was merely attempted prescribes a load off a weight the lifter
/// failed to lift.
function topWeight(sets: ProgressionSetLike[]): number | null {
	let top: number | null = null;
	for (const s of sets) {
		const w = numericOrNull(s.weight_kg);
		if (w != null && w > 0 && (top == null || w > top)) top = w;
	}
	return top;
}

/// A weight increment can never drive the prescription below zero — guards the
/// degenerate case where params hand us a negative step.
function safeAdd(weightKg: number, deltaKg: number): number {
	const next = weightKg + deltaKg;
	return next > 0 ? round1(next) : round1(weightKg);
}

export function nextPrescription(input: ProgressionInput): ProgressionSuggestion {
	const none: ProgressionSuggestion = {
		suggestedWeightKg: null,
		suggestedRepsMin: null,
		suggestedRepsMax: null,
		reason: 'none',
	};
	if (input.scheme === 'none') return none;

	const params = input.params ?? {};
	const sets = input.lastSets ?? [];
	// Warmups are excluded before anything is judged. Every "did they hit the
	// target?" test below is an `every` over this list, so a 2-rep ramp-up set
	// counted as a failed working set and held the load — forever, for anyone
	// who warms up, which is everyone. `gym_adherence` states the same rule for
	// planned-vs-actual grading; the prescriber simply never received the
	// column. A null set_type is 'working', matching the DB default.
	const completed = completedWorkingSets(sets);

	const repsMin = numericOrNull(input.targetRepsMin);
	const repsMax = numericOrNull(input.targetRepsMax);
	// Anchor on what was COMPLETED, not on what was attempted. `gym_sets.reps`
	// is nullable and CHECK-allows 0, and the editor writes a row for every set
	// typed — so "weight entered, reps left blank" and "failed attempt logged
	// as 0" are normal shapes. Scanning the raw list made the failed heavier
	// attempt the anchor and then added the increment to it, prescribing more
	// than a weight the lifter had just missed.
	const weight = topWeight(completed);
	const step = positiveOr(params.incrementKg, 2.5);

	switch (input.scheme) {
		case 'linear': {
			const topReps = repsMax ?? repsMin;
			if (completed.length === 0 || topReps == null) {
				return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
			}
			const allHit = completed.every((s) => (numericOrNull(s.reps) ?? 0) >= topReps);
			if (allHit) {
				if (weight != null) {
					return {
						suggestedWeightKg: safeAdd(weight, step),
						suggestedRepsMin: repsMin,
						suggestedRepsMax: repsMax,
						reason: 'increase_weight',
					};
				}
				// Bodyweight: no load to add, so genuinely progress by raising the rep
				// target — returning the unchanged reps labelled "increase_reps" told
				// the user to do more while prescribing the same count (the same bug the
				// double_progression / five_by_five bodyweight paths fixed). Raise the
				// top of the range, or the single value when there's no range.
				return {
					suggestedWeightKg: null,
					suggestedRepsMin: repsMin == null ? null : repsMin + (repsMax == null ? 1 : 0),
					suggestedRepsMax: repsMax == null ? null : repsMax + 1,
					reason: 'increase_reps',
				};
			}
			return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
		}

		case 'double_progression': {
			if (completed.length === 0 || repsMax == null) {
				return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
			}
			const atTop = completed.every((s) => (numericOrNull(s.reps) ?? 0) >= repsMax);
			if (atTop) {
				if (weight != null) {
					// Weighted: add load and drop back to the bottom of the rep range.
					return {
						suggestedWeightKg: safeAdd(weight, step),
						suggestedRepsMin: repsMin,
						suggestedRepsMax: repsMin,
						reason: 'increase_weight',
					};
				}
				// Bodyweight: no load to add, so genuinely progress by raising the rep
				// ceiling. Collapsing the range back to repsMin here used to suggest
				// FEWER reps (e.g. 12 → 8) while labelling it "increase_reps".
				return {
					suggestedWeightKg: null,
					suggestedRepsMin: repsMin,
					suggestedRepsMax: repsMax + 1,
					reason: 'increase_reps',
				};
			}
			return {
				suggestedWeightKg: weight,
				suggestedRepsMin: repsMin,
				suggestedRepsMax: repsMax,
				reason: 'increase_reps',
			};
		}

		case 'five_by_five': {
			const { targetSets, targetReps } = fiveByFiveTargets(input);
			const maxMisses = positiveOr(params.maxConsecutiveMisses, 3);
			// Author-set params never carry this — it is derived from logged
			// history by progression_prefill.progressionParamsWithStreak, without
			// which the deload branch below is unreachable.
			const misses = positiveOr(params.consecutiveMisses, 0);
			const success = fiveByFiveSessionSucceeded(sets, { targetSets, targetReps });

			if (success) {
				if (weight != null) {
					return {
						suggestedWeightKg: safeAdd(weight, step),
						suggestedRepsMin: targetReps,
						suggestedRepsMax: targetReps,
						reason: 'increase_weight',
					};
				}
				// Bodyweight: no load to add — progress by raising the rep target
				// rather than re-prescribing the same count as "increase_reps".
				return {
					suggestedWeightKg: null,
					suggestedRepsMin: targetReps + 1,
					suggestedRepsMax: targetReps + 1,
					reason: 'increase_reps',
				};
			}
			if (misses >= maxMisses) {
				const deloaded =
					weight != null ? round1(weight * positiveOr(params.deloadFactor, 0.9)) : null;
				return {
					suggestedWeightKg: deloaded,
					suggestedRepsMin: targetReps,
					suggestedRepsMax: targetReps,
					reason: 'deload',
				};
			}
			return {
				suggestedWeightKg: weight,
				suggestedRepsMin: targetReps,
				suggestedRepsMax: targetReps,
				reason: 'hold',
			};
		}

		case 'percent_cycle': {
			const percent = numericOrNull(params.percent);
			const oneRm = numericOrNull(params.oneRmKg);
			if (percent == null || oneRm == null || !(percent > 0) || !(oneRm > 0)) {
				return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
			}
			const prescribed = round1(percent * oneRm);
			// A first/bodyweight session has no prior top weight to compare against,
			// so the prescription isn't a "hold" of anything — it's the starting load.
			const reason: ProgressionReason =
				weight == null
					? 'establish_baseline'
					: prescribed > weight
						? 'increase_weight'
						: 'hold';
			return {
				suggestedWeightKg: prescribed,
				suggestedRepsMin: repsMin,
				suggestedRepsMax: repsMax,
				reason,
			};
		}

		case 'rpe_autoreg': {
			const targetRpe = numericOrNull(params.targetRpe);
			const achieved = numericOrNull(
				completed.reduce<number | null>((acc, s) => {
					const r = numericOrNull(s.rpe);
					if (r == null) return acc;
					return acc == null ? r : Math.max(acc, r);
				}, null),
			);
			if (targetRpe == null || achieved == null) {
				return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
			}
			if (achieved < targetRpe) {
				if (weight != null) {
					return {
						suggestedWeightKg: safeAdd(weight, step),
						suggestedRepsMin: repsMin,
						suggestedRepsMax: repsMax,
						reason: 'increase_weight',
					};
				}
				// Bodyweight: no load to add — raise the rep target rather than
				// re-prescribing the same count under an "increase_reps" label.
				return {
					suggestedWeightKg: null,
					suggestedRepsMin: repsMin == null ? null : repsMin + (repsMax == null ? 1 : 0),
					suggestedRepsMax: repsMax == null ? null : repsMax + 1,
					reason: 'increase_reps',
				};
			}
			return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
		}

		default:
			return none;
	}
}
