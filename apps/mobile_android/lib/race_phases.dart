/// Race pacing-strategy phase plans — pure, locale/unit-agnostic. Slices a
/// race distance into intent phases (hold back / settle / race) whose pace
/// factors multiply the goal pace, with the derived final factor chosen so the
/// distance-weighted mean factor is exactly 1.0 — the plan still lands the
/// goal time.
///
/// Presets: even (one flat phase), negativeSplit (2% held-back first half,
/// derived-faster second half), and tenTenTen (the classic marathon
/// 10 mi / 10 mi / 10 K strategy generalised proportionally to any distance).
/// Intent is an identifier — i18n labels resolve at the render layer and are
/// not part of the pair.
///
/// Twin of `apps/web/src/lib/runs/race_phases.ts` — keep logic, edge cases,
/// and test count in lockstep.

enum RacePhasePreset { tenTenTen, negativeSplit, even }

extension RacePhasePresetWire on RacePhasePreset {
  String get wire => switch (this) {
        RacePhasePreset.tenTenTen => 'ten_ten_ten',
        RacePhasePreset.negativeSplit => 'negative_split',
        RacePhasePreset.even => 'even',
      };
}

enum RacePhaseIntent { holdBack, settle, race, even }

extension RacePhaseIntentWire on RacePhaseIntent {
  String get wire => switch (this) {
        RacePhaseIntent.holdBack => 'hold_back',
        RacePhaseIntent.settle => 'settle',
        RacePhaseIntent.race => 'race',
        RacePhaseIntent.even => 'even',
      };
}

class RacePhase {
  final double startM;
  final double endM;
  final RacePhaseIntent intent;
  final double paceFactor;

  const RacePhase({
    required this.startM,
    required this.endM,
    required this.intent,
    required this.paceFactor,
  });
}

const double _tenMileFraction = 16093.44 / 42195;
const double _holdBackFactor = 1.02;

List<RacePhase> buildPhasePlan(double distanceM, RacePhasePreset preset) {
  if (!distanceM.isFinite || distanceM <= 0) return [];

  if (preset == RacePhasePreset.even) {
    return [
      RacePhase(
          startM: 0, endM: distanceM, intent: RacePhaseIntent.even, paceFactor: 1),
    ];
  }

  if (preset == RacePhasePreset.negativeSplit) {
    const raceFactor = (1 - 0.5 * _holdBackFactor) / 0.5;
    return [
      RacePhase(
          startM: 0,
          endM: distanceM / 2,
          intent: RacePhaseIntent.holdBack,
          paceFactor: _holdBackFactor),
      RacePhase(
          startM: distanceM / 2,
          endM: distanceM,
          intent: RacePhaseIntent.race,
          paceFactor: raceFactor),
    ];
  }

  const f1 = _tenMileFraction;
  const f2 = _tenMileFraction;
  const f3 = 1 - f1 - f2;
  const raceFactor = (1 - f1 * _holdBackFactor - f2 * 1) / f3;
  return [
    RacePhase(
        startM: 0,
        endM: distanceM * f1,
        intent: RacePhaseIntent.holdBack,
        paceFactor: _holdBackFactor),
    RacePhase(
        startM: distanceM * f1,
        endM: distanceM * (f1 + f2),
        intent: RacePhaseIntent.settle,
        paceFactor: 1),
    RacePhase(
        startM: distanceM * (f1 + f2),
        endM: distanceM,
        intent: RacePhaseIntent.race,
        paceFactor: raceFactor),
  ];
}

/// Index of the phase containing [distanceM] (start-inclusive, end-exclusive;
/// >= the last end clamps to the last index, < 0 clamps to the first).
/// Empty plan → -1.
int phaseAt(List<RacePhase> phases, double distanceM) {
  if (phases.isEmpty) return -1;
  if (distanceM < 0) return 0;
  for (var i = 0; i < phases.length; i++) {
    if (distanceM >= phases[i].startM && distanceM < phases[i].endM) return i;
  }
  return phases.length - 1;
}

double? phaseTargetPaceSecPerKm(RacePhase phase, double? goalPaceSecPerKm) {
  if (goalPaceSecPerKm == null ||
      !goalPaceSecPerKm.isFinite ||
      goalPaceSecPerKm <= 0) {
    return null;
  }
  return goalPaceSecPerKm * phase.paceFactor;
}

double? goalPaceSecPerKm(double distanceM, double goalTimeS) {
  if (!distanceM.isFinite || distanceM <= 0) return null;
  if (!goalTimeS.isFinite || goalTimeS <= 0) return null;
  return goalTimeS / (distanceM / 1000);
}
