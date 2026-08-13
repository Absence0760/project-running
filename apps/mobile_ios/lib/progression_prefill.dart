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
import 'gym_progression.dart'
    show
        FiveByFiveTargets,
        ProgressionScheme,
        ProgressionSetLike,
        fiveByFiveSessionSucceeded,
        fiveByFiveTargets,
        workingSets;

/// A logged set carrying its workout + date, the raw history shape the prefill
/// reduces over.
class DatedLoggedSet {
  final String workoutId;
  final String startedAt;
  final String exerciseName;
  final num? reps;
  final num? weightKg;
  final num? rpe;

  /// gym_sets.set_type — carried so the prescriber can exclude warmups.
  final String? setType;
  const DatedLoggedSet({
    required this.workoutId,
    required this.startedAt,
    required this.exerciseName,
    this.reps,
    this.weightKg,
    this.rpe,
    this.setType,
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
          ProgressionSetLike(
              reps: s.reps,
              weightKg: s.weightKg,
              rpe: s.rpe,
              setType: s.setType))
      .toList();
}

class _LoggedSession {
  final String id;
  final String startedAt;
  final List<ProgressionSetLike> sets;
  _LoggedSession(this.id, this.startedAt) : sets = [];
}

/// This exercise's logged sessions, newest first — ties broken by workout id,
/// the same ordering lastSessionSets picks its "most recent" by, so a streak
/// walk starts on the session the prescriber is judging.
List<_LoggedSession> _sessionsNewestFirst(
  List<DatedLoggedSet> sets,
  String key,
) {
  final byWorkout = <String, _LoggedSession>{};
  for (final s in sets) {
    if (normaliseExerciseName(s.exerciseName) != key) continue;
    final entry = byWorkout.putIfAbsent(
        s.workoutId, () => _LoggedSession(s.workoutId, s.startedAt));
    entry.sets.add(ProgressionSetLike(
        reps: s.reps, weightKg: s.weightKg, rpe: s.rpe, setType: s.setType));
  }
  final out = byWorkout.values.toList();
  out.sort((a, b) {
    if (a.startedAt != b.startedAt) {
      return b.startedAt.compareTo(a.startedAt);
    }
    return b.id.compareTo(a.id);
  });
  return out;
}

/// How many of the most recent logged sessions of [exerciseName] — walking back
/// from the newest — failed to clear the 5×5 bar. This is the running miss
/// count nextPrescription reads as `params['consecutiveMisses']`, and nothing
/// else supplies it: progression_params is authored once at routine-build time
/// and carries no session history, so an unfed count left the deload branch
/// unreachable and a stalled lifter holding the same weight forever.
///
/// A session with no completed working set for the exercise (only warmups, or
/// rows logged with no reps) is evidence of neither success nor failure, so it
/// is skipped rather than counted — a logging artifact must not be able to
/// prescribe a load reduction. The walk stops at the first session that cleared
/// the bar.
int consecutiveMissSessions(
  List<DatedLoggedSet> sets,
  String exerciseName,
  FiveByFiveTargets targets,
) {
  final key = normaliseExerciseName(exerciseName);
  if (key == '') return 0;

  var misses = 0;
  for (final session in _sessionsNewestFirst(sets, key)) {
    if (workingSets(session.sets).isEmpty) continue;
    if (fiveByFiveSessionSucceeded(session.sets, targets)) break;
    misses += 1;
  }
  return misses;
}

/// The params a caller hands nextPrescription: the routine's authored bag plus
/// the history-derived `consecutiveMisses`. Only fiveByFive reads that key, so
/// every other scheme passes through untouched. The derived count wins over any
/// authored one — the routine editor never writes it, and history is the only
/// honest source.
Map<String, Object?>? progressionParamsWithStreak({
  required ProgressionScheme scheme,
  required Map<String, Object?>? params,
  required List<DatedLoggedSet> history,
  required String exerciseName,
  num? targetRepsMin,
  num? targetRepsMax,
}) {
  if (scheme != ProgressionScheme.fiveByFive) return params;
  final targets = fiveByFiveTargets(
    targetRepsMin: targetRepsMin,
    targetRepsMax: targetRepsMax,
    params: params,
  );
  return {
    ...(params ?? const {}),
    'consecutiveMisses':
        consecutiveMissSessions(history, exerciseName, targets),
  };
}
