// Glue for the gym_progression P4 prefill (gym_programming.md). The prescriber
// gym_progression.ts ↔ gym_progression.dart is only called here, never modified.

import { normaliseExerciseName } from './gym_prs';
import {
	workingSets,
	fiveByFiveSessionSucceeded,
	fiveByFiveTargets,
	type FiveByFiveTargets,
	type ProgressionScheme,
	type ProgressionSetLike,
} from './gym_progression';

export interface DatedLoggedSet {
	workout_id: string;
	started_at: string;
	exercise_name: string;
	reps: number | null;
	weight_kg: number | null;
	rpe: number | null;
	/// gym_sets.set_type — carried so the prescriber can exclude warmups.
	set_type?: string | null;
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
		.map((s) => ({ reps: s.reps, weight_kg: s.weight_kg, rpe: s.rpe, set_type: s.set_type }));
}

/// This exercise's logged sessions, newest first — ties broken by workout id,
/// the same ordering lastSessionSets picks its "most recent" by, so a streak
/// walk starts on the session the prescriber is judging.
function sessionsNewestFirst(
	sets: DatedLoggedSet[],
	key: string,
): { id: string; startedAt: string; sets: ProgressionSetLike[] }[] {
	const byWorkout = new Map<string, { id: string; startedAt: string; sets: ProgressionSetLike[] }>();
	for (const s of sets) {
		if (normaliseExerciseName(s.exercise_name ?? '') !== key) continue;
		let entry = byWorkout.get(s.workout_id);
		if (!entry) {
			entry = { id: s.workout_id, startedAt: s.started_at, sets: [] };
			byWorkout.set(s.workout_id, entry);
		}
		entry.sets.push({ reps: s.reps, weight_kg: s.weight_kg, rpe: s.rpe, set_type: s.set_type });
	}
	return [...byWorkout.values()].sort((a, b) => {
		if (a.startedAt !== b.startedAt) return a.startedAt < b.startedAt ? 1 : -1;
		if (a.id === b.id) return 0;
		return a.id < b.id ? 1 : -1;
	});
}

/// How many of the most recent logged sessions of `exerciseName` — walking back
/// from the newest — failed to clear the 5×5 bar. This is the running miss
/// count `nextPrescription` reads as `params.consecutiveMisses`, and nothing
/// else supplies it: `progression_params` is authored once at routine-build
/// time and carries no session history, so an unfed count left the deload
/// branch unreachable and a stalled lifter holding the same weight forever.
///
/// A session with no completed working set for the exercise (only warmups, or
/// rows logged with no reps) is evidence of neither success nor failure, so it
/// is skipped rather than counted — a logging artifact must not be able to
/// prescribe a load reduction. The walk stops at the first session that cleared
/// the bar.
export function consecutiveMissSessions(
	sets: DatedLoggedSet[],
	exerciseName: string,
	targets: FiveByFiveTargets,
): number {
	const key = normaliseExerciseName(exerciseName);
	if (key === '') return 0;

	let misses = 0;
	for (const session of sessionsNewestFirst(sets, key)) {
		if (workingSets(session.sets).length === 0) continue;
		if (fiveByFiveSessionSucceeded(session.sets, targets)) break;
		misses += 1;
	}
	return misses;
}

/// The params a caller hands `nextPrescription`: the routine's authored bag
/// plus the history-derived `consecutiveMisses`. Only `five_by_five` reads that
/// key, so every other scheme passes through untouched. The derived count wins
/// over any authored one — the routine editor never writes it, and history is
/// the only honest source.
export function progressionParamsWithStreak(input: {
	scheme: ProgressionScheme;
	params: Record<string, unknown> | null;
	targetRepsMin: number | null;
	targetRepsMax: number | null;
	history: DatedLoggedSet[];
	exerciseName: string;
}): Record<string, unknown> | null {
	if (input.scheme !== 'five_by_five') return input.params;
	const targets = fiveByFiveTargets({
		targetRepsMin: input.targetRepsMin,
		targetRepsMax: input.targetRepsMax,
		params: input.params,
	});
	return {
		...(input.params ?? {}),
		consecutiveMisses: consecutiveMissSessions(input.history, input.exerciseName, targets),
	};
}
