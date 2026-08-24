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
/// P2 (THIS FILE, gated): an optional [AdaptiveFitness] input adds a DIRECTION
/// GATE over the already-computed CTL/ATL/TSB series (`training_load.dart`) —
/// no new collection, no new column, no new hop. Three arms:
///
///   1. add volume only when form allows — an "under-run, do more" trend is
///      SUPPRESSED while TSB < 0, because you never pile volume onto a fatigue
///      hole;
///   2. override to DELOAD when TSB is deeply negative AND acute load is high
///      against the chronic base — the load signal then outranks whatever the
///      adherence trend said, in either direction;
///   3. suggest nothing on disagreement (arm 1's outcome).
///
/// The fitness snapshot is a parameter and dies here: nothing in
/// [AdaptiveReplanResult] carries a load number back out, and this library logs
/// nothing — so a TSB can reach a suggestion but can never reach a log line, a
/// plan row, or the network. That is a stated condition of the sign-off, so it
/// is enforced structurally rather than by convention.
///
/// This is the first phase that reads health-derived load into a prescription,
/// so the whole input is behind a FAIL-CLOSED deploy gate — mobile
/// `ADAPTIVE_FITNESS_GATE` in dotenv, web `PUBLIC_ADAPTIVE_FITNESS_GATE`, both
/// parsed by [adaptiveFitnessGateEnabled] below so the two platforms cannot
/// drift. Unset → the caller passes no fitness → behaviour is exactly P1.
/// Flipping the flag on for a prod build is the CISO / Security-Analyst
/// sign-off-gated action (decisions §144 + §150).
///
/// Dart twin of `apps/web/src/lib/training/plan_adaptive_replan.ts` — keep in
/// lockstep (equal test counts).
library;

import 'env_flag.dart';
import 'plan_adherence.dart';
import 'plan_replan.dart';

/// How many trailing COMPLETED weeks define the trend.
const int adaptiveTrendWindow = 3;

/// At least this many flagged weeks (in one direction) within the window make
/// a trend. Two-of-three is the "sustained, not noise" bar.
const int adaptiveTrendMin = 2;

/// TSB at or below this counts as DEEPLY negative — form is in the hole, not
/// merely down after one hard week. Conventional reading of the CTL/ATL/TSB
/// model puts −10..−25 in the productive-training band and past −25 into
/// overreaching, so that is where "stop adding, start bleeding" sits.
const double adaptiveDeepFatigueTsb = -25;

/// Acute:chronic workload ratio at or above which acute load counts as HIGH
/// against the base the runner has actually absorbed. 1.3 is the conventional
/// injury-risk threshold. Required alongside the TSB floor so a runner whose
/// whole load is simply large (high ATL and high CTL together) isn't told to
/// deload — only one carrying acute load their chronic base doesn't support.
const double adaptiveHighAcwr = 1.3;

enum AdaptiveReason {
  trendUnderfitness,
  trendOvertraining,

  /// P2 arm 2: the fitness signal overrode the direction to a deload.
  deloadFatigue,
  onTrack,
}

/// How strongly the window agrees with the trend direction.
enum AdaptiveConfidence { high, medium, low }

/// P2: the runner's current training-load state, sourced from the
/// ALREADY-COMPUTED training_load.dart series (no new data collection).
/// Consumed in-memory to pick a direction; never echoed back out, logged, or
/// persisted.
class AdaptiveFitness {
  /// Training Stress Balance (form). Negative = fatigued.
  final double tsb;

  /// Acute load (fatigue).
  final double atl;

  /// Chronic load (fitness).
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
  /// fitness signal contradicts the adherence trend (fatigued runner) and
  /// nothing is proposed in its place. A deload override reports its outcome
  /// through [reason] instead.
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

/// Pure parse of the P2 fitness-gate deploy flag, delegating to the one
/// canonical [isTruthyFlagValue] so the accepted-affirmative set is a single
/// contract across every gate on both platforms (decisions § 709).
/// Fail-closed: the whole health-derived-load → prescription path stays
/// unreachable until CISO / Security-Analyst sign-off flips the flag at deploy
/// time. The mobile binding reads `dotenv.env['ADAPTIVE_FITNESS_GATE']`; the
/// web env binding lives in `adaptive_fitness_flag.ts`.
bool adaptiveFitnessGateEnabled(String? raw) => isTruthyFlagValue(raw);

/// Deeply fatigued: form in the hole AND acute load high against a real chronic
/// base. Non-finite or absent chronic load fails closed (a runner with no
/// chronic base has nothing for acute load to be "high" against).
bool _isDeeplyFatigued(AdaptiveFitness f) {
  if (!f.tsb.isFinite || !f.atl.isFinite || !f.ctl.isFinite) return false;
  if (!(f.ctl > 0)) return false;
  return f.tsb <= adaptiveDeepFatigueTsb && f.atl >= f.ctl * adaptiveHighAcwr;
}

/// Classify the trailing completed weeks' adherence trend and, when a sustained
/// drift is found, return the future-only changes [replanRemaining] would make.
/// Fails toward `onTrack` whenever a trend can't be established. When [fitness]
/// is supplied (P2), the load signal gates the direction: an under-fitness ramp
/// is suppressed for a fatigued runner, and deep fatigue overrides to a deload.
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

  // P2 arm 2 — deep-fatigue DELOAD OVERRIDE. Checked before the adherence
  // arms because it is the only branch where the runner is at genuine risk:
  // whatever the plan says they ran, the load says bleed it off. Never adds
  // volume (the make-up pass is skipped entirely), so it is also a strict
  // tightening of arm 1 rather than a competing rule.
  if (fitness != null && _isDeeplyFatigued(fitness)) {
    final lastComplete = _lastComplete(sorted);
    final changes = easeOffNextWeek(sorted, lastComplete?.weekIndex ?? -1);
    return AdaptiveReplanResult(
      changes: changes,
      reason: AdaptiveReason.deloadFatigue,
      // The load signal crossed both thresholds — nothing about the week
      // window makes it more or less certain.
      confidence: AdaptiveConfidence.high,
      onTrack: changes.isEmpty,
      trailingDirections: trailingDirections,
      fitnessGated: false,
    );
  }

  // P2 arms 1 + 3 — direction gate: don't pile volume onto a fatigued runner.
  // When the adherence trend says "do more" but form (TSB) is negative, the
  // signals disagree → suggest nothing, flagged as fitness-gated.
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

ReplanWeek? _lastComplete(List<ReplanWeek> sorted) {
  for (final w in sorted.reversed) {
    if (w.isComplete) return w;
  }
  return null;
}
