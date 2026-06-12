/// Glue between the logged-set history and the gym_progression prescriber
/// (gym_programming.md P4).
///
/// Dart twin of `apps/web/src/lib/gym/progression_prefill.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Pure — no DB, no Flutter. It picks the most recent logged session of an
/// exercise and reduces it to the [ProgressionSetLike] list nextPrescription
/// consumes. The prescriber itself (gym_progression.dart) is NOT touched here —
/// we only call it.
library;

import 'gym_prs.dart' show normaliseExerciseName;
import 'gym_progression.dart' show ProgressionSetLike;

/// A logged set carrying its workout + date, the raw history shape the prefill
/// reduces over.
class DatedLoggedSet {
  final String workoutId;
  final String startedAt;
  final String exerciseName;
  final num? reps;
  final num? weightKg;
  final num? rpe;
  const DatedLoggedSet({
    required this.workoutId,
    required this.startedAt,
    required this.exerciseName,
    this.reps,
    this.weightKg,
    this.rpe,
  });
}

/// The raw sets of the most recent logged session of [exerciseName], matched by
/// normalised key, in their logged order. Null when the exercise has never been
/// logged (the prescriber treats a null last session as a first session).
/// "Most recent" is by `startedAt`, ties broken by workout id so the choice is
/// deterministic — mirroring exercise_history's ordering.
List<ProgressionSetLike>? lastSessionSets(
  List<DatedLoggedSet> sets,
  String exerciseName,
) {
  final key = normaliseExerciseName(exerciseName);
  if (key == '') return null;

  String? bestStartedAt;
  String? bestWorkoutId;
  for (final s in sets) {
    if (normaliseExerciseName(s.exerciseName) != key) continue;
    if (bestStartedAt == null ||
        s.startedAt.compareTo(bestStartedAt) > 0 ||
        (s.startedAt == bestStartedAt &&
            s.workoutId.compareTo(bestWorkoutId ?? '') > 0)) {
      bestStartedAt = s.startedAt;
      bestWorkoutId = s.workoutId;
    }
  }
  if (bestWorkoutId == null) return null;

  return sets
      .where((s) =>
          s.workoutId == bestWorkoutId &&
          normaliseExerciseName(s.exerciseName) == key)
      .map((s) =>
          ProgressionSetLike(reps: s.reps, weightKg: s.weightKg, rpe: s.rpe))
      .toList();
}
