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

import 'exercise_fold_table.dart';

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
double estimatedOneRepMax(double weightKg, num reps) {
  if (!(weightKg > 0) || !(reps > 0)) return 0;
  if (reps == 1) return weightKg;
  final r = reps < kE1rmMaxReps ? reps : kE1rmMaxReps;
  return weightKg * (1 + r / 30);
}

/// The whitespace class every rail folds, spelled out by code point rather
/// than left to a runtime's default.
///
/// This value is PERSISTED as `gym_sets.exercise_key` (server-stamped),
/// `gym_routine_exercises.exercise_key` and `exercises.name_key`, so all three
/// rails must produce an identical key or one exercise buckets as two: the
/// local PR tracker says PR where `gym_workout_summaries.is_pr` says no, and
/// `gym_exercise_set_history(p_name)` returns an empty history for a lift that
/// has one.
///
/// Naming the set is what removes the dependency on each runtime's idea of
/// whitespace, and the three ideas genuinely differ. Dart's `String.trim()`
/// strips every Unicode `White_Space` code point including U+0085 (NEL) where
/// JS's `trim()` and `\s` do not. Postgres is worse than either: `btrim(text)`
/// with no second argument strips U+0020 ALONE, and `\s` is `[[:space:]]`,
/// whose membership past ASCII is decided by the database's locale provider —
/// measured on PG 17.6, the ICU provider folds U+00A0 / U+2007 / U+202F /
/// U+001C-U+001F and the libc `en_US.utf8` provider folds none of them. A
/// persisted key cannot be a function of the server's collation.
///
/// The class is Unicode `White_Space` plus U+FEFF, which is not White_Space but
/// is invisible and must not split a bucket. U+001C-U+001F are deliberately
/// absent: they are control characters, not spaces, and Postgres folding them
/// under one provider was a divergence to close, not a rule to copy. The SQL
/// mirror is `public.normalise_exercise_name` (migration 20270623000001);
/// `scripts/check_shared_constants.mjs` compares all three. decisions § 790.
final RegExp kExerciseWhitespace = RegExp(
  '[\\u0009-\\u000d\\u0020\\u0085\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]+',
);

/// The one case fold applied around the table, spelled out by code point for
/// the same reason [kExerciseWhitespace] is.
///
/// U+03C2 folds to U+03C3 AFTER the table. Final sigma is a CONTEXT, not a
/// case: ICU and JS produce it when lowercasing a word-final capital sigma and
/// this rail and libc never do, and no per-code-point table can express either
/// behaviour. The table always answers U+03C3, so this collapses a lifter's own
/// typed final sigma onto it and an all-caps Greek spelling meets its
/// lower-case one on all three rails.
const List<String> kExerciseCasePostFold = ['\u03c2', '\u03c3'];

/// Normalise a free-text exercise name for grouping: trimmed, lower-cased,
/// internal whitespace collapsed.
String normaliseExerciseName(String name) =>
    _foldExerciseCase(name.replaceAll(kExerciseWhitespace, ' ').trim())
        .replaceAll(kExerciseCasePostFold[0], kExerciseCasePostFold[1])
        .replaceAll(RegExp(r' +'), ' ');

/// Lower-case through the FROZEN table rather than through [String.toLowerCase].
///
/// The runtime's own table is the last thing about this key that still moved
/// with the runtime, and this rail carried the worst of it: Dart's
/// `toLowerCase()` is Unicode SIMPLE case mapping from an older revision, and
/// measured over every assignable code point it left 465 code points alone that
/// web folded and 410 that the server folded. The key is PERSISTED, so each of
/// those was a name this rail could not write to
/// `gym_routine_exercises.exercise_key` or `exercises.name_key` without a 23514
/// from a CHECK the other two rails agreed on (decisions § 1175). The table is
/// generated by `scripts/gen_exercise_fold_table.mjs`; the mirrors are
/// `apps/web/src/lib/gym/exercise_fold_table.ts` and the `translate()` inside
/// `public.exercise_fold_case`.
///
/// Walking [String.runes] is load-bearing: 307 of the 1,488 entries are outside
/// the BMP, and a code-unit walk would fold each half of a surrogate pair
/// separately and match nothing.
String _foldExerciseCase(String value) {
  final out = StringBuffer();
  for (final rune in value.runes) {
    out.writeCharCode(_exerciseFold[rune] ?? rune);
  }
  return out.toString();
}

final Map<int, int> _exerciseFold = <int, int>{
  for (var i = 0; i < kExerciseFoldKeys.length; i++)
    kExerciseFoldKeys[i]: kExerciseFoldValues[i],
};

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
      final e1rm = estimatedOneRepMax(weight, reps);
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

/// How many distinct exercises a flat set list covers, bucketed by the same
/// canonical key the PR engine groups on. Blank names contribute nothing, as
/// they do to the PR map.
///
/// The header stat, the dashboard lift card and the mobile list row each
/// counted this with the runtime's own `trim().toLowerCase()`, which splits an
/// internal whitespace run and every code point the frozen fold collapses —
/// so one lift logged under two spellings was reported as two exercises while
/// every keyed surface treated it as one (§ 1248).
int distinctExerciseCount(Iterable<String> exerciseNames) {
  final keys = <String>{};
  for (final n in exerciseNames) {
    final key = normaliseExerciseName(n);
    if (key != '') keys.add(key);
  }
  return keys.length;
}

/// Do two free-text exercise spellings name the same lift?
///
/// The one comparison every *consecutive-set* block grouping must make. The
/// display surfaces each walked a flat set list and opened a new block on
/// `last.name != s.exerciseName` -- the raw DISPLAY spelling -- so two
/// consecutive sets of one lift typed two ways rendered as two blocks beside a
/// header stat counting one, [distinctExerciseCount] having been keyed since
/// decisions 1248. Adjacency itself is load-bearing and stays: a superset
/// alternates A/B/A and has to stay three blocks. Only the equality test moves
/// onto the key.
///
/// Blank spellings compare equal to each other, as they did on the raw
/// comparison -- a surface that renders an unnamed set still renders it, and
/// deciding to split those into a block each is a separate call no caller has
/// asked for.
bool sameExerciseName(String? a, String? b) =>
    normaliseExerciseName(a ?? '') == normaliseExerciseName(b ?? '');

class WorkoutPrResult {
  /// The grouping key — [normaliseExerciseName] of the exercise. Carried so a
  /// caller keying a lookup on the result never re-derives it from
  /// [exerciseName], which is a DISPLAY string: re-deriving it with the
  /// runtime's own `toLowerCase()` misses every spelling the frozen fold
  /// collapses and the exercise's chips silently stop rendering (§ 1248).
  final String key;
  final String exerciseName;
  final List<PrKind> kinds;
  const WorkoutPrResult({
    required this.key,
    required this.exerciseName,
    required this.kinds,
  });
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
      results.add(WorkoutPrResult(key: key, exerciseName: cur.exerciseName, kinds: kinds));
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
        results.add(WorkoutPrResult(key: key, exerciseName: cur.exerciseName, kinds: kinds));
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
