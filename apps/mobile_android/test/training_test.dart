// Mirrors apps/web/src/lib/training.test.ts. These two suites must stay in
// sync — the Dart engine is expected to produce the same paces and phase
// assignments as the TS engine for the same inputs.

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/training.dart';

void main() {
  group('vdotFromRace', () {
    test('20-minute 5k lands near VDOT 50', () {
      final v = vdotFromRace(5000, 20 * 60);
      expect((v - 49.8).abs() < 1.5, isTrue);
    });

    test('3-hour marathon lands near VDOT 54', () {
      final v = vdotFromRace(42195, 3 * 3600);
      expect((v - 54.3).abs() < 2, isTrue);
    });

    test('faster 5k produces higher VDOT', () {
      expect(vdotFromRace(5000, 20 * 60) > vdotFromRace(5000, 30 * 60), isTrue);
    });
  });

  group('riegelPredict', () {
    test('identity for same distance', () {
      expect(riegelPredict(5000, 1234, 5000), 1234);
    });

    test('20-min 5k projects near 41-42 min 10k', () {
      final t10k = riegelPredict(5000, 20 * 60, 10000);
      expect((t10k - 41.7 * 60).abs() < 60, isTrue);
    });
  });

  group('pacesFromGoalPace', () {
    test('zones are ordered slow → fast', () {
      final p = pacesFromGoalPace(240);
      expect(p.easy > p.marathon, isTrue);
      expect(p.marathon > p.tempo, isTrue);
      expect(p.tempo > p.interval, isTrue);
      expect(p.interval > p.repetition, isTrue);
    });

    test('4:00/km goal yields easy in 4:30-5:15 band', () {
      final p = pacesFromGoalPace(240);
      expect(p.easy >= 270 && p.easy <= 315, isTrue);
    });
  });

  group('resolveTrainingPaces', () {
    test('recent 5k beats goal time as anchor', () {
      final withRecent = resolveTrainingPaces(
        goalDistanceM: 5000,
        goalTimeSec: 19 * 60 + 59,
        recent5kSec: 25 * 60,
      );
      final goalOnly = resolveTrainingPaces(
        goalDistanceM: 5000,
        goalTimeSec: 19 * 60 + 59,
      );
      expect(withRecent.easy > goalOnly.easy, isTrue);
    });

    test('fallback without any anchor still produces a valid pace set', () {
      final p = resolveTrainingPaces(goalDistanceM: 10000);
      expect(p.easy > 0, isTrue);
      expect(p.interval > 0, isTrue);
    });
  });

  group('phaseFor', () {
    test('16-week plan is ~30/40/20/10 base/build/peak/taper', () {
      final counts = <PlanPhase, int>{};
      for (var i = 0; i < 16; i++) {
        counts[phaseFor(i, 16)] = (counts[phaseFor(i, 16)] ?? 0) + 1;
      }
      expect(counts[PlanPhase.race], 1);
      expect(counts[PlanPhase.base]! >= 4 && counts[PlanPhase.base]! <= 5, isTrue);
    });

    test('final week is always race', () {
      for (final total in [4, 8, 12, 16, 20]) {
        expect(phaseFor(total - 1, total), PlanPhase.race);
      }
    });
  });

  group('generatePlan', () {
    test('produces the requested number of weeks', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 4,
        goalTimeSec: 90 * 60,
      ));
      expect(plan.weeks.length, defaultPlanWeeks(GoalEvent.distanceHalf));
    });

    test('4-day plan has exactly 4 runs in base week', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 4,
        goalTimeSec: 45 * 60,
      ));
      final w0 = plan.weeks.first;
      final active = w0.workouts.where((w) => w.kind != WorkoutKind.rest).toList();
      expect(active.length, 4);
      expect(active.any((w) => w.kind == WorkoutKind.long), isTrue);
    });

    test('taper < peak by volume', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceFull,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 5,
        goalTimeSec: 4 * 3600,
      ));
      final peak = plan.weeks.firstWhere((w) => w.phase == PlanPhase.peak);
      final taper = plan.weeks.firstWhere((w) => w.phase == PlanPhase.taper);
      expect(peak.targetVolumeM > taper.targetVolumeM, isTrue);
    });

    test('race week ends with a race-kind workout', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 4,
        goalTimeSec: 25 * 60,
      ));
      final raceWeek = plan.weeks.last;
      expect(raceWeek.phase, PlanPhase.race);
      expect(raceWeek.workouts.any((w) => w.kind == WorkoutKind.race), isTrue);
    });

    test('build-phase intervals have a structure with repeats', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 5,
        goalTimeSec: 95 * 60,
      ));
      final interval = plan.weeks
          .expand((w) => w.workouts)
          .firstWhere((w) => w.kind == WorkoutKind.interval);
      expect(interval.structure, isNotNull);
      expect(interval.structure!.repeats, isNotNull);
    });

    test('no recent5k + no goal still produces a plan with null vdot', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 3,
      ));
      expect(plan.weeks.isNotEmpty, isTrue);
      expect(plan.vdot, isNull);
      expect(plan.paces.easy > 0, isTrue);
    });

    test(
        'every generated workout has a non-null kind across goals and days/week',
        () {
      // The DB enforces NOT NULL on plan_workouts.kind. The TS twin has a
      // regression test for the same invariant; keep both in sync so a
      // future edit to either engine can't silently produce kind-less
      // workouts (race week + sparse quality allocation were the trigger
      // on the web side).
      for (final combo in [
        (GoalEvent.distance5k, 8),
        (GoalEvent.distance10k, 12),
        (GoalEvent.distanceHalf, 16),
        (GoalEvent.distanceFull, 32),
      ]) {
        for (final dpw in [3, 4, 5, 6, 7]) {
          final plan = generatePlan(GeneratePlanInput(
            goalEvent: combo.$1,
            startDate: DateTime(2026, 3, 30),
            daysPerWeek: dpw,
            goalTimeSec: 3 * 3600,
            recent5kSec: 22 * 60,
            weeks: combo.$2,
          ));
          for (final w in plan.weeks) {
            for (final wo in w.workouts) {
              // ignore: unnecessary_null_comparison — documents the invariant
              expect(wo.kind, isNotNull,
                  reason:
                      'null kind in ${combo.$1} ${combo.$2}w × $dpw/wk at week ${w.weekIndex}');
            }
          }
        }
      }
    });
  });
}
