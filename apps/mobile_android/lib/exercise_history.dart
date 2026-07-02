/// Per-exercise progression over time (Phase 4 multi-modal, decisions §63;
/// spec: docs/features/multi_modal.md § Gym). Drives the gym exercise
/// drill-down linked from each records card.
///
/// Dart twin of `apps/web/src/lib/gym/exercise_history.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
///
/// Records (exercise_records.dart) answer "what's my current best?". This
/// answers the next question — "am I getting stronger?" — by collapsing every
/// session that included one exercise into a chronological series: each
/// session's top set, best estimated 1RM, total volume, and whether that
/// session set a new e1RM PR at the time. The headline est.-1RM delta (latest
/// vs first) is the "are you progressing" signal.
///
/// Pure functions, no Flutter / Supabase deps. Reuses the gym_prs primitives
/// (estimatedOneRepMax, normaliseExerciseName, computeExercisePrs) so the
/// numbers and the display spelling stay consistent with the records + badge
/// surfaces.
library;

import 'exercise_records.dart';
import 'gym_prs.dart';

class ExerciseSession {
  final String workoutId;

  /// started_at of the workout (ISO).
  final String startedAt;

  /// Heaviest single weighted set in this session, kg. Always non-null (a
  /// session only qualifies once it has at least one weighted set).
  final double topWeightKg;

  /// Reps at the heaviest set (for "100 kg × 5" display).
  final num? topWeightReps;

  /// Best estimated 1RM in this session, kg. Null if no set had reps.
  final double? bestEst1RmKg;

  /// Total working volume (Σ reps·weight over weighted sets), kg.
  final double volumeKg;

  /// Weighted sets of this exercise logged in the session.
  final int setCount;

  /// True when this session's heaviest set strictly beat every earlier
  /// session's — a new heaviest-weight PR at the time. Judged on the same
  /// single-set metric the records surface calls "Heaviest", so the badges
  /// agree. Distinct from an e1RM PR: a heavier single at low reps can beat
  /// the weight best without beating a prior high-rep e1RM.
  final bool isWeightPr;

  /// True when this session's best e1RM strictly beat every earlier session's
  /// — i.e. it set a new estimated-1RM PR at the time.
  final bool isEst1RmPr;

  const ExerciseSession({
    required this.workoutId,
    required this.startedAt,
    required this.topWeightKg,
    required this.topWeightReps,
    required this.bestEst1RmKg,
    required this.volumeKg,
    required this.setCount,
    required this.isWeightPr,
    required this.isEst1RmPr,
  });
}

class ExerciseProgress {
  /// Display spelling — inherited from the PR engine so it matches the records
  /// card the user clicked.
  final String exerciseName;

  /// Chronological (oldest first), one entry per qualifying session.
  final List<ExerciseSession> sessions;

  /// e1RM of the first session that had one (kg). Null if none ever did.
  final double? firstEst1RmKg;

  /// e1RM of the most recent session that had one (kg).
  final double? latestEst1RmKg;

  /// Best e1RM across all sessions (kg).
  final double? bestEst1RmKg;

  /// latest − first, kg, rounded to 1 dp. Null unless at least two sessions
  /// carried an e1RM (no delta to report from a single data point).
  final double? est1RmDeltaKg;

  const ExerciseProgress({
    required this.exerciseName,
    required this.sessions,
    required this.firstEst1RmKg,
    required this.latestEst1RmKg,
    required this.bestEst1RmKg,
    required this.est1RmDeltaKg,
  });
}

double _round1(double n) => (n * 10).round() / 10;

class _Group {
  final String workoutId;
  final String startedAt;
  double topWeightKg = 0;
  num? topWeightReps;
  double? bestEst1RmKg;
  double volumeKg = 0;
  int setCount = 0;
  _Group(this.workoutId, this.startedAt);
}

