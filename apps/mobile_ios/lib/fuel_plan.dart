/// Race fueling plan — a per-leg carbs/hr + fluid plan synced to the roadbook's
/// aid-station timeline. The deferred fueling half of the roadbook
/// (race_roadbook.md § Deferred / race_fueling_plan.md).
///
/// [buildFuelPlan] takes the roadbook's per-leg schedule and scales a carbs +
/// fluid target onto each leg by its **duration** (carbs/hr × leg-hours,
/// fluid/hr × heat × leg-hours). On the start line and on each refill
/// checkpoint (one carrying water or food) it also emits [FuelLeg.carryToNextAid]
/// — the fuel to carry out to reach the next refill (inclusive of the leg
/// arriving there), so a runner knows "carry 3 gels + 500 ml out of Aid 1".
/// Optionally estimates per-leg energy burn via [runCalories] when a bodyweight
/// is supplied.
///
/// Twin of `apps/web/src/lib/routes/fuel_plan.ts` — keep the scaling, carry
/// rules, edge cases, and test count in lockstep.
library;

import 'dart:math' as math;

import 'exercise_calories.dart' show runCalories;

/// Conservative default intake rates (race_fueling_plan.md § Design).
const double defaultCarbsPerHourG = 60;
const double defaultFluidPerHourMl = 500;

/// Heat toggle multiplier on fluid (not carbs).
const double heatFluidFactor = 1.5;

/// Carbs per gel, for the [FuelLeg.carryToNextAid] gel count.
const double gelCarbsG = 25;

/// Minimal per-leg input. The surface maps each `RoadbookLeg` to one of these.
class FuelLegInput {
  final double projectedElapsedS;
  final double legDistM;
  final List<String> services;
  const FuelLegInput({
    required this.projectedElapsedS,
    required this.legDistM,
    this.services = const [],
  });
}

class FuelCarry {
  final double carbsG;
  final double fluidMl;
  final int gels;
  const FuelCarry({
    required this.carbsG,
    required this.fluidMl,
    required this.gels,
  });
}

class FuelLeg {
  final double carbsG;
  final double fluidMl;

  /// Estimated energy burn for the leg (0 when no bodyweight supplied).
  final double kcal;

  /// Present on the start + each refill checkpoint — what to carry out.
  final FuelCarry? carryToNextAid;

  const FuelLeg({
    required this.carbsG,
    required this.fluidMl,
    required this.kcal,
    this.carryToNextAid,
  });

  FuelLeg _withCarry(FuelCarry carry) => FuelLeg(
        carbsG: carbsG,
        fluidMl: fluidMl,
        kcal: kcal,
        carryToNextAid: carry,
      );
}

class FuelPlan {
  final List<FuelLeg> legs;
  final double totalCarbsG;
  final double totalFluidMl;
  const FuelPlan({
    required this.legs,
    required this.totalCarbsG,
    required this.totalFluidMl,
  });
}

bool _isRefill(FuelLegInput leg) =>
    leg.services.contains('water') || leg.services.contains('food');

/// Build the fueling plan. The returned [FuelPlan.legs] list is parallel to the
/// input (and to the roadbook's legs).
FuelPlan buildFuelPlan(
  List<FuelLegInput> legs, {
  required double carbsPerHourG,
  required double fluidPerHourMl,
  double? heatFactor,
  double? gelCarbsG_,
  double? weightKg,
}) {
  final carbs = math.max(0.0, carbsPerHourG);
  final fluid = math.max(0.0, fluidPerHourMl);
  final heat = (heatFactor != null && heatFactor > 0) ? heatFactor : 1.0;
  final perGel = (gelCarbsG_ != null && gelCarbsG_ > 0) ? gelCarbsG_ : gelCarbsG;

  final out = <FuelLeg>[];
  var prevElapsed = 0.0;
  var totalCarbsG = 0.0;
  var totalFluidMl = 0.0;
  for (final leg in legs) {
    final durS = math.max(0.0, leg.projectedElapsedS - prevElapsed);
    final h = durS / 3600;
    final carbsG = carbs * h;
    final fluidMl = fluid * heat * h;
    out.add(FuelLeg(
      carbsG: carbsG,
      fluidMl: fluidMl,
      kcal: runCalories(leg.legDistM, weightKg),
    ));
    totalCarbsG += carbsG;
    totalFluidMl += fluidMl;
    prevElapsed = leg.projectedElapsedS;
  }

  // Carry-out at the start (index 0) and at each refill checkpoint: sum the
  // fuel of every leg until the next refill, inclusive of the leg arriving
  // there (you consume it before you can refill).
  for (var i = 0; i < legs.length; i++) {
    if (i != 0 && !_isRefill(legs[i])) continue;
    var carbsG = 0.0;
    var fluidMl = 0.0;
    for (var j = i + 1; j < legs.length; j++) {
      carbsG += out[j].carbsG;
      fluidMl += out[j].fluidMl;
      if (_isRefill(legs[j])) break;
    }
    out[i] = out[i]._withCarry(FuelCarry(
      carbsG: carbsG,
      fluidMl: fluidMl,
      gels: carbsG > 0 ? (carbsG / perGel).ceil() : 0,
    ));
  }

  return FuelPlan(legs: out, totalCarbsG: totalCarbsG, totalFluidMl: totalFluidMl);
}
