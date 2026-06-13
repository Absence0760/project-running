/// Gym personal-record computation (Phase 4 multi-modal, decisions §63;
/// spec: docs/features/multi_modal.md § Gym).
///
/// Dart twin of `apps/web/src/lib/gym/gym_prs.ts` — keep the algorithm,
/// edge cases, outputs, and test counts in lockstep.
///
/// Three PR metrics per (user, exercise) — "heaviest set / most volume /
/// best rep-PR":
///   weight  — heaviest single set (max weightKg).
///   volume  — biggest single-set volume (reps × weightKg).
///   e1rm    — best estimated one-rep-max (Epley), the meaningful "rep PR":
///             a 5×100 kg outranks a 1×105 kg in real strength.
/// All three are single-set metrics so they're deterministic and a typo in
/// one set can't poison a session aggregate.
///
/// Pure functions, no Flutter / Supabase deps.
library;

class GymSetLike {
  final String exerciseName;
  final num? reps;
  final num? weightKg;
  const GymSetLike({required this.exerciseName, this.reps, this.weightKg});
}

enum PrKind { weight, volume, e1rm }

class ExercisePr {
  /// Display spelling — the original exercise name of the first set (in
  /// input order) that maps to this normalised key.
  final String exerciseName;
  final double? heaviestWeightKg;
  final num? heaviestWeightReps;
  final double? bestVolumeKg;
  final double? bestEst1RmKg;
  const ExercisePr({
    required this.exerciseName,
    this.heaviestWeightKg,
    this.heaviestWeightReps,
    this.bestVolumeKg,
    this.bestEst1RmKg,
  });

  ExercisePr _copyWith({
    double? heaviestWeightKg,
    num? heaviestWeightReps,
    double? bestVolumeKg,
    double? bestEst1RmKg,
    bool clearReps = false,
  }) =>
      ExercisePr(
        exerciseName: exerciseName,
        heaviestWeightKg: heaviestWeightKg ?? this.heaviestWeightKg,
        heaviestWeightReps:
            clearReps ? heaviestWeightReps : (heaviestWeightReps ?? this.heaviestWeightReps),
        bestVolumeKg: bestVolumeKg ?? this.bestVolumeKg,
        bestEst1RmKg: bestEst1RmKg ?? this.bestEst1RmKg,
      );
}

/// Reps beyond this are clamped for the e1rm estimate — Epley loses accuracy
/// past ~10-12 reps, and an endurance set would otherwise manufacture an
/// absurd 1RM and a phantom PR. The set still counts; only the rep multiplier
/// saturates.
const int kE1rmMaxReps = 12;

/// Estimated one-rep-max via Epley `w · (1 + reps/30)`, with a true single
/// (reps == 1) reported as the lifted weight itself. Returns 0 for
/// non-positive inputs.
double estimatedOneRepMax(double weightKg, int reps) {
  if (!(weightKg > 0) || !(reps > 0)) return 0;
  if (reps == 1) return weightKg;
  final r = reps < kE1rmMaxReps ? reps : kE1rmMaxReps;
  return weightKg * (1 + r / 30);
}

/// Normalise a free-text exercise name for grouping: trimmed, lower-cased,
/// internal whitespace collapsed.
String normaliseExerciseName(String name) =>
    name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

double _round1(double n) => (n * 10).round() / 10;

