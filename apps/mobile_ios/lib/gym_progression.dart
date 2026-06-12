/// Gym progressive-overload prescriber (gym_programming.md P4).
///
/// Dart twin of `apps/web/src/lib/gym/gym_progression.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
///
/// `nextPrescription` reads the last session's sets + the per-exercise scheme
/// and returns the next target (weight in canonical kg + rep range + a reason
/// the UI explains). Weights stay canonical kg; display formatting is the
/// caller's job.
///
/// Pure functions, no Flutter / Supabase deps.
library;

enum ProgressionScheme {
  none,
  linear,
  doubleProgression,
  fiveByFive,
  percentCycle,
  rpeAutoreg,
}

enum ProgressionReason { increaseWeight, increaseReps, hold, deload, none }

class ProgressionSetLike {
  final num? reps;
  final num? weightKg;
  final num? rpe;
  const ProgressionSetLike({this.reps, this.weightKg, this.rpe});
}

class ProgressionInput {
  final ProgressionScheme scheme;
  final List<ProgressionSetLike> lastSets;
  final num? targetRepsMin;
  final num? targetRepsMax;
  final Map<String, Object?>? params;
  const ProgressionInput({
    required this.scheme,
    this.lastSets = const [],
    this.targetRepsMin,
    this.targetRepsMax,
    this.params,
  });
}

class ProgressionSuggestion {
  final double? suggestedWeightKg;
  final double? suggestedRepsMin;
  final double? suggestedRepsMax;
  final ProgressionReason reason;
  const ProgressionSuggestion({
    this.suggestedWeightKg,
    this.suggestedRepsMin,
    this.suggestedRepsMax,
    required this.reason,
  });
}

double _round1(double n) => (n * 10).round() / 10;

double? _numericOrNull(Object? v) {
  if (v is num) {
    final d = v.toDouble();
    return d.isFinite ? d : null;
  }
  if (v is String) {
    final n = double.tryParse(v);
    return (n != null && n.isFinite) ? n : null;
  }
  return null;
}

double _positiveOr(Object? v, double fallback) {
  final n = _numericOrNull(v);
  return (n != null && n > 0) ? n : fallback;
}

/// The heaviest working weight across the session — the anchor a load increment
/// is added to. Null when no set carried a positive weight (bodyweight work).
double? _topWeight(List<ProgressionSetLike> sets) {
  double? top;
  for (final s in sets) {
    final w = _numericOrNull(s.weightKg);
    if (w != null && w > 0 && (top == null || w > top)) top = w;
  }
  return top;
}

/// A weight increment can never drive the prescription below zero — guards the
/// degenerate case where params hand us a negative step.
double _safeAdd(double weightKg, double deltaKg) {
  final next = weightKg + deltaKg;
  return next > 0 ? _round1(next) : _round1(weightKg);
}

