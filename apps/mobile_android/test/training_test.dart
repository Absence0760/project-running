// Mirrors apps/web/src/lib/training.test.ts. These two suites must stay in
// sync — the Dart engine is expected to produce the same paces and phase
// assignments as the TS engine for the same inputs.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/training.dart';

void main() {
  group('walk_run workout kind (#22)', () {
    test('walk_run round-trips through fromDb / dbValue / label', () {
      // Mirrors the WORKOUT_KIND_LABEL.walk_run test in training.test.ts.
      expect(workoutKindFromDb('walk_run'), WorkoutKind.walkRun);
      expect(workoutKindDbValue(WorkoutKind.walkRun), 'walk_run');
      expect(workoutKindLabel(WorkoutKind.walkRun), 'Walk-run');
    });
  });

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

    // Persona-hunt Round 3 finding Woman #3 — gender calibration.
    // Mirror of `pacesFromGoalPace: female calibration ...` + companion
    // tests in `apps/web/src/lib/training.test.ts`. Keep both suites
    // in lockstep — `shared-library-syncer` agent flags divergence.
    test('omitting gender returns the existing (male-curve) values', () {
      final noGender = pacesFromGoalPace(240);
      final explicitNull = pacesFromGoalPace(240, null);
      final explicitMale = pacesFromGoalPace(240, 'male');
      expect(noGender.easy, explicitNull.easy);
      expect(noGender.easy, explicitMale.easy);
      expect(noGender.repetition, explicitMale.repetition);
    });

    test('female calibration shifts every band ~3% slower', () {
      final male = pacesFromGoalPace(240);
      final female = pacesFromGoalPace(240, 'female');
      expect(female.easy > male.easy, isTrue);
      expect(female.marathon > male.marathon, isTrue);
      expect(female.tempo > male.tempo, isTrue);
      expect(female.interval > male.interval, isTrue);
      expect(female.repetition > male.repetition, isTrue);
      final ratio = female.easy / male.easy;
      expect(ratio > 1.02 && ratio < 1.05, isTrue,
          reason: 'female easy / male easy ratio out of 2-5% band: $ratio');
    });

    test('nonbinary falls back to the unmodified curve', () {
      final male = pacesFromGoalPace(240);
      final nb = pacesFromGoalPace(240, 'nonbinary');
      expect(nb.easy, male.easy);
      expect(nb.repetition, male.repetition);
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

    // Persona-hunt Intermediate #4: 3-day plans used to be all
    // long-run + easy with no quality work — basically a mileage
    // log, not a training plan. Pin the post-fix behaviour.
    test('3-day plan in base phase includes a tempo workout', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 3,
        goalTimeSec: 105 * 60,
      ));
      final base = plan.weeks.firstWhere((w) => w.phase == PlanPhase.base);
      final active =
          base.workouts.where((w) => w.kind != WorkoutKind.rest).toList();
      expect(active.length, 3);
      expect(active.any((w) => w.kind == WorkoutKind.long), isTrue);
      expect(
        active.any((w) =>
            w.kind == WorkoutKind.tempo || w.kind == WorkoutKind.interval),
        isTrue,
        reason: '3-day base phase must have a tempo/interval — '
            'pre-fix it was all easy + long, not a training plan',
      );
    });

    test('3-day plan in build phase includes intervals', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceFull,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 3,
        goalTimeSec: 4 * 3600,
      ));
      final build = plan.weeks.firstWhere((w) => w.phase == PlanPhase.build);
      expect(
        build.workouts.any((w) => w.kind == WorkoutKind.interval),
        isTrue,
      );
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

  group('fmtKm — unit-pref aware', () {
    // training.dart's `fmtKm` is the single distance-format helper used
    // across the entire training-plan UI: workout_detail_screen,
    // plan_calendar, plan_detail_screen, plan_new_screen,
    // event_detail_screen. A regression that lost unit-awareness here
    // would silently mis-label every plan-related surface — pin both
    // modes + the null + digits contracts.

    tearDown(resetActivePreferencesForTest);

    test('null input returns the em-dash placeholder', () {
      // The plan UI passes `targetDistanceM` (nullable) directly —
      // null must NOT crash, must NOT render "null km" / "0.0 km".
      expect(fmtKm(null), '—');
    });

    test('km mode (default): "5.0 km" at default 1 decimal', () async {
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(fmtKm(5000), '5.0 km');
    });

    test('km mode: digits parameter controls precision', () async {
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(fmtKm(5234, 2), '5.23 km');
      expect(fmtKm(5234, 0), '5 km');
    });

    test('mi mode: "3.1 mi" at default 1 decimal', () async {
      // Headline regression net — mi-mode users used to see "5.0 km"
      // on the workout-detail / plan-calendar surfaces. Flipping the
      // pref must surface miles.
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      // 5000 m / 1609.344 = 3.107 → "3.1 mi"
      expect(fmtKm(5000), '3.1 mi');
    });

    test('mi mode: 0 km still renders 0.0 mi (not a crash)', () async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      expect(fmtKm(0), '0.0 mi');
    });

    test('mi mode honours digits parameter too', () async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      // Marathon: 42195m / 1609.344 = 26.219 mi → "26.22 mi" at 2 digits.
      expect(fmtKm(42195, 2), '26.22 mi');
    });

    test('switching pref mid-test re-evaluates (no caching)', () async {
      SharedPreferences.setMockInitialValues({'use_miles': false});
      final kmPrefs = Preferences();
      await kmPrefs.init();
      registerActivePreferences(kmPrefs);
      expect(fmtKm(5000), '5.0 km');

      // Flip and re-register. No memoisation in fmtKm → next call
      // reads the new pref.
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final miPrefs = Preferences();
      await miPrefs.init();
      registerActivePreferences(miPrefs);
      expect(fmtKm(5000), '3.1 mi');
    });
  });
}
