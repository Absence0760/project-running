import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_progress.dart';

void main() {
  group('orderedPlanPhases', () {
    test('de-dupes and sorts into canonical order', () {
      final weeks = [
        const PlanProgressWeek('build'),
        const PlanProgressWeek('base'),
        const PlanProgressWeek('build'),
        const PlanProgressWeek('taper'),
        const PlanProgressWeek('peak'),
      ];
      expect(orderedPlanPhases(weeks), ['base', 'build', 'peak', 'taper']);
    });

    test('empty plan yields no phases', () {
      expect(orderedPlanPhases(const []), <String>[]);
    });

    test('ignores unknown phase strings', () {
      expect(
        orderedPlanPhases(
            const [PlanProgressWeek('base'), PlanProgressWeek('mystery')]),
        ['base'],
      );
    });
  });

  group('longestCompletedLongRunMetres', () {
    test('null when no long run is completed', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 25000, completedRunId: null),
        const LongRunWorkout(
            kind: 'easy',
            targetDistanceM: 8000,
            completedRunId: 'r1',
            manuallyCompleted: false),
      ];
      expect(longestCompletedLongRunMetres(workouts), null);
    });

    test('picks the max completed long-run target', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 18000, manuallyCompleted: true),
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 28000, manuallyCompleted: true),
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 32000, completedRunId: null),
      ];
      expect(longestCompletedLongRunMetres(workouts), 28000);
    });

    test('prefers actual run distance over the planned target', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 30000, completedRunId: 'r1'),
      ];
      final actual = {'r1': 31200.0};
      expect(longestCompletedLongRunMetres(workouts, actual), 31200);
    });

    test('falls back to target when the run is off-window', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 30000, completedRunId: 'r-old'),
      ];
      expect(longestCompletedLongRunMetres(workouts, const {}), 30000);
    });

    test('a zero-distance linked run falls back to the planned target', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 30000, completedRunId: 'r1'),
      ];
      // r1 is linked but recorded 0 m — fall back to the 30 km target.
      expect(longestCompletedLongRunMetres(workouts, {'r1': 0.0}), 30000);
    });

    test('a zero-distance linked run does not beat a real longer run', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 18000, completedRunId: 'r1'),
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 22000, completedRunId: 'r2'),
      ];
      final actual = {'r1': 0.0, 'r2': 24000.0};
      expect(longestCompletedLongRunMetres(workouts, actual), 24000);
    });

    test('ignores non-long completed workouts', () {
      final workouts = [
        const LongRunWorkout(
            kind: 'tempo', targetDistanceM: 40000, manuallyCompleted: true),
        const LongRunWorkout(
            kind: 'long', targetDistanceM: 12000, manuallyCompleted: true),
      ];
      expect(longestCompletedLongRunMetres(workouts), 12000);
    });
  });

  group('planDistanceBanked', () {
    test('sums planned over non-rest, completed over done', () {
      final workouts = [
        const DistanceWorkout(
            kind: 'easy', targetDistanceM: 8000, manuallyCompleted: true),
        const DistanceWorkout(
            kind: 'long', targetDistanceM: 20000, completedRunId: null),
        const DistanceWorkout(kind: 'rest', targetDistanceM: null),
      ];
      final r = planDistanceBanked(workouts);
      expect(r.completedMetres, 8000);
      expect(r.plannedMetres, 28000);
    });

    test('prefers actual run distance for completed workouts', () {
      final workouts = [
        const DistanceWorkout(
            kind: 'long', targetDistanceM: 20000, completedRunId: 'r1'),
      ];
      final r = planDistanceBanked(workouts, {'r1': 21400.0});
      expect(r.completedMetres, 21400);
      expect(r.plannedMetres, 20000);
    });

    test('a skipped workout leaves the planned denominator', () {
      final workouts = [
        const DistanceWorkout(
            kind: 'easy', targetDistanceM: 8000, manuallyCompleted: true),
        const DistanceWorkout(
            kind: 'long',
            targetDistanceM: 20000,
            skippedAt: '2026-07-01T00:00:00Z'),
      ];
      final r = planDistanceBanked(workouts);
      expect(r.completedMetres, 8000);
      expect(r.plannedMetres, 8000);
    });

    test('banked can exceed planned when the runner over-runs', () {
      final workouts = [
        const DistanceWorkout(
            kind: 'long', targetDistanceM: 20000, completedRunId: 'r1'),
      ];
      final r = planDistanceBanked(workouts, {'r1': 24000.0});
      expect(r.completedMetres, 24000);
      expect(r.plannedMetres, 20000);
    });

    test('a zero-distance linked run falls back to the planned target', () {
      final workouts = [
        const DistanceWorkout(
            kind: 'long', targetDistanceM: 20000, completedRunId: 'r1'),
      ];
      final r = planDistanceBanked(workouts, {'r1': 0.0});
      expect(r.completedMetres, 20000);
      expect(r.plannedMetres, 20000);
    });

    test('empty plan is zero / zero', () {
      final r = planDistanceBanked(const []);
      expect(r.completedMetres, 0);
      expect(r.plannedMetres, 0);
    });
  });
}
