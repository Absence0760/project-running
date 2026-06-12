/// Adaptive re-plan (plan generator v2). Where [replanRemaining] reacts to a
/// single signal (a missed long run, last week over), this gates a re-plan on a
/// MULTI-WEEK adherence TREND: it only proposes changes when the last few
/// completed weeks show a sustained drift, suppressing single-week noise the
/// manual re-plan would act on.
///
/// Pure + suggestion-only: classify the trailing completed weeks' drift, and
/// when a trend is flagged delegate the actual future-only deltas to
/// [replanRemaining] — this layer decides WHETHER and WHY, the shipped engine
/// decides WHAT. Past + taper stay frozen because [replanRemaining] already
/// freezes them; this layer never widens that.
///
/// P1 (shipped, decisions §144): intensity/volume-only off adherence drift.
///
/// P2 (THIS FILE, gated): an optional [fitness] input adds a DIRECTION GATE — an
/// adherence "you've under-run, do more" trend is SUPPRESSED when the runner is
/// already fatigued (TSB < 0). First phase reading health-derived load into a
/// prescription, so GATED ON CISO / SECURITY-ANALYST SIGN-OFF before it ships
/// (reviews/plan-generator-v2-p2-ciso-note.md). Branch feat/gen-v2-p2-fitness.
///
/// Dart twin of `apps/web/src/lib/training/plan_adaptive_replan.ts` — keep in
/// lockstep (equal test counts).
library;

import 'plan_adherence.dart';
import 'plan_replan.dart';

/// How many trailing COMPLETED weeks define the trend.
const int adaptiveTrendWindow = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
const int adaptiveTrendMin = 2;

enum AdaptiveReason { trendUnderfitness, trendOvertraining, onTrack }

/// How strongly the window agrees with the trend direction.
enum AdaptiveConfidence { high, medium, low }

/// P2: the runner's current training-load state, sourced from the
/// ALREADY-COMPUTED training_load.dart series (no new data collection). Only the
/// sign of [tsb] (form) is consulted; never logged or persisted.
class AdaptiveFitness {
  final double tsb;
  final double atl;
  final double ctl;
  const AdaptiveFitness({required this.tsb, required this.atl, required this.ctl});
}

class AdaptiveReplanResult {
  final List<ReplanChange> changes;
  final AdaptiveReason reason;
  final AdaptiveConfidence confidence;
  final bool onTrack;
  final List<DriftDirection> trailingDirections;

  /// P2: true when a would-be add-volume suggestion was withheld because the
  /// fitness signal contradicts the adherence trend (fatigued runner).
  final bool fitnessGated;

  const AdaptiveReplanResult({
    required this.changes,
    required this.reason,
    required this.confidence,
    required this.onTrack,
    required this.trailingDirections,
    required this.fitnessGated,
  });
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes [replanRemaining] would make.
/// Fails toward `onTrack` whenever a trend can't be established. When [fitness]
/// is supplied (P2), an under-fitness ramp is suppressed for a fatigued runner.
AdaptiveReplanResult adaptiveReplanRemaining({
  required List<ReplanWeek> weeks,

  /// ISO today (YYYY-MM-DD).
  required String today,

  /// P2 (gated): current fitness/fatigue. Omit for the P1 behaviour.
  AdaptiveFitness? fitness,
}) {
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));

  final completed = sorted.where((w) => w.isComplete && w.plannedMetres > 0).toList();
  final window = completed.length > adaptiveTrendWindow
      ? completed.sublist(completed.length - adaptiveTrendWindow)
      : completed;
  final drifts = window.map((w) => weeklyDrift(w.plannedMetres, w.actualMetres)).toList();
  final trailingDirections = drifts.map((d) => d.direction).toList();

  final under =
      drifts.where((d) => d.flagged && d.direction == DriftDirection.under).length;
  final over =
      drifts.where((d) => d.flagged && d.direction == DriftDirection.over).length;

  var reason = AdaptiveReason.onTrack;
  if (under >= adaptiveTrendMin && under > over) {
    reason = AdaptiveReason.trendUnderfitness;
  } else if (over >= adaptiveTrendMin && over > under) {
    reason = AdaptiveReason.trendOvertraining;
  }

  // P2 direction gate: don't pile volume onto a fatigued runner. When the
  // adherence trend says "do more" but form (TSB) is negative, the signals
  // disagree → suggest nothing (fail to on_track), flagged as fitness-gated.
  if (reason == AdaptiveReason.trendUnderfitness && fitness != null && fitness.tsb < 0) {
    return AdaptiveReplanResult(
      changes: const [],
      reason: AdaptiveReason.onTrack,
      confidence: AdaptiveConfidence.low,
      onTrack: true,
      trailingDirections: trailingDirections,
      fitnessGated: true,
    );
  }

  if (reason == AdaptiveReason.onTrack) {
    return AdaptiveReplanResult(
      changes: const [],
      reason: reason,
      confidence: AdaptiveConfidence.low,
      onTrack: true,
      trailingDirections: trailingDirections,
      fitnessGated: false,
    );
  }

  final agree = reason == AdaptiveReason.trendUnderfitness ? under : over;
  final confidence =
      agree >= window.length ? AdaptiveConfidence.high : AdaptiveConfidence.medium;

  final result = replanRemaining(weeks: sorted, today: today);
  return AdaptiveReplanResult(
    changes: result.changes,
    reason: reason,
    confidence: confidence,
    onTrack: result.changes.isEmpty,
    trailingDirections: trailingDirections,
    fitnessGated: false,
  );
}
