/// Per-exercise personal-record roll-up (Phase 4 multi-modal, decisions §63;
/// spec: docs/features/multi_modal.md § Gym). Drives the gym records surface.
///
/// Mobile-only: the web records surface moved to the server-side
/// `gym_exercise_records()` RPC (all-time bests can't be served by a windowed
/// client read), so there is no web twin to keep in lockstep. Mobile still
/// computes records client-side here until it too moves to the RPC.
///
/// The PR engine (gym_prs.dart) already computes each exercise's bests, but
/// only transiently — to decide whether a workout earned a badge. There was no
/// place to answer "what's my best bench press, and when did I last hit it?".
/// This helper joins gym_prs' per-exercise bests with each exercise's
/// last-performed date + distinct-session count so a lifter can scan their
/// current strength.
///
/// Pure functions, no Flutter / Supabase deps. Reuses [computeExercisePrs] so
/// the PR numbers shown here can never drift from the badge engine.
library;

import 'gym_prs.dart';

/// A logged set carrying the columns the records roll-up needs: the PR metrics
/// (via [GymSetLike]) plus the workout it belongs to and when that workout
/// happened.
class DatedGymSet extends GymSetLike {
  final String workoutId;
  final String startedAt;
  const DatedGymSet({
    required super.exerciseName,
    super.reps,
    super.weightKg,
    required this.workoutId,
    required this.startedAt,
  });
}

class ExerciseRecord {
  /// Display spelling — inherited from the PR engine (first set, in input
  /// order, that maps to the normalised key) so it stays deterministic and
  /// consistent with the per-workout badges.
  final String exerciseName;

  /// Heaviest single-set weight, kg. Always non-null for a record (a record
  /// only exists once at least one weighted set has been logged).
  final double heaviestWeightKg;

  /// Reps performed at the heaviest weight, for "100 kg × 5" display.
  final num? heaviestWeightReps;

  /// Best single-set volume (reps × weight_kg), kg. Null if no set had reps.
  final double? bestVolumeKg;

  /// Best estimated one-rep-max (Epley), kg. Null if no set had reps.
  final double? bestEst1RmKg;

  /// started_at of the most recent workout that included this exercise (ISO).
  final String lastPerformedAt;

  /// Distinct workouts that included this exercise.
  final int sessionCount;

  const ExerciseRecord({
    required this.exerciseName,
    required this.heaviestWeightKg,
    required this.heaviestWeightReps,
    required this.bestVolumeKg,
    required this.bestEst1RmKg,
    required this.lastPerformedAt,
    required this.sessionCount,
  });
}

/// Build the records table from a flat, dated set list. One row per exercise
/// that has at least one weighted set (bodyweight-only exercises are excluded,
/// exactly as they're excluded from the PR engine's weight/volume/e1rm
/// metrics). Sorted most-recently-performed first, ties broken alphabetically
/// by display name so the order is deterministic.
List<ExerciseRecord> exerciseRecords(List<DatedGymSet> sets) {
  final prs = computeExercisePrs(sets);

  final lastPerformed = <String, String>{};
  final workouts = <String, Set<String>>{};
  for (final s in sets) {
    final key = normaliseExerciseName(s.exerciseName);
    if (key == '') continue;
    final ws = workouts.putIfAbsent(key, () => <String>{});
    if (s.workoutId.isNotEmpty) ws.add(s.workoutId);
    // ISO timestamps compare chronologically as strings.
    final prev = lastPerformed[key] ?? '';
    if (s.startedAt.isNotEmpty && s.startedAt.compareTo(prev) > 0) {
      lastPerformed[key] = s.startedAt;
    }
  }

  final records = <ExerciseRecord>[];
  prs.forEach((key, pr) {
    if (pr.heaviestWeightKg == null) return; // bodyweight-only — no record
    records.add(_toRecord(
      pr,
      lastPerformed[key] ?? '',
      workouts[key]?.length ?? 0,
    ));
  });

  records.sort((x, y) {
    if (x.lastPerformedAt != y.lastPerformedAt) {
      return y.lastPerformedAt.compareTo(x.lastPerformedAt);
    }
    return x.exerciseName.compareTo(y.exerciseName);
  });
  return records;
}

ExerciseRecord _toRecord(ExercisePr pr, String lastPerformedAt, int sessionCount) =>
    ExerciseRecord(
      exerciseName: pr.exerciseName,
      heaviestWeightKg: pr.heaviestWeightKg!,
      heaviestWeightReps: pr.heaviestWeightReps,
      bestVolumeKg: pr.bestVolumeKg,
      bestEst1RmKg: pr.bestEst1RmKg,
      lastPerformedAt: lastPerformedAt,
      sessionCount: sessionCount,
    );
