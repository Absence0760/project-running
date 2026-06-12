/// Gym routine plan ↔ log shaping (gym_programming.md slice P1).
///
/// Dart twin of `apps/web/src/lib/gym/gym_routine.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
///
///   routineFromWorkout — promote a logged session's grouped exercises into a
///     routine draft (title + ordered exercise blocks, each with planned sets
///     carrying the logged reps/weight as targets). The "Save as routine" path.
///   prefillFromRoutine — expand a saved routine's planned targets into
///     editable in-memory exercise blocks for the gym composer. The
///     "Repeat last" / "Start routine" prefill path (prefill-only in P1).
///
/// Binding plan ↔ log is by `normaliseExerciseName` + order, never by FK.
/// `normaliseExerciseName` is imported from gym_prs so the normalisation that
/// stamps `exerciseKey` can never drift from the PR grouping that reads it. P1
/// builds NO expandRoutineSteps / superset handling / progression prescriber —
/// those are P2-P4.
///
/// Pure functions, no Flutter / Supabase deps.
library;

import 'gym_prs.dart' show normaliseExerciseName;

/// A logged gym set, as it arrives from `gym_sets`.
class LoggedSet {
  final String exerciseName;
  final num? reps;
  final num? weightKg;
  final num? rpe;
  const LoggedSet({
    required this.exerciseName,
    this.reps,
    this.weightKg,
    this.rpe,
  });
}

/// One planned set within a routine draft exercise (targets only). A single
/// rep value lives in `targetRepsMin` with `targetRepsMax` null.
class RoutineDraftSet {
  final int setIndex;
  final String setType;
  final num? targetRepsMin;
  final num? targetRepsMax;
  final num? targetWeightKg;
  final num? targetRpe;
  const RoutineDraftSet({
    required this.setIndex,
    required this.setType,
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetRpe,
  });
}

/// One planned exercise within a routine draft.
class RoutineDraftExercise {
  final String exerciseName;
  final String exerciseKey;
  final int position;
  final List<RoutineDraftSet> sets;
  const RoutineDraftExercise({
    required this.exerciseName,
    required this.exerciseKey,
    required this.position,
    required this.sets,
  });
}

/// The in-memory routine shape "Save as routine" hands to the create call.
class RoutineDraft {
  final String title;
  final int exerciseCount;
  final List<RoutineDraftExercise> exercises;
  const RoutineDraft({
    required this.title,
    required this.exerciseCount,
    required this.exercises,
  });
}

/// A persisted routine flattened for prefill.
class PlannedRoutine {
  final String title;
  final List<PlannedExercise> exercises;
  const PlannedRoutine({required this.title, required this.exercises});
}

class PlannedExercise {
  final String exerciseName;
  final int position;
  final List<PlannedSet> sets;
  const PlannedExercise({
    required this.exerciseName,
    required this.position,
    required this.sets,
  });
}

class PlannedSet {
  final int setIndex;
  final num? targetRepsMin;
  final num? targetRepsMax;
  final num? targetWeightKg;
  final num? targetRpe;
  const PlannedSet({
    required this.setIndex,
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetRpe,
  });
}

/// An editable set row for the gym composer (strings for reps/rpe; weight kept
/// as canonical kg so the pure layer stays unit-free).
class PrefillSet {
  final String reps;
  final num? weightKg;
  final String rpe;
  const PrefillSet({required this.reps, this.weightKg, required this.rpe});
}

/// An editable exercise block for the gym composer.
class PrefillExercise {
  final String name;
  final List<PrefillSet> sets;
  const PrefillExercise({required this.name, required this.sets});
}

num? _numericOrNull(Object? v) {
  if (v is num) return v.isFinite ? v : null;
  if (v is String) {
    final n = num.tryParse(v);
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

/// Promote a logged session's sets into a routine draft. Sets are grouped into
/// exercise blocks by *consecutive* equal `exerciseName`. Each logged set
/// becomes a planned `working` set with its reps/weight/RPE as the target.
/// Blank-named sets are dropped. `exerciseKey` is stamped via
/// `normaliseExerciseName` at promotion time. The title defaults to the
/// workout's title, else `fallbackTitle`.
RoutineDraft routineFromWorkout(
  String? workoutTitle,
  List<LoggedSet> sets, {
  String fallbackTitle = 'Routine',
}) {
  final exercises = <_MutableExercise>[];
  for (final s in sets) {
    final name = s.exerciseName.trim();
    if (name == '') continue;
    final reps = _numericOrNull(s.reps);
    final weight = _numericOrNull(s.weightKg);
    final rpe = _numericOrNull(s.rpe);

    final last = exercises.isNotEmpty ? exercises.last : null;
    final _MutableExercise block;
    if (last != null && last.exerciseName == name) {
      block = last;
    } else {
      block = _MutableExercise(
        exerciseName: name,
        exerciseKey: normaliseExerciseName(name),
        position: exercises.length,
      );
      exercises.add(block);
    }

    block.sets.add(RoutineDraftSet(
      setIndex: block.sets.length,
      setType: 'working',
      targetRepsMin: reps,
      targetRepsMax: null,
      targetWeightKg: weight,
      targetRpe: rpe,
    ));
  }

  final trimmedTitle = (workoutTitle ?? '').trim();
  final title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle;
  return RoutineDraft(
    title: title,
    exerciseCount: exercises.length,
    exercises: exercises
        .map((e) => RoutineDraftExercise(
              exerciseName: e.exerciseName,
              exerciseKey: e.exerciseKey,
              position: e.position,
              sets: e.sets,
            ))
        .toList(),
  );
}

class _MutableExercise {
  final String exerciseName;
  final String exerciseKey;
  final int position;
  final List<RoutineDraftSet> sets = [];
  _MutableExercise({
    required this.exerciseName,
    required this.exerciseKey,
    required this.position,
  });
}

/// Expand a saved routine's planned targets into editable composer blocks.
/// Exercises are ordered by `position`, sets by `setIndex` (defensively
/// sorted). Each planned set's target reps (range min, or the single value)
/// prefills the reps field; the target weight prefills the weight field; the
/// target RPE prefills RPE. An empty routine yields a single empty block.
List<PrefillExercise> prefillFromRoutine(PlannedRoutine routine) {
  final ordered = [...routine.exercises]
    ..sort((a, b) => a.position.compareTo(b.position));
  final blocks = <PrefillExercise>[];
  for (final ex in ordered) {
    final sets = [...ex.sets]..sort((a, b) => a.setIndex.compareTo(b.setIndex));
    blocks.add(PrefillExercise(
      name: ex.exerciseName,
      sets: sets.isEmpty
          ? const [PrefillSet(reps: '', weightKg: null, rpe: '')]
          : sets
              .map((s) => PrefillSet(
                    reps: s.targetRepsMin == null ? '' : '${s.targetRepsMin}',
                    weightKg: s.targetWeightKg,
                    rpe: s.targetRpe == null ? '' : '${s.targetRpe}',
                  ))
              .toList(),
    ));
  }
  if (blocks.isEmpty) {
    return const [
      PrefillExercise(name: '', sets: [PrefillSet(reps: '', weightKg: null, rpe: '')]),
    ];
  }
  return blocks;
}
