/// Fundraiser thermometer math (fundraising.md).
///
/// Pure, deterministic, no I/O — computes the goal-thermometer state from
/// `(raisedCents, goalCents)`: the bar fill percentage (clamped to 0–100 for
/// the bar geometry), the true uncapped percentage (so the UI can show
/// "118% — over goal!"), the cents still needed, and a coarse [ThermometerState]
/// that drives the bar styling + label.
///
/// TS↔Dart parity pair: keep in lockstep with
/// `apps/web/src/lib/social/fundraiser_progress.ts` — same algorithm, same
/// edge cases, same test count.
library;

enum ThermometerState { starting, progressing, met, exceeded }

class FundraiserProgress {
  /// Bar fill 0–100 (clamped), for the thermometer geometry.
  final double fillPct;

  /// True percentage of goal raised, uncapped (can exceed 100).
  final double rawPct;

  /// Cents still needed to reach the goal; 0 once met or exceeded.
  final int remainingCents;

  final ThermometerState state;

  const FundraiserProgress({
    required this.fillPct,
    required this.rawPct,
    required this.remainingCents,
    required this.state,
  });
}

/// Below this fill the bar reads as "just getting started".
const double startingThresholdPct = 10;

/// Resolve the thermometer state from raised vs goal.
///
/// Defensive: a non-finite or non-positive goal yields a zeroed,
/// [ThermometerState.starting] result (the bar renders empty rather than
/// dividing by zero); negative raised is floored to 0.
FundraiserProgress fundraiserProgress(num raisedCents, num goalCents) {
  final raised = raisedCents.isFinite && raisedCents > 0 ? raisedCents : 0;
  if (!goalCents.isFinite || goalCents <= 0) {
    return const FundraiserProgress(
      fillPct: 0,
      rawPct: 0,
      remainingCents: 0,
      state: ThermometerState.starting,
    );
  }

  final rawPct = (raised / goalCents) * 100;
  final fillPct = rawPct.clamp(0, 100).toDouble();
  final remainingCents = (goalCents - raised) > 0 ? (goalCents - raised).round() : 0;

  final ThermometerState state;
  if (raised > goalCents) {
    state = ThermometerState.exceeded;
  } else if (raised >= goalCents) {
    state = ThermometerState.met;
  } else if (rawPct < startingThresholdPct) {
    state = ThermometerState.starting;
  } else {
    state = ThermometerState.progressing;
  }

  return FundraiserProgress(
    fillPct: fillPct,
    rawPct: rawPct.toDouble(),
    remainingCents: remainingCents,
    state: state,
  );
}
