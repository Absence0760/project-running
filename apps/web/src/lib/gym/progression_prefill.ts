// Web-only glue between the logged-set history and the gym_progression
// prescriber (gym_programming.md P4). Pure — no DB, no Svelte. It picks the most
// recent logged session of an exercise and reduces it to the ProgressionSetLike
// list nextPrescription consumes. The prescriber itself is the parity pair
// gym_progression.ts ↔ gym_progression.dart and is NOT touched here — we only
// call it. The mobile twin ports this glue inline against the same Dart
// prescriber.

import { normaliseExerciseName } from './gym_prs';
import type { ProgressionSetLike } from './gym_progression';

export interface DatedLoggedSet {
	workout_id: string;
	started_at: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
}

/// The raw sets of the most recent logged session of `exerciseName`, matched by
/// normalised key, in their logged order. Null when the exercise has never been
/// logged (the prescriber treats a null `lastActuals` as a first session).
/// "Most recent" is by `started_at`, ties broken by workout id so the choice is
/// deterministic — mirroring exercise_history's ordering.
export function lastSessionSets(
	sets: DatedLoggedSet[],
	exerciseName: string,
): ProgressionSetLike[] | null {
	const key = normaliseExerciseName(exerciseName);
	if (key === '') return null;

	let bestStartedAt: string | null = null;
	let bestWorkoutId: string | null = null;
	for (const s of sets) {
		if (normaliseExerciseName(s.exercise_name ?? '') !== key) continue;
		if (
			bestStartedAt == null ||
			s.started_at > bestStartedAt ||
			(s.started_at === bestStartedAt && s.workout_id > (bestWorkoutId ?? ''))
		) {
			bestStartedAt = s.started_at;
			bestWorkoutId = s.workout_id;
		}
	}
	if (bestWorkoutId == null) return null;

	return sets
		.filter((s) => s.workout_id === bestWorkoutId && normaliseExerciseName(s.exercise_name ?? '') === key)
		.map((s) => ({ reps: s.reps, weight_kg: s.weight_kg, rpe: s.rpe }));
}
