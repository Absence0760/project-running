/// Built-in starter training plans (Training Phase-3). A starter is just a
/// preset set of [generatePlan] inputs — instantiating one produces a
/// [GeneratedPlan] that flows through the same createPlan path the wizard uses
/// (no RPC, no schema, no DB template row). Distinct from club templates, which
/// are DB-owned rows cloned via clone_plan_template.
///
/// Dart twin of `apps/web/src/lib/training/starter_plans.ts` — keep in lockstep
/// (equal test counts).
library;

import 'training.dart';

class StarterPlan {
  /// Stable id; also the ARB key suffix (plansNewStarter<Id>Name / ...Hint).
  final String id;
  final GoalEvent goalEvent;
  final int weeks;
  final int daysPerWeek;

  /// C25K-style walk-run beginner plan.
  final bool beginnerWalkRun;

  const StarterPlan({
    required this.id,
    required this.goalEvent,
    required this.weeks,
    required this.daysPerWeek,
    this.beginnerWalkRun = false,
  });
}

/// The catalogue. Order is the display order on the picker. Not `const` because
/// C25K's week count comes from the runtime [walkRunDefaultWeeks].
final List<StarterPlan> starterPlans = [
  // C25K: weeks MUST be walkRunDefaultWeeks() or the graduation week truncates.
  StarterPlan(
    id: 'c25k',
    goalEvent: GoalEvent.distance5k,
    weeks: walkRunDefaultWeeks(),
    daysPerWeek: 3,
    beginnerWalkRun: true,
  ),
  const StarterPlan(id: 'half_12wk', goalEvent: GoalEvent.distanceHalf, weeks: 12, daysPerWeek: 4),
  const StarterPlan(id: 'marathon_16wk', goalEvent: GoalEvent.distanceFull, weeks: 16, daysPerWeek: 5),
];

StarterPlan? starterById(String id) {
  for (final s in starterPlans) {
    if (s.id == id) return s;
  }
  return null;
}

/// Instantiate a starter into a [GeneratedPlan] anchored at [startDate],
/// delegating to [generatePlan]. Returns null for an unknown id. No goal time /
/// recent-5k is supplied, so paces come back as the conservative fallback —
/// the caller discloses that, same as the wizard.
GeneratedPlan? instantiateStarter(String id, DateTime startDate, {int? age}) {
  final starter = starterById(id);
  if (starter == null) return null;
  return generatePlan(GeneratePlanInput(
    goalEvent: starter.goalEvent,
    startDate: startDate,
    daysPerWeek: starter.daysPerWeek,
    weeks: starter.weeks,
    beginnerWalkRun: starter.beginnerWalkRun,
    age: age,
  ));
}