/// Build one exercise's progression from a flat, dated set list. Returns null
/// when the name resolves to no qualifying (weighted) session — the same
/// bodyweight-only exclusion the records + PR surfaces apply. Sessions are
/// sorted oldest-first; ties (same started_at) break by workout id so the
/// order is deterministic.
ExerciseProgress? exerciseProgress(List<DatedGymSet> sets, String exerciseName) {
  final key = normaliseExerciseName(exerciseName);
  if (key == '') return null;

  final groups = <String, _Group>{};
  for (final s in sets) {
    if (normaliseExerciseName(s.exerciseName) != key) continue;
    final weight = _numericOrNull(s.weightKg);
    if (weight == null || weight <= 0) continue; // bodyweight set — no record
    final reps = _numericOrNull(s.reps);

    final g = groups.putIfAbsent(s.workoutId, () => _Group(s.workoutId, s.startedAt));
    g.setCount += 1;
    // Heaviest set; ties broken by more reps (mirrors computeExercisePrs).
    if (weight > g.topWeightKg ||
        (weight == g.topWeightKg && (reps ?? 0) > (g.topWeightReps ?? 0))) {
      g.topWeightKg = weight;
      g.topWeightReps = reps;
    }
    if (reps != null && reps > 0) {
      g.volumeKg += weight * reps;
      final e1rm = estimatedOneRepMax(weight, reps.toInt());
      if (g.bestEst1RmKg == null || e1rm > g.bestEst1RmKg!) g.bestEst1RmKg = e1rm;
    }
  }

  if (groups.isEmpty) return null;

  final ordered = groups.values.toList()
    ..sort((a, b) {
      if (a.startedAt != b.startedAt) return a.startedAt.compareTo(b.startedAt);
      return a.workoutId.compareTo(b.workoutId);
    });

  var runningBestE1rm = double.negativeInfinity;
  var runningBestWeight = double.negativeInfinity;
  final sessions = ordered.map((g) {
    final e1rm = g.bestEst1RmKg;
    final isEst1RmPr = e1rm != null && e1rm > runningBestE1rm;
    if (isEst1RmPr) runningBestE1rm = e1rm;
    // A qualifying session always has a positive topWeightKg, so the first
    // one clears -Infinity — the "no prior best ⇒ PR" rule workoutPrs uses.
    final isWeightPr = g.topWeightKg > runningBestWeight;
    if (isWeightPr) runningBestWeight = g.topWeightKg;
    return ExerciseSession(
      workoutId: g.workoutId,
      startedAt: g.startedAt,
      topWeightKg: g.topWeightKg,
      topWeightReps: g.topWeightReps,
      bestEst1RmKg: e1rm == null ? null : _round1(e1rm),
      volumeKg: g.volumeKg.roundToDouble(),
      setCount: g.setCount,
      isWeightPr: isWeightPr,
      isEst1RmPr: isEst1RmPr,
    );
  }).toList();

  final withE1rm = sessions.where((s) => s.bestEst1RmKg != null).toList();
  final firstEst1RmKg = withE1rm.isNotEmpty ? withE1rm.first.bestEst1RmKg : null;
  final latestEst1RmKg = withE1rm.isNotEmpty ? withE1rm.last.bestEst1RmKg : null;
  double? bestEst1RmKg;
  for (final s in withE1rm) {
    if (bestEst1RmKg == null || s.bestEst1RmKg! > bestEst1RmKg) {
      bestEst1RmKg = s.bestEst1RmKg;
    }
  }
  final est1RmDeltaKg =
      withE1rm.length >= 2 ? _round1(latestEst1RmKg! - firstEst1RmKg!) : null;

  return ExerciseProgress(
    exerciseName: _displayName(sets, key, exerciseName),
    sessions: sessions,
    firstEst1RmKg: firstEst1RmKg,
    latestEst1RmKg: latestEst1RmKg,
    bestEst1RmKg: bestEst1RmKg,
    est1RmDeltaKg: est1RmDeltaKg,
  );
}

/// The most recent qualifying (weighted) session of an exercise strictly
/// before [beforeStartedAt] — the "last time" a workout's detail screen
/// compares against for a progressive-overload hint. Returns null when there
/// is no earlier session. Because sessions sharing the compared workout's
/// `started_at` are excluded by the strict `<`, passing that workout's own
/// started_at naturally drops its own session from the lookup.
ExerciseSession? previousExerciseSession(
  List<DatedGymSet> sets,
  String exerciseName,
  String beforeStartedAt,
) {
  final prog = exerciseProgress(sets, exerciseName);
  if (prog == null) return null;
  ExerciseSession? prev;
  for (final s in prog.sessions) {
    if (s.startedAt.compareTo(beforeStartedAt) < 0) {
      prev = s;
    } else {
      break; // sessions are chronological — nothing later qualifies
    }
  }
  return prev;
}

/// Resolve the display spelling the same way the records + badge surfaces do —
/// via the PR engine (first set, in input order, that maps to the key) — so
/// the drill-down title matches the card the user clicked. Falls back to the
/// caller-supplied name if the PR engine has no entry (shouldn't happen once a
/// qualifying session exists).
String _displayName(List<GymSetLike> sets, String key, String fallback) =>
    computeExercisePrs(sets)[key]?.exerciseName ?? fallback;

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
