/// Adaptive re-plan (plan generator v2, P1). Where [replanRemaining] reacts to
/// a single signal (a missed long run, last week over), this gates a re-plan on
/// a MULTI-WEEK adherence TREND: it only proposes changes when the last few
/// completed weeks show a sustained drift, suppressing single-week noise the
/// manual re-plan would act on.
///
/// Pure + suggestion-only: classify the trailing completed weeks' drift, and
/// when a trend is flagged delegate the actual future-only deltas to
/// [replanRemaining] — this layer decides WHETHER and WHY, the shipped engine
/// decides WHAT. Past + taper stay frozen because [replanRemaining] already
/// freezes them; this layer never widens that.
///
/// P1 is intensity/volume-only off adherence drift; fitness (TSB/ATL/CTL)
/// gating is P2 and is the first phase that reads health-derived load, so it
/// carries a CISO sign-off gate. Do not add a fitness signal here without it.
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

class AdaptiveReplanResult {
  /// Future-only changes from [replanRemaining] (empty when the trend is
  /// flagged but no SAFE change applies — e.g. under-running easy volume,
  /// which is deliberately never crammed).
  final List<ReplanChange> changes;
  final AdaptiveReason reason;
  final AdaptiveConfidence confidence;

  /// True when nothing needs changing.
  final bool onTrack;

  /// Drift direction of each examined trailing week, oldest→newest.
  final List<DriftDirection> trailingDirections;

  const AdaptiveReplanResult({
    required this.changes,
    required this.reason,
    required this.confidence,
    required this.onTrack,
    required this.trailingDirections,
  });
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes [replanRemaining] would make.
/// Fails toward `onTrack` whenever a trend can't be established.
AdaptiveReplanResult adaptiveReplanRemaining({
  required List<ReplanWeek> weeks,

  /// ISO today (YYYY-MM-DD).
  required String today,
}) {
  final sorted = [...weeks]..sort((a, b) => a.weekIndex.compareTo(b.weekIndex));

  // Only completed weeks that modelled real volume can carry a trend.
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

  if (reason == AdaptiveReason.onTrack) {
    return AdaptiveReplanResult(
      changes: const [],
      reason: reason,
      confidence: AdaptiveConfidence.low,
      onTrack: true,
      trailingDirections: trailingDirections,
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
  );
}
