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

/// The heaviest working weight across the session — the anchor a load increment
/// is added to. Null when no set carried a positive weight (bodyweight work).
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
	const completed = sets.filter((s) => {
		const r = numericOrNull(s.reps);
		return r != null && r > 0;
	});

	const repsMin = numericOrNull(input.targetRepsMin);
	const repsMax = numericOrNull(input.targetRepsMax);
	const weight = topWeight(sets);
	const step = positiveOr(params.incrementKg, 2.5);

	switch (input.scheme) {
		case 'linear': {
			const topReps = repsMax ?? repsMin;
			if (completed.length === 0 || topReps == null) {
				return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
			}
			const allHit = completed.every((s) => (numericOrNull(s.reps) ?? 0) >= topReps);
			if (allHit) {
				return {
					suggestedWeightKg: weight != null ? safeAdd(weight, step) : null,
					suggestedRepsMin: repsMin,
					suggestedRepsMax: repsMax,
					reason: weight != null ? 'increase_weight' : 'increase_reps',
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
				return {
					suggestedWeightKg: weight != null ? safeAdd(weight, step) : null,
					suggestedRepsMin: repsMin,
					suggestedRepsMax: repsMin,
					reason: weight != null ? 'increase_weight' : 'increase_reps',
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
			const targetSets = positiveOr(params.targetSets, 5);
			const targetReps = repsMax ?? repsMin ?? positiveOr(params.targetReps, 5);
			const maxMisses = positiveOr(params.maxConsecutiveMisses, 3);
			const misses = positiveOr(params.consecutiveMisses, 0);
			const success =
				completed.length >= targetSets &&
				completed.every((s) => (numericOrNull(s.reps) ?? 0) >= targetReps);

			if (success) {
				return {
					suggestedWeightKg: weight != null ? safeAdd(weight, step) : null,
					suggestedRepsMin: targetReps,
					suggestedRepsMax: targetReps,
					reason: weight != null ? 'increase_weight' : 'increase_reps',
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
			return {
				suggestedWeightKg: prescribed,
				suggestedRepsMin: repsMin,
				suggestedRepsMax: repsMax,
				reason: weight != null && prescribed > weight ? 'increase_weight' : 'hold',
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
				return {
					suggestedWeightKg: weight != null ? safeAdd(weight, step) : null,
					suggestedRepsMin: repsMin,
					suggestedRepsMax: repsMax,
					reason: weight != null ? 'increase_weight' : 'increase_reps',
				};
			}
			return { suggestedWeightKg: weight, suggestedRepsMin: repsMin, suggestedRepsMax: repsMax, reason: 'hold' };
		}

		default:
			return none;
	}
}
