import 'package:flutter_test/flutter_test.dart';
import '../lib/starter_plans.dart';
import '../lib/training.dart';

void main() {
  test('starterPlans catalogue has the expected presets', () {
    expect(starterPlans.map((s) => s.id).toList(),
        ['c25k', 'half_12wk', 'marathon_16wk']);
  });

  test('starterById finds a preset and returns null for an unknown id', () {
    expect(starterById('marathon_16wk')?.goalEvent, GoalEvent.distanceFull);
    expect(starterById('nope'), isNull);
  });

  test('instantiateStarter returns null for an unknown id', () {
    expect(instantiateStarter('nope', DateTime(2026, 7, 1)), isNull);
  });

  test('C25K starter is a walk-run plan over the full progression', () {
    final plan = instantiateStarter('c25k', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, walkRunDefaultWeeks());
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distance5k]);
    final kinds =
        plan.weeks.expand((w) => w.workouts.map((x) => x.kind)).toList();
    expect(kinds.contains(WorkoutKind.walkRun), isTrue,
        reason: 'C25K should produce walk_run workouts');
  });

  test('half-marathon starter is 12 weeks at the half distance', () {
    final plan = instantiateStarter('half_12wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, 12);
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distanceHalf]);
  });

  test('marathon starter is 16 weeks at the full distance', () {
    final plan = instantiateStarter('marathon_16wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.weeks.length, 16);
    expect(plan.goalDistanceM, kGoalDistancesM[GoalEvent.distanceFull]);
  });

  test('an instantiated starter anchors at the given start date', () {
    final plan = instantiateStarter('half_12wk', DateTime(2026, 7, 1));
    expect(plan, isNotNull);
    expect(plan!.endDate.isAfter(DateTime(2026, 7, 1)), isTrue);
  });
}
