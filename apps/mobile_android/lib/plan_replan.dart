/// Training-plan re-planning around missed sessions. Pure: takes a snapshot
/// of the plan (weeks + workouts + per-week actual mileage) and returns a list
/// of proposed changes to FUTURE workouts. The caller previews the diff and
/// applies it via the existing per-row update path.
///
/// Deliberately conservative — this rewrites someone's training, so the rules
/// are the safe, defensible ones a coach would actually use:
///
///  - The past is frozen. Nothing dated before today is touched.
///  - The taper is sacred. Weeks in the `taper` / `race` phase are never
///    modified — freshness for race day beats any make-up.
///  - Missed *easy* volume is let go. Only the long run is worth a make-up.
///  - A make-up never spikes the next long run by more than 15%.
///  - Cumulative over-running triggers a one-week ease-off.
///
/// Dart twin of `apps/web/src/lib/training/plan_replan.ts` — keep in lockstep.
library;

import 'plan_adherence.dart';

/// Cap on how far a make-up may stretch the next long run.
const double makeUpMaxIncrease = 0.15;

/// Multiplier applied to the next week's non-long workouts when over-running.
const double easeOffScale = 0.85;

const Set<String> _taperPhases = {'taper', 'race'};

class ReplanWorkout {
  final String id;

  /// ISO scheduled date (YYYY-MM-DD).
  final String scheduledDate;
  final String kind;
  final double? targetDistanceM;
  final bool completed;

  /// scheduledDate strictly before today.
  final bool isPast;

  const ReplanWorkout({
    required this.id,
    required this.scheduledDate,
    required this.kind,
    required this.targetDistanceM,
    required this.completed,
    required this.isPast,
  });
}

class ReplanWeek {
  final int weekIndex;
  final String phase;
  final double plannedMetres;

  /// Summed actual run mileage dated inside this week's window.
  final double actualMetres;

  /// Every day in the week is before today.
  final bool isComplete;
  final List<ReplanWorkout> workouts;

  const ReplanWeek({
    required this.weekIndex,
    required this.phase,
    required this.plannedMetres,
    required this.actualMetres,
    required this.isComplete,
    required this.workouts,
  });
}

enum ReplanReason { makeUpLong, easeOverRunning }

class ReplanChange {
  final String workoutId;
  final String scheduledDate;
  final ReplanReason reason;
  final double fromMetres;
  final double toMetres;

  const ReplanChange({
    required this.workoutId,
    required this.scheduledDate,
    required this.reason,
    required this.fromMetres,
    required this.toMetres,
  });
}

class ReplanResult {
  final List<ReplanChange> changes;

  /// True when nothing needs changing — the plan is on track.
  final bool onTrack;
  const ReplanResult({required this.changes, required this.onTrack});
}

bool _isTaper(String phase) => _taperPhases.contains(phase);

T? _firstOrNull<T>(Iterable<T> it, bool Function(T) test) {
  for (final e in it) {
    if (test(e)) return e;
  }
  return null;
}

/// Whether a step-back week (a >15% planned-volume drop) immediately follows
/// the week at `idx`.
bool _recoveryWeekImminent(List<ReplanWeek> weeks, int idx) {
  final cur = weeks[idx];
  final next = _firstOrNull(weeks, (w) => w.weekIndex == cur.weekIndex + 1);
  if (next == null || !(cur.plannedMetres > 0) || !(next.plannedMetres > 0)) {
    return false;
  }
  return next.plannedMetres < cur.plannedMetres * 0.85;
}

ReplanResult replanRemaining({
  required List<ReplanWeek> weeks,

  /// ISO today (YYYY-MM-DD).
  required String today,
}) {
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));
  final changes = <ReplanChange>[];

  // Future, non-taper long runs available to absorb a make-up.
  final futureLongRuns = sorted
      .expand((w) => _isTaper(w.phase) ? <ReplanWorkout>[] : w.workouts)
      .where((wo) => !wo.isPast && wo.kind == 'long')
      .toList()
    ..sort((a, b) => a.scheduledDate.compareTo(b.scheduledDate));

  // ── 1. Missed long runs in past weeks → make up in the future ──
  // With several outstanding missed long runs the make-up honours the
  // LARGEST one (the most demanding session to recover), not whichever
  // happened first.
  var maxMissedLong = 0.0;
  for (var i = 0; i < sorted.length; i++) {
    final week = sorted[i];
    for (final wo in week.workouts) {
      if (wo.kind != 'long' || !wo.isPast || wo.completed) continue;
      final advice = missedWorkoutAdvice(MissedWorkoutInput(
        kind: 'long',
        isTaper: _isTaper(week.phase),
        recoveryWeekImminent: _recoveryWeekImminent(sorted, i),
      ));
      if (advice.recommendation != MakeUpRecommendation.makeUp) continue;
      final missed = wo.targetDistanceM ?? 0;
      if (missed > maxMissedLong) maxMissedLong = missed;
    }
  }
  if (futureLongRuns.isNotEmpty && maxMissedLong > 0) {
    final next = futureLongRuns.first;
    final plannedNext = next.targetDistanceM ?? 0;
    if (plannedNext > 0) {
      final capped =
          maxMissedLong < (plannedNext * (1 + makeUpMaxIncrease)).round()
              ? maxMissedLong
              : (plannedNext * (1 + makeUpMaxIncrease)).round().toDouble();
      if (capped > plannedNext) {
        changes.add(ReplanChange(
          workoutId: next.id,
          scheduledDate: next.scheduledDate,
          reason: ReplanReason.makeUpLong,
          fromMetres: plannedNext,
          toMetres: capped,
        ));
      }
    }
  }

  // ── 2. Cumulative over-running → ease off the next future week ──
  final lastComplete = _firstOrNull(sorted.reversed, (w) => w.isComplete);
  if (lastComplete != null) {
    final drift =
        weeklyDrift(lastComplete.plannedMetres, lastComplete.actualMetres);
    if (drift.direction == DriftDirection.over) {
      final nextWeek = _firstOrNull(
          sorted,
          (w) =>
              w.weekIndex > lastComplete.weekIndex &&
              !_isTaper(w.phase) &&
              w.workouts.any((wo) => !wo.isPast));
      if (nextWeek != null) {
        for (final wo in nextWeek.workouts) {
          if (wo.isPast || wo.kind == 'rest' || wo.kind == 'long') continue;
          final td = wo.targetDistanceM;
          if (td == null || td <= 0) continue;
          if (changes.any((c) => c.workoutId == wo.id)) continue;
          changes.add(ReplanChange(
            workoutId: wo.id,
            scheduledDate: wo.scheduledDate,
            reason: ReplanReason.easeOverRunning,
            fromMetres: td,
            toMetres: (td * easeOffScale).round().toDouble(),
          ));
        }
      }
    }
  }

  return ReplanResult(changes: changes, onTrack: changes.isEmpty);
}
