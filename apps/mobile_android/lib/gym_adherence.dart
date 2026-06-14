/// Gym routine planned-vs-actual adherence (gym_programming.md — the
/// planned-vs-actual signal that sits above the P1 repeat-rate gate).
///
/// Dart twin of `apps/web/src/lib/gym/gym_adherence.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
///
/// Reduces a routine's planned set targets against the sets a runner actually
/// logged into a per-set verdict plus a session roll-up. Matching is by
/// (exerciseKey, setIndex) — a stable identity stamped at plan time — never by
/// name spelling, so a re-typed exercise label never desyncs the comparison.
/// Weights stay canonical kg; the caller formats through the weight pref.
///
/// The session `verdict` mirrors the run-side WorkoutAdherence 80% threshold:
/// completed at >= 80% of planned sets hit, abandoned at zero, partial between.
///
/// Pure functions, no Flutter / Supabase deps.
library;

class PlannedSetRef {
  final String exerciseKey;
  final int setIndex;

  /// gym_routine_sets.set_type — raw string (matches the DB CHECK union). Drives
  /// warmup exclusion + amrap/failure scoring. Null is treated as 'working'.
  final String? setType;
  final num? targetRepsMin;
  final num? targetRepsMax;
  final num? targetWeightKg;
  final num? targetDurationS;
  const PlannedSetRef({
    required this.exerciseKey,
    required this.setIndex,
    this.setType,
    this.targetRepsMin,
    this.targetRepsMax,
    this.targetWeightKg,
    this.targetDurationS,
  });
}

class ActualSetRef {
  final String exerciseKey;
  final int setIndex;
  final num? reps;
  final num? weightKg;
  final num? durationS;
  const ActualSetRef({
    required this.exerciseKey,
    required this.setIndex,
    this.reps,
    this.weightKg,
    this.durationS,
  });
}

enum SetAdherenceStatus { hit, partial, missed, extra }

class SetAdherence {
  final String exerciseKey;
  final int setIndex;
  final SetAdherenceStatus status;

  /// actual − target. Reps uses targetRepsMin as the target; null when either
  /// side is missing (no actual logged, or no rep target to compare).
  final num? repsDelta;

  /// actual − target, canonical kg. Null when either side is missing.
  final num? weightDeltaKg;
  const SetAdherence({
    required this.exerciseKey,
    required this.setIndex,
    required this.status,
    required this.repsDelta,
    required this.weightDeltaKg,
  });
}

enum RoutineVerdict { completed, partial, abandoned }

class RoutineAdherence {
  final List<SetAdherence> sets;
  final int plannedCount;
  final int completedCount;

  /// completedCount / plannedCount, 0 when nothing was planned.
  final double adherencePct;
  final RoutineVerdict verdict;
  const RoutineAdherence({
    required this.sets,
    required this.plannedCount,
    required this.completedCount,
    required this.adherencePct,
    required this.verdict,
  });
}

/// Fraction of planned sets that must be hit for the session to count as
/// completed — mirrors the run WorkoutAdherence threshold.
const double gymAdherenceCompletedThreshold = 0.8;

/// Per-axis hit floor — an actual reaches a target when it is within this
/// fraction of it (gym_programming.md § Adherence). Same 80% the run side uses.
const double _axisHitFraction = 0.8;

String _refKey(String exerciseKey, int setIndex) => '$exerciseKey $setIndex';

/// Reduce planned set targets against logged sets into per-set verdicts and a
/// session roll-up. A planned set is `hit` when the actual reps reach 80% of the
/// rep floor AND (no weight target, or the actual weight reaches 80% of it); a
/// duration target is hit at 80% of the target. A set with reps logged but below
/// the floor is `partial`; one whose weight fell short, or that was never logged,
/// is `missed`. `amrap`/`failure` sets count as `hit` whenever any reps (or
/// duration) were logged. `warmup` sets are excluded from the denominator
/// entirely (skipping a warmup never marks a session partial). A logged set with
/// no matching plan entry is `extra` and is excluded from `plannedCount`.
RoutineAdherence computeRoutineAdherence(
  List<PlannedSetRef> planned,
  List<ActualSetRef> actual,
) {
  final actualByKey = <String, ActualSetRef>{};
  for (final a in actual) {
    actualByKey[_refKey(a.exerciseKey, a.setIndex)] = a;
  }
  final plannedKeys = <String>{};
  final sets = <SetAdherence>[];
  var completedCount = 0;
  var plannedCount = 0;

  for (final p in planned) {
    final key = _refKey(p.exerciseKey, p.setIndex);
    plannedKeys.add(key);
    // Warmups are matched (so their logged set isn't flagged extra) but never
    // counted toward the verdict.
    if (p.setType == 'warmup') continue;
    plannedCount += 1;
    final a = actualByKey[key];

    final repsDelta = a == null || a.reps == null || p.targetRepsMin == null
        ? null
        : a.reps! - p.targetRepsMin!;
    final weightDeltaKg =
        a == null || a.weightKg == null || p.targetWeightKg == null
        ? null
        : a.weightKg! - p.targetWeightKg!;

    SetAdherenceStatus status;
    if (a == null) {
      status = SetAdherenceStatus.missed;
    } else if (p.setType == 'amrap' || p.setType == 'failure') {
      status = (a.reps != null && a.reps! > 0) ||
              (a.durationS != null && a.durationS! > 0)
          ? SetAdherenceStatus.hit
          : SetAdherenceStatus.missed;
    } else if (p.targetWeightKg != null &&
        p.targetWeightKg! > 0 &&
        (a.weightKg == null ||
            a.weightKg! < p.targetWeightKg! * _axisHitFraction)) {
      status = SetAdherenceStatus.missed;
    } else if (p.targetRepsMin != null) {
      status =
          a.reps != null && a.reps! >= p.targetRepsMin! * _axisHitFraction
          ? SetAdherenceStatus.hit
          : SetAdherenceStatus.partial;
    } else if (p.targetDurationS != null) {
      status =
          a.durationS != null &&
              a.durationS! >= p.targetDurationS! * _axisHitFraction
          ? SetAdherenceStatus.hit
          : SetAdherenceStatus.partial;
    } else {
      status = SetAdherenceStatus.hit;
    }

    if (status == SetAdherenceStatus.hit) completedCount += 1;
    sets.add(
      SetAdherence(
        exerciseKey: p.exerciseKey,
        setIndex: p.setIndex,
        status: status,
        repsDelta: repsDelta,
        weightDeltaKg: weightDeltaKg,
      ),
    );
  }

  for (final a in actual) {
    final key = _refKey(a.exerciseKey, a.setIndex);
    if (plannedKeys.contains(key)) continue;
    sets.add(
      SetAdherence(
        exerciseKey: a.exerciseKey,
        setIndex: a.setIndex,
        status: SetAdherenceStatus.extra,
        repsDelta: null,
        weightDeltaKg: null,
      ),
    );
  }

  final adherencePct = plannedCount == 0 ? 0.0 : completedCount / plannedCount;
  RoutineVerdict verdict;
  if (completedCount == 0) {
    verdict = RoutineVerdict.abandoned;
  } else if (adherencePct >= gymAdherenceCompletedThreshold) {
    verdict = RoutineVerdict.completed;
  } else {
    verdict = RoutineVerdict.partial;
  }

  return RoutineAdherence(
    sets: sets,
    plannedCount: plannedCount,
    completedCount: completedCount,
    adherencePct: adherencePct,
    verdict: verdict,
  );
}
