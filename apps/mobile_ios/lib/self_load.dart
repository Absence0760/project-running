/// The runner's own acute:chronic workload ratio, and what it means.
///
/// ACWR and its injury-risk bands already exist in `coach_load.dart`, but only
/// a *coach* ever saw them — the roster classifies other people's athletes,
/// and `plan_ramp.dart` grades a hypothetical future plan. The runner looking
/// at their own dashboard, who mostly has no coach at all, was never told that
/// their last seven days run 60 % above their month's average.
///
/// This is a different question from readiness. `readiness` scores today
/// (form, sleep, resting HR) — "should I run hard this morning". ACWR scores
/// the last month's ramp — "have I built too fast to keep getting away with
/// it". A runner can be fully recovered today and still sitting in the spike
/// zone that shows up as an injury three weeks from now.
///
/// Dart twin of `apps/web/src/lib/training/self_load.ts` — keep the algorithm,
/// band edges, gates, and test counts in lockstep. The reduction it grades
/// comes from `plan_ramp.dart`, not from a private copy, for the reason that
/// module documents: `comeback.dart` reduces the same runs over a different
/// window, and two copies of the filter would let the two disagree.
library;

import 'coach_load.dart';
import 'plan_ramp.dart';

class SelfLoad {
  /// [InjuryRiskBand.insufficient] whenever the ratio would be arithmetic on
  /// noise — the caller renders nothing rather than a band it cannot stand
  /// behind.
  final InjuryRiskBand band;
  final LoadTrend trend;

  /// acute / chronic. 0 when the band is insufficient.
  final double ratio;

  /// Last 7 days' running distance, metres.
  final double acuteM;

  /// Mean weekly running distance over the chronic window, metres.
  final double chronicWeeklyM;
  final int activeWeeks;

  const SelfLoad({
    required this.band,
    required this.trend,
    required this.ratio,
    required this.acuteM,
    required this.chronicWeeklyM,
    required this.activeWeeks,
  });
}

/// Grade the runner's current load ramp from their recent runs.
///
/// The ratio is taken over **distance**, not the coach roster's km×10 stress
/// proxy. That proxy is linear in distance, so the quotient is identical — the
/// ×10 cancels — and reproducing the constant here would be a second place for
/// it to drift. [acwr] is still the one implementation doing the division.
///
/// Requires [kMinActiveWeeks] of the chronic window to carry a run, for the
/// reason `plan_ramp` already documents: one 3 km jog in a month is not a
/// chronic base, and dividing by it manufactures a terrifying ratio out of a
/// runner who has barely trained. Under-reporting a real spike is the failure
/// that hurts here, but inventing one is how a safety signal gets ignored.
SelfLoad selfLoad(List<RunForVolume> runs, int nowMs) {
  final recent = recentRunVolume(runs, nowMs);
  SelfLoad build(InjuryRiskBand band, LoadTrend trend, double ratio) {
    return SelfLoad(
      band: band,
      trend: trend,
      ratio: ratio,
      acuteM: recent.acuteM,
      chronicWeeklyM: recent.weeklyM,
      activeWeeks: recent.activeWeeks,
    );
  }

  if (recent.activeWeeks < kMinActiveWeeks) {
    return build(InjuryRiskBand.insufficient, LoadTrend.steady, 0);
  }
  final band = injuryRiskBand(recent.acuteM, recent.weeklyM);
  if (band == InjuryRiskBand.insufficient) {
    return build(band, LoadTrend.steady, 0);
  }
  return build(
    band,
    loadTrend(recent.acuteM, recent.weeklyM),
    acwr(recent.acuteM, recent.weeklyM),
  );
}

/// Whether the dashboard has a load ramp worth showing. Only the gradeable
/// bands earn the card; insufficient renders nothing at all, matching how
/// every other analytics card self-hides rather than showing a zeroed stat.
///
/// Web returns a type predicate here, narrowing the band to the four it has
/// copy for so an unlabelled band is a compile error. Dart has no analogue for
/// narrowing a field's enum through a boolean, so this is a plain bool and the
/// caller's `switch` over the four is what the analyzer checks instead.
bool shouldSurfaceSelfLoad(SelfLoad load) {
  return load.band != InjuryRiskBand.insufficient;
}