ProgressionSuggestion nextPrescription(ProgressionInput input) {
  const none = ProgressionSuggestion(reason: ProgressionReason.none);
  if (input.scheme == ProgressionScheme.none) return none;

  final params = input.params ?? const {};
  final sets = input.lastSets;
  final completed = sets.where((s) {
    final r = _numericOrNull(s.reps);
    return r != null && r > 0;
  }).toList();

  final repsMin = _numericOrNull(input.targetRepsMin);
  final repsMax = _numericOrNull(input.targetRepsMax);
  final weight = _topWeight(sets);
  final step = _positiveOr(params['incrementKg'], 2.5);

  switch (input.scheme) {
    case ProgressionScheme.none:
      return none;

    case ProgressionScheme.linear:
      {
        final topReps = repsMax ?? repsMin;
        if (completed.isEmpty || topReps == null) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: ProgressionReason.hold,
          );
        }
        final allHit =
            completed.every((s) => (_numericOrNull(s.reps) ?? 0) >= topReps);
        if (allHit) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight != null ? _safeAdd(weight, step) : null,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: weight != null
                ? ProgressionReason.increaseWeight
                : ProgressionReason.increaseReps,
          );
        }
        return ProgressionSuggestion(
          suggestedWeightKg: weight,
          suggestedRepsMin: repsMin,
          suggestedRepsMax: repsMax,
          reason: ProgressionReason.hold,
        );
      }

    case ProgressionScheme.doubleProgression:
      {
        if (completed.isEmpty || repsMax == null) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: ProgressionReason.hold,
          );
        }
        final atTop =
            completed.every((s) => (_numericOrNull(s.reps) ?? 0) >= repsMax);
        if (atTop) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight != null ? _safeAdd(weight, step) : null,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMin,
            reason: weight != null
                ? ProgressionReason.increaseWeight
                : ProgressionReason.increaseReps,
          );
        }
        return ProgressionSuggestion(
          suggestedWeightKg: weight,
          suggestedRepsMin: repsMin,
          suggestedRepsMax: repsMax,
          reason: ProgressionReason.increaseReps,
        );
      }

    case ProgressionScheme.fiveByFive:
      {
        final targetSets = _positiveOr(params['targetSets'], 5);
        final targetReps =
            repsMax ?? repsMin ?? _positiveOr(params['targetReps'], 5);
        final maxMisses = _positiveOr(params['maxConsecutiveMisses'], 3);
        final misses = _positiveOr(params['consecutiveMisses'], 0);
        final success = completed.length >= targetSets &&
            completed.every((s) => (_numericOrNull(s.reps) ?? 0) >= targetReps);

        if (success) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight != null ? _safeAdd(weight, step) : null,
            suggestedRepsMin: targetReps,
            suggestedRepsMax: targetReps,
            reason: weight != null
                ? ProgressionReason.increaseWeight
                : ProgressionReason.increaseReps,
          );
        }
        if (misses >= maxMisses) {
          final deloaded = weight != null
              ? _round1(weight * _positiveOr(params['deloadFactor'], 0.9))
              : null;
          return ProgressionSuggestion(
            suggestedWeightKg: deloaded,
            suggestedRepsMin: targetReps,
            suggestedRepsMax: targetReps,
            reason: ProgressionReason.deload,
          );
        }
        return ProgressionSuggestion(
          suggestedWeightKg: weight,
          suggestedRepsMin: targetReps,
          suggestedRepsMax: targetReps,
          reason: ProgressionReason.hold,
        );
      }

    case ProgressionScheme.percentCycle:
      {
        final percent = _numericOrNull(params['percent']);
        final oneRm = _numericOrNull(params['oneRmKg']);
        if (percent == null || oneRm == null || !(percent > 0) || !(oneRm > 0)) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: ProgressionReason.hold,
          );
        }
        return ProgressionSuggestion(
          suggestedWeightKg: _round1(percent * oneRm),
          suggestedRepsMin: repsMin,
          suggestedRepsMax: repsMax,
          reason: ProgressionReason.increaseWeight,
        );
      }

    case ProgressionScheme.rpeAutoreg:
      {
        final targetRpe = _numericOrNull(params['targetRpe']);
        double? achieved;
        for (final s in completed) {
          final r = _numericOrNull(s.rpe);
          if (r == null) continue;
          achieved = achieved == null ? r : (r > achieved ? r : achieved);
        }
        if (targetRpe == null || achieved == null) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: ProgressionReason.hold,
          );
        }
        if (achieved < targetRpe) {
          return ProgressionSuggestion(
            suggestedWeightKg: weight != null ? _safeAdd(weight, step) : null,
            suggestedRepsMin: repsMin,
            suggestedRepsMax: repsMax,
            reason: weight != null
                ? ProgressionReason.increaseWeight
                : ProgressionReason.increaseReps,
          );
        }
        return ProgressionSuggestion(
          suggestedWeightKg: weight,
          suggestedRepsMin: repsMin,
          suggestedRepsMax: repsMax,
          reason: ProgressionReason.hold,
        );
      }
  }
}
