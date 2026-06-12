/// Plan-adherence feedback — does the runner's actual training match the
/// plan? Two signals, both pure (no Supabase / Flutter):
///
///  1. Weekly mileage drift — flags when actual weekly volume runs more
///     than ±20% off the plan. BOTH directions matter: under-running loses
///     the adaptation; over-running the easy weeks is the classic way a
///     motivated runner digs a fatigue hole.
///
///  2. Missed-long-run advice — a make-up / skip recommendation for a long
///     run the runner blew past, driven by training phase and proximity to
///     a recovery week.
///
/// Dart twin of `apps/web/src/lib/training/plan_adherence.ts` — keep the
/// algorithm, edge cases, outputs, and test counts in lockstep.
library;

/// Beyond ±this fraction off the planned weekly volume, surface a drift flag.
const double planDriftThreshold = 0.2;

enum DriftDirection { under, over, onTrack }

class WeeklyDrift {
  final double plannedMetres;
  final double actualMetres;

  /// (actual − planned) / planned. Positive = over-running, negative =
  /// under-running. 0 when there's no planned volume to compare against.
  final double driftFraction;
  final DriftDirection direction;

  /// True when |driftFraction| exceeds the threshold AND there's a real plan
  /// to drift from (planned volume > 0).
  final bool flagged;

  const WeeklyDrift({
    required this.plannedMetres,
    required this.actualMetres,
    required this.driftFraction,
    required this.direction,
    required this.flagged,
  });
}

/// Compare a week's actual mileage to its planned volume. Returns a neutral,
/// unflagged result when the week has no planned volume (a pure rest week, or
/// a week before the plan models distance) so the caller never shows a drift
/// flag against a zero baseline.
WeeklyDrift weeklyDrift(
  double plannedMetres,
  double actualMetres, {
  double threshold = planDriftThreshold,
}) {
  if (!(plannedMetres > 0)) {
    return WeeklyDrift(
      plannedMetres: plannedMetres < 0 ? 0 : plannedMetres,
      actualMetres: actualMetres < 0 ? 0 : actualMetres,
      driftFraction: 0,
      direction: DriftDirection.onTrack,
      flagged: false,
    );
  }
  final actual = actualMetres < 0 ? 0.0 : actualMetres;
  final driftFraction = (actual - plannedMetres) / plannedMetres;
  var direction = DriftDirection.onTrack;
  if (driftFraction > threshold) {
    direction = DriftDirection.over;
  } else if (driftFraction < -threshold) {
    direction = DriftDirection.under;
  }
  return WeeklyDrift(
    plannedMetres: plannedMetres,
    actualMetres: actual,
    driftFraction: driftFraction,
    direction: direction,
    flagged: direction != DriftDirection.onTrack,
  );
}

enum MakeUpRecommendation { makeUp, skip }

enum MissedWorkoutReason { keySession, taper, recoverySoon, notLongRun }

class MissedWorkoutAdvice {
  final MakeUpRecommendation recommendation;
  final MissedWorkoutReason reason;
  const MissedWorkoutAdvice(this.recommendation, this.reason);
}

class MissedWorkoutInput {
  /// Workout kind from the plan (`long`, `tempo`, …).
  final String kind;

  /// Whether the missed workout sits in the taper phase of the plan.
  final bool isTaper;

  /// Whether the very next week is a recovery / step-back week. Null when
  /// unknown (treated as "not imminent").
  final bool? recoveryWeekImminent;

  const MissedWorkoutInput({
    required this.kind,
    required this.isTaper,
    required this.recoveryWeekImminent,
  });
}

/// Recommend whether to make up or skip a missed workout. Only the long run
/// earns a make-up decision; everything else is cheaper to drop than to cram.
/// For a long run: skip in the taper (freshness > one more long run) or when a
/// recovery week is about to absorb the deficit anyway; otherwise make it up.
MissedWorkoutAdvice missedWorkoutAdvice(MissedWorkoutInput input) {
  if (input.kind != 'long') {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.notLongRun);
  }
  if (input.isTaper) {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.taper);
  }
  if (input.recoveryWeekImminent == true) {
    return const MissedWorkoutAdvice(
        MakeUpRecommendation.skip, MissedWorkoutReason.recoverySoon);
  }
  return const MissedWorkoutAdvice(
      MakeUpRecommendation.makeUp, MissedWorkoutReason.keySession);
}