/// Compute the PR table across a flat set list, keyed by normalised exercise
/// name. Sets with a blank exercise name are ignored. Insertion order of the
/// returned map follows first appearance of each exercise.
/// Fold one set into a running PR map (max of each metric). The shared
/// per-set body of [computeExercisePrs] + [RunningPrTracker] so the two can't
/// diverge. A blank exercise name is ignored.
void _accumulateSet(Map<String, ExercisePr> out, GymSetLike s) {
  final key = normaliseExerciseName(s.exerciseName);
  if (key == '') return;
  final weight = _numericOrNull(s.weightKg);
  final reps = _numericOrNull(s.reps);

  var pr = out[key] ?? ExercisePr(exerciseName: s.exerciseName);
  out[key] = pr;

  if (weight != null && weight > 0) {
    if (pr.heaviestWeightKg == null ||
        weight > pr.heaviestWeightKg! ||
        (weight == pr.heaviestWeightKg && (reps ?? 0) > (pr.heaviestWeightReps ?? 0))) {
      pr = pr._copyWith(
        heaviestWeightKg: weight,
        heaviestWeightReps: reps,
        clearReps: true,
      );
      out[key] = pr;
    }
    if (reps != null && reps > 0) {
      final volume = weight * reps;
      if (pr.bestVolumeKg == null || volume > pr.bestVolumeKg!) {
        pr = pr._copyWith(bestVolumeKg: _round1(volume.toDouble()));
        out[key] = pr;
      }
      final e1rm = estimatedOneRepMax(weight, reps.toInt());
      if (pr.bestEst1RmKg == null || e1rm > pr.bestEst1RmKg!) {
        pr = pr._copyWith(bestEst1RmKg: _round1(e1rm));
        out[key] = pr;
      }
    }
  }
}

Map<String, ExercisePr> computeExercisePrs(List<GymSetLike> sets) {
  final out = <String, ExercisePr>{};
  for (final s in sets) {
    _accumulateSet(out, s);
  }
  return out;
}

class WorkoutPrResult {
  final String exerciseName;
  final List<PrKind> kinds;
  const WorkoutPrResult({required this.exerciseName, required this.kinds});
}

/// Which PRs a workout newly set, given every set logged BEFORE it. A kind is
/// reported only when this workout strictly beats the prior best for that
/// exercise+metric (or there was no prior set at all). `priorSets` must
/// exclude the workout's own sets.
List<WorkoutPrResult> workoutPrs(
  List<GymSetLike> priorSets,
  List<GymSetLike> workoutSets,
) {
  final prior = computeExercisePrs(priorSets);
  final current = computeExercisePrs(workoutSets);
  final results = <WorkoutPrResult>[];

  current.forEach((key, cur) {
    final before = prior[key];
    final kinds = <PrKind>[];
    if (_beats(cur.heaviestWeightKg, before?.heaviestWeightKg)) kinds.add(PrKind.weight);
    if (_beats(cur.bestVolumeKg, before?.bestVolumeKg)) kinds.add(PrKind.volume);
    if (_beats(cur.bestEst1RmKg, before?.bestEst1RmKg)) kinds.add(PrKind.e1rm);
    if (kinds.isNotEmpty) {
      results.add(WorkoutPrResult(exerciseName: cur.exerciseName, kinds: kinds));
    }
  });
  return results;
}

/// Single-pass PR detector for the chronological "did THIS workout set a PR vs
/// everything before it?" question asked once per workout when walking
/// oldest→newest. Maintains ONE running PR map and folds each workout's sets in
/// after judging it — O(total sets), versus calling [workoutPrs] in a loop with
/// a growing priorSets list (which re-derives the full prior map every workout:
/// O(workouts × prior sets)). Results match that loop because the metric
/// updates are order-independent maxes.
class RunningPrTracker {
  final Map<String, ExercisePr> _running = <String, ExercisePr>{};

  /// Judge [workoutSets] against all sets folded in so far, then fold them in.
  /// Same semantics as [workoutPrs]`(everythingBefore, workoutSets)`.
  List<WorkoutPrResult> judge(List<GymSetLike> workoutSets) {
    final current = computeExercisePrs(workoutSets);
    final results = <WorkoutPrResult>[];
    current.forEach((key, cur) {
      final before = _running[key];
      final kinds = <PrKind>[];
      if (_beats(cur.heaviestWeightKg, before?.heaviestWeightKg)) kinds.add(PrKind.weight);
      if (_beats(cur.bestVolumeKg, before?.bestVolumeKg)) kinds.add(PrKind.volume);
      if (_beats(cur.bestEst1RmKg, before?.bestEst1RmKg)) kinds.add(PrKind.e1rm);
      if (kinds.isNotEmpty) {
        results.add(WorkoutPrResult(exerciseName: cur.exerciseName, kinds: kinds));
      }
    });
    for (final s in workoutSets) {
      _accumulateSet(_running, s);
    }
    return results;
  }
}

bool _beats(double? current, double? prior) {
  if (current == null) return false;
  if (prior == null) return true;
  return current > prior;
}

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
