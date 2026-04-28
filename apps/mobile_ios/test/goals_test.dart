import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/goals.dart';

void main() {
  // Wednesday noon mid-week — gives both elapsed and remaining period
  // time for "ahead/behind pace" feedback to exercise both branches.
  final now = DateTime(2026, 4, 15, 12); // Wed 12:00 local

  Run makeRun({
    String id = 'r',
    required DateTime startedAt,
    double distance = 5000,
    Duration duration = const Duration(minutes: 25),
    String? activityType,
  }) {
    return Run(
      id: id,
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distance,
      track: const [],
      source: RunSource.app,
      metadata: activityType != null ? {'activity_type': activityType} : null,
    );
  }

  TargetProgress targetOf(GoalProgress progress, GoalTargetKind kind) {
    return progress.targets.firstWhere((t) => t.kind == kind);
  }

  group('period bounds', () {
    test('week start is Monday 00:00 local', () {
      expect(
        goalPeriodStart(GoalPeriod.week, now),
        DateTime(2026, 4, 13),
      );
    });

    test('week end is the following Monday 00:00 local', () {
      expect(
        goalPeriodEnd(GoalPeriod.week, now),
        DateTime(2026, 4, 20),
      );
    });

    test('month end wraps into next year for December', () {
      final dec = DateTime(2026, 12, 15);
      expect(goalPeriodStart(GoalPeriod.month, dec), DateTime(2026, 12, 1));
      expect(goalPeriodEnd(GoalPeriod.month, dec), DateTime(2027, 1, 1));
    });
  });

  group('distance target', () {
    const goal = RunGoal(
      id: 'g1',
      period: GoalPeriod.week,
      distanceMetres: 20000,
    );

    test('empty run list → 0% and "log a run" feedback', () {
      final p = evaluateGoal(goal, const [], now);
      final t = targetOf(p, GoalTargetKind.distance);
      expect(t.current, 0);
      expect(t.percent, 0);
      expect(t.complete, isFalse);
      expect(t.feedback, 'Log a run to start tracking');
      expect(p.complete, isFalse);
    });

    test('runs outside the period are ignored', () {
      final p = evaluateGoal(goal, [
        makeRun(startedAt: DateTime(2026, 4, 6, 9), distance: 12000),
      ], now);
      expect(targetOf(p, GoalTargetKind.distance).current, 0);
    });

    test('sums distances across the period', () {
      final p = evaluateGoal(goal, [
        makeRun(id: 'a', startedAt: DateTime(2026, 4, 13, 8), distance: 5000),
        makeRun(id: 'b', startedAt: DateTime(2026, 4, 14, 9), distance: 5000),
      ], now);
      final t = targetOf(p, GoalTargetKind.distance);
      expect(t.current, 10000);
      expect(t.percent, closeTo(0.5, 0.001));
      expect(t.complete, isFalse);
    });

    test('hitting the target reports Goal reached', () {
      final p = evaluateGoal(goal, [
        makeRun(startedAt: DateTime(2026, 4, 13, 8), distance: 20000),
      ], now);
      final t = targetOf(p, GoalTargetKind.distance);
      expect(t.percent, 1);
      expect(t.complete, isTrue);
      expect(t.feedback, 'Goal reached');
      expect(p.complete, isTrue);
    });

    test('ahead of pace → ahead feedback', () {
      final p = evaluateGoal(goal, [
        makeRun(startedAt: DateTime(2026, 4, 13, 8), distance: 15000),
      ], now);
      expect(
        targetOf(p, GoalTargetKind.distance).feedback,
        contains('ahead of pace'),
      );
    });

    test('behind pace → "X km to go" feedback', () {
      final p = evaluateGoal(goal, [
        makeRun(startedAt: DateTime(2026, 4, 13, 8), distance: 2000),
      ], now);
      expect(
        targetOf(p, GoalTargetKind.distance).feedback,
        contains('to go'),
      );
    });
  });

  group('avg pace target', () {
    const goal = RunGoal(
      id: 'g2',
      period: GoalPeriod.week,
      avgPaceSecPerKm: 300, // 5:00 /km
    );

    test('only cycling in period → 0% with running-activity message', () {
      final p = evaluateGoal(goal, [
        makeRun(
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 20000,
          duration: const Duration(minutes: 60),
          activityType: 'cycle',
        ),
      ], now);
      final t = targetOf(p, GoalTargetKind.avgPace);
      expect(t.current, 0);
      expect(t.percent, 0);
      expect(t.feedback, 'Log a running activity to track pace');
    });

    test('meeting target exactly → complete', () {
      final p = evaluateGoal(goal, [
        makeRun(
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 10000,
          duration: const Duration(minutes: 50), // 5:00 /km exact
        ),
      ], now);
      final t = targetOf(p, GoalTargetKind.avgPace);
      expect(t.complete, isTrue);
      expect(t.percent, 1.0);
      expect(t.feedback, 'Goal reached');
    });

    test('faster than target → complete', () {
      final p = evaluateGoal(goal, [
        makeRun(
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 10000,
          duration: const Duration(minutes: 45), // 4:30 /km
        ),
      ], now);
      expect(targetOf(p, GoalTargetKind.avgPace).complete, isTrue);
    });

    test('slower than target → proportional percent + off-target feedback', () {
      final p = evaluateGoal(goal, [
        makeRun(
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 10000,
          duration: const Duration(minutes: 60), // 6:00 /km
        ),
      ], now);
      final t = targetOf(p, GoalTargetKind.avgPace);
      expect(t.complete, isFalse);
      expect(t.percent, closeTo(0.833, 0.01));
      expect(t.feedback, contains('off target'));
    });

    test('distance-weighted across multiple runs; cycling excluded', () {
      final p = evaluateGoal(goal, [
        makeRun(
          id: 'a',
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 5000,
          duration: const Duration(minutes: 25), // 5:00 /km
        ),
        makeRun(
          id: 'b',
          startedAt: DateTime(2026, 4, 14, 8),
          distance: 5000,
          duration: const Duration(minutes: 30), // 6:00 /km → weighted 5:30 /km
        ),
        makeRun(
          id: 'c',
          startedAt: DateTime(2026, 4, 15, 8),
          distance: 30000,
          duration: const Duration(minutes: 60),
          activityType: 'cycle',
        ),
      ], now);
      final t = targetOf(p, GoalTargetKind.avgPace);
      expect(t.current, closeTo(330, 1));
    });
  });

  group('run count target', () {
    const goal = RunGoal(
      id: 'g3',
      period: GoalPeriod.week,
      runCount: 4,
    );

    test('counts runs in period', () {
      final p = evaluateGoal(goal, [
        makeRun(id: 'a', startedAt: DateTime(2026, 4, 13, 8)),
        makeRun(id: 'b', startedAt: DateTime(2026, 4, 14, 8)),
      ], now);
      final t = targetOf(p, GoalTargetKind.runCount);
      expect(t.current, 2);
      expect(t.percent, closeTo(0.5, 0.001));
      expect(t.feedback, '2 to go');
    });
  });

  group('time target', () {
    const goal = RunGoal(
      id: 'g4',
      period: GoalPeriod.week,
      timeSeconds: 18000, // 5 h
    );

    test('accumulates seconds', () {
      final p = evaluateGoal(goal, [
        makeRun(
          startedAt: DateTime(2026, 4, 13, 8),
          duration: const Duration(minutes: 60),
        ),
      ], now);
      final t = targetOf(p, GoalTargetKind.time);
      expect(t.current, 3600);
      expect(t.percent, closeTo(0.2, 0.001));
    });
  });

  group('multi-target goal', () {
    const goal = RunGoal(
      id: 'combo',
      period: GoalPeriod.week,
      distanceMetres: 20000,
      avgPaceSecPerKm: 300,
      runCount: 4,
    );

    test('evaluates each target independently', () {
      final p = evaluateGoal(goal, [
        makeRun(
          id: 'a',
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 10000,
          duration: const Duration(minutes: 50), // 5:00 /km
        ),
      ], now);
      expect(p.targets.length, 3);
      expect(targetOf(p, GoalTargetKind.distance).current, 10000);
      expect(targetOf(p, GoalTargetKind.avgPace).complete, isTrue);
      expect(targetOf(p, GoalTargetKind.runCount).current, 1);
      // Only pace is complete — overall percent should be the mean of the three.
      expect(p.complete, isFalse);
      expect(
        p.overallPercent,
        closeTo((0.5 + 1.0 + 0.25) / 3, 0.01),
      );
    });

    test('overall complete only when every target is met', () {
      final p = evaluateGoal(goal, [
        makeRun(
          id: 'a',
          startedAt: DateTime(2026, 4, 13, 8),
          distance: 5000,
          duration: const Duration(minutes: 25),
        ),
        makeRun(
          id: 'b',
          startedAt: DateTime(2026, 4, 14, 8),
          distance: 5000,
          duration: const Duration(minutes: 25),
        ),
        makeRun(
          id: 'c',
          startedAt: DateTime(2026, 4, 15, 8),
          distance: 5000,
          duration: const Duration(minutes: 25),
        ),
        makeRun(
          id: 'd',
          startedAt: DateTime(2026, 4, 16, 8),
          distance: 5000,
          duration: const Duration(minutes: 25),
        ),
      ], now);
      expect(p.complete, isTrue);
      for (final t in p.targets) {
        expect(t.complete, isTrue, reason: '${t.kind} should be complete');
      }
    });
  });

  group('RunGoal JSON', () {
    test('round-trips a multi-target goal', () {
      const goal = RunGoal(
        id: 'abc',
        period: GoalPeriod.month,
        distanceMetres: 20000,
        avgPaceSecPerKm: 300,
      );
      final copy = RunGoal.fromJson(goal.toJson());
      expect(copy.id, goal.id);
      expect(copy.period, goal.period);
      expect(copy.distanceMetres, goal.distanceMetres);
      expect(copy.avgPaceSecPerKm, goal.avgPaceSecPerKm);
      expect(copy.timeSeconds, isNull);
      expect(copy.runCount, isNull);
    });

    test('legacy single-target json migrates into the matching field', () {
      final legacy = {
        'id': 'xyz',
        'type': 'avgPace',
        'period': 'week',
        'target': 300.0,
      };
      final g = RunGoal.fromJson(legacy);
      expect(g.id, 'xyz');
      expect(g.period, GoalPeriod.week);
      expect(g.avgPaceSecPerKm, 300);
      expect(g.distanceMetres, isNull);
      expect(g.timeSeconds, isNull);
      expect(g.runCount, isNull);
    });
  });
}
