// Mirrors apps/web/src/lib/training.test.ts. These two suites must stay in
// sync — the Dart engine is expected to produce the same paces and phase
// assignments as the TS engine for the same inputs.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/preferences.dart';
import '../lib/training.dart';

void main() {
  group('walk_run workout kind (#22)', () {
    test('walk_run round-trips through fromDb / dbValue', () {
      // The display label moved to training_labels.dart (localized) — see
      // training_labels_test.dart. This pins the pure db round-trip.
      expect(workoutKindFromDb('walk_run'), WorkoutKind.walkRun);
      expect(workoutKindDbValue(WorkoutKind.walkRun), 'walk_run');
    });

    test('no-anchor 5k plan ramps gentler than an anchored one (#23)', () {
      // Mirrors the no-anchor volume test in training.test.ts.
      double weekVol(GeneratedPlan p, int i) => p.weeks[i].workouts
          .fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0));
      int activeDays(GeneratedPlan p, int i) => p.weeks[i].workouts
          .where((w) => w.kind != WorkoutKind.rest)
          .length;
      final base = GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 4,
      );
      final anchored = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 4,
        recent5kSec: 22 * 60,
      ));
      final noAnchor = generatePlan(base);
      expect(activeDays(noAnchor, 0), 4);
      expect(weekVol(noAnchor, 0) < weekVol(anchored, 0), isTrue);
      expect(weekVol(noAnchor, 0) < 15000, isTrue);
    });

    // Persona round-5 runner-new. Mirrors the graduation-week tests in
    // training.test.ts. A default 5k beginner plan arrives with weeks=8
    // against a 9-stage progression; the engine floor keeps the graduation
    // week from being truncated.
    test('walkRunDefaultWeeks matches the full progression length', () {
      expect(walkRunDefaultWeeks(), 9);
    });

    test('generatePlan(beginnerWalkRun, weeks=8) keeps the graduation week', () {
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
        weeks: 8,
        beginnerWalkRun: true,
      ));
      expect(plan.weeks.length, 9);
      final wkLast = plan.weeks.last.workouts
          .firstWhere((w) => w.kind == WorkoutKind.walkRun);
      expect(wkLast.structure!.repeats!['count'], 1);
      expect(wkLast.structure!.repeats!.containsKey('recovery_duration_s'),
          isFalse);
      expect(wkLast.notes, contains('Graduation week'));
    });

    // Persona round-5 runner-comeback. Mirrors the pacesAreFallback test in
    // training.test.ts.
    test('pacesAreFallback is true with no anchor, false with an anchor', () {
      final noAnchor = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
      ));
      expect(noAnchor.pacesAreFallback, isTrue);

      final withGoal = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
        goalTimeSec: 45 * 60,
      ));
      expect(withGoal.pacesAreFallback, isFalse);

      final withRecent = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance10k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
        recent5kSec: 24 * 60,
      ));
      expect(withRecent.pacesAreFallback, isFalse);
      expect(noAnchor.paces.easy > 0, isTrue);
      expect(noAnchor.weeks.isNotEmpty, isTrue);
    });

    test('generatePlan(beginnerWalkRun) yields a 9-week walk_run plan', () {
      // Mirrors generatePlan(beginnerWalkRun) in training.test.ts.
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 3,
        beginnerWalkRun: true,
      ));
      expect(plan.weeks.length, 9);
      final sessions = plan.weeks
          .expand((w) => w.workouts)
          .where((w) => w.kind != WorkoutKind.rest)
          .toList();
      expect(sessions.length, 9 * 3);
      expect(sessions.every((w) => w.kind == WorkoutKind.walkRun), isTrue);

      final wk1 = plan.weeks[0].workouts
          .firstWhere((w) => w.kind == WorkoutKind.walkRun);
      expect(wk1.structure!.repeats!['recovery_pace'], 'walk');
      expect(wk1.structure!.repeats!['duration_s'], 60);
      expect(wk1.structure!.repeats!['recovery_duration_s'], 90);
      expect(wk1.structure!.repeats!['count'], 8);

      final wk9 = plan.weeks[8].workouts
          .firstWhere((w) => w.kind == WorkoutKind.walkRun);
      expect(wk9.structure!.repeats!['count'], 1);
      expect(wk9.structure!.repeats!.containsKey('recovery_duration_s'), isFalse);
      // #273: the final week is a graduation, not a race — a beginner walk-run
      // plan has no goal race, so labelling it 'race' ("Race week") misleads.
      expect(plan.weeks[8].phase, PlanPhase.graduation);
      expect(plan.weeks[0].phase, PlanPhase.build);
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

  group('predictionConfidence', () {
    const fiveK = 5000.0;
    const tenK = 10000.0;
    const marathon = 42195.0;

    test('high when distance is close, effort recent, well-sampled', () {
      final q = predictionConfidence(
        knownDistanceM: tenK,
        targetDistanceM: fiveK,
        daysSinceBest: 10,
        qualifyingRunCount: 5,
      );
      expect(q.confidence, PredictionConfidence.high);
      expect(q.reason, PredictionReason.similar);
    });

    test('low + extrapolated projecting a marathon off a 5k', () {
      final q = predictionConfidence(
        knownDistanceM: fiveK,
        targetDistanceM: marathon,
        daysSinceBest: 5,
        qualifyingRunCount: 8,
      );
      expect(q.confidence, PredictionConfidence.low);
      expect(q.reason, PredictionReason.extrapolated);
    });

    test('moderate + stale when the only recent effort is weeks old', () {
      final q = predictionConfidence(
        knownDistanceM: fiveK,
        targetDistanceM: fiveK,
        daysSinceBest: 45,
        qualifyingRunCount: 4,
      );
      expect(q.confidence, PredictionConfidence.moderate);
      expect(q.reason, PredictionReason.stale);
    });

    test('moderate + limited when close + recent but thinly sampled', () {
      final q = predictionConfidence(
        knownDistanceM: fiveK,
        targetDistanceM: fiveK,
        daysSinceBest: 7,
        qualifyingRunCount: 1,
      );
      expect(q.confidence, PredictionConfidence.moderate);
      expect(q.reason, PredictionReason.limited);
    });

    test('moderate + extrapolated for a meaningful but not extreme gap', () {
      final q = predictionConfidence(
        knownDistanceM: tenK,
        targetDistanceM: 21097,
        daysSinceBest: 10,
        qualifyingRunCount: 5,
      );
      expect(q.confidence, PredictionConfidence.moderate);
      expect(q.reason, PredictionReason.extrapolated);
    });

    test('low + stale when the anchoring effort is over two months old', () {
      final q = predictionConfidence(
        knownDistanceM: fiveK,
        targetDistanceM: fiveK,
        daysSinceBest: 75,
        qualifyingRunCount: 4,
      );
      expect(q.confidence, PredictionConfidence.low);
      expect(q.reason, PredictionReason.stale);
    });

    test('low + limited with no qualifying runs', () {
      final q = predictionConfidence(
        knownDistanceM: fiveK,
        targetDistanceM: fiveK,
        daysSinceBest: 5,
        qualifyingRunCount: 0,
      );
      expect(q.confidence, PredictionConfidence.low);
      expect(q.reason, PredictionReason.limited);
    });

    test('>60d anchor stays low even when the distance gap is also far', () {
      // A close+stale(75d) anchor is already low/stale (test above). Adding a
      // second degrading factor (a far distance gap) must NOT improve
      // confidence to moderate — guards against a confidence inversion where a
      // doubly-bad prediction outranks a singly-bad one.
      final q = predictionConfidence(
        knownDistanceM: tenK,
        targetDistanceM: 21097, // 2.1x — past the close band, within the 4x cap
        daysSinceBest: 75,
        qualifyingRunCount: 5,
      );
      expect(q.confidence, PredictionConfidence.low);
      expect(q.reason, PredictionReason.stale);
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

    test('prefer_not_to_say falls back to the unmodified curve', () {
      final male = pacesFromGoalPace(240);
      final pnts = pacesFromGoalPace(240, 'prefer_not_to_say');
      expect(pnts.easy, male.easy);
      expect(pnts.repetition, male.repetition);
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

    test('a zero recent5kSec/goalTimeSec is treated as no anchor (twin parity)', () {
      // Regression: `0 != null` ran Riegel on a 0 time → goalPace 0 → every band
      // 0:00/km + isFallback wrongly false. A 0 anchor is "no usable time" and
      // must fall through to the conservative fallback, matching the web twin.
      final zeroRecent = resolveTrainingPacesWithMeta(
        goalDistanceM: 10000,
        recent5kSec: 0,
      );
      expect(zeroRecent.isFallback, isTrue);
      expect(zeroRecent.paces.easy > 0, isTrue);
      expect(zeroRecent.paces.interval > 0, isTrue);

      final zeroGoal = resolveTrainingPacesWithMeta(
        goalDistanceM: 10000,
        goalTimeSec: 0,
      );
      expect(zeroGoal.isFallback, isTrue);
      expect(zeroGoal.paces.easy > 0, isTrue);

      final fallback = resolveTrainingPacesWithMeta(goalDistanceM: 10000);
      expect(zeroRecent.paces.easy, fallback.paces.easy);
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

    test('every total from the editor floor up seats a taper and sums exact', () {
      const order = [
        PlanPhase.base,
        PlanPhase.build,
        PlanPhase.peak,
        PlanPhase.taper,
        PlanPhase.race,
      ];
      // 4 is the plan editor's minimum on the total-weeks override.
      for (var total = 4; total <= 30; total++) {
        final seq = [for (var i = 0; i < total; i++) phaseFor(i, total)];
        expect(seq.length, total, reason: 'total $total: every week lands in a phase');
        for (var i = 1; i < seq.length; i++) {
          expect(order.indexOf(seq[i]) >= order.indexOf(seq[i - 1]), isTrue,
              reason: 'total $total: phases must not run backwards ($seq)');
        }
        expect(seq.where((p) => p == PlanPhase.race).length, 1,
            reason: 'total $total: one race week');
        expect(seq.contains(PlanPhase.taper), isTrue,
            reason: 'total $total: taper starved ($seq)');
        // Four phases need four non-race weeks; below that one must go empty,
        // and the taper asserted above is never the one dropped.
        if (total >= 5) {
          for (final phase in [PlanPhase.base, PlanPhase.build, PlanPhase.peak]) {
            expect(seq.contains(phase), isTrue,
                reason: 'total $total: $phase starved ($seq)');
          }
        }
      }
    });

    test('a 10-week plan tapers instead of peaking into race week', () {
      // 10 and 5 floored to exactly the non-race block (3+4+2 and 1+2+1), so
      // the taper got nothing and the 100 % peak week sat against race day.
      expect(phaseFor(8, 10), PlanPhase.taper);
      expect(phaseFor(3, 5), PlanPhase.taper);
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

    test('7-day plan runs all 7 days (no hardcoded Monday rest)', () {
      // Both wizards offer 3–7 days/week. Monday was hardwired as a rest day,
      // so a runner who picked 7 silently got a 6-day plan — the requested 7th
      // day vanished. A 7-day plan must have zero rest days; 6 keeps exactly 1.
      final seven = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 7,
        recent5kSec: 22 * 60,
        weeks: 12,
      ));
      // The race week is a deliberate exception: the race itself stands in for
      // the long run and dwarfs the light race-week budget, so shakeout days
      // collapse to what the remaining budget supports (#326) rather than
      // padding with filler runs. The "no hardcoded Monday rest" guarantee
      // still applies to every training-load week.
      for (final week in seven.weeks) {
        if (week.phase == PlanPhase.race) continue;
        final active =
            week.workouts.where((w) => w.kind != WorkoutKind.rest).length;
        final rest =
            week.workouts.where((w) => w.kind == WorkoutKind.rest).length;
        expect(active, 7, reason: '7-day week ${week.weekIndex} active=$active');
        expect(rest, 0, reason: '7-day week ${week.weekIndex} rest=$rest');
      }
      final six = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 5, 3),
        daysPerWeek: 6,
        recent5kSec: 22 * 60,
        weeks: 12,
      ));
      for (final week in six.weeks) {
        if (week.phase == PlanPhase.race) continue;
        final active =
            week.workouts.where((w) => w.kind != WorkoutKind.rest).length;
        expect(active, 6, reason: '6-day week ${week.weekIndex} active=$active');
      }
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

    test('stated weekly volume equals the sum of emitted workout distances',
        () {
      // Headline targetVolumeM must match what the week prescribes. Pre-fix
      // it was weeklyKm * 1000, overshooting the rounded/floored per-day
      // distances by ~25-70% on small-volume plans. Mirrors training.test.ts.
      for (final goalEvent in [GoalEvent.distance5k, GoalEvent.distanceHalf]) {
        for (final daysPerWeek in [3, 4, 5]) {
          final plan = generatePlan(GeneratePlanInput(
            goalEvent: goalEvent,
            startDate: DateTime(2026, 5, 3),
            daysPerWeek: daysPerWeek,
            goalTimeSec:
                goalEvent == GoalEvent.distance5k ? 25 * 60 : 105 * 60,
          ));
          for (final week in plan.weeks) {
            final emitted = week.workouts
                .fold<double>(0, (s, w) => s + (w.targetDistanceM ?? 0));
            expect(week.targetVolumeM, emitted,
                reason:
                    '$goalEvent ${daysPerWeek}d week ${week.weekIndex}: stated '
                    '${week.targetVolumeM} should equal emitted $emitted');
          }
        }
      }
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

    // #326: the race week reserved a quality slot the race phase never fills and
    // costed the Sunday slot as a nominal long run while emitting the full race
    // distance, so the week ballooned back toward peak volume. Mirrors
    // training.test.ts.
    test('race week volume stays a light shakeout above the race (#326)', () {
      final cfgs = [
        (goal: GoalEvent.distanceHalf, days: 5, time: 90 * 60),
        (goal: GoalEvent.distanceFull, days: 7, time: 4 * 3600),
      ];
      for (final cfg in cfgs) {
        final plan = generatePlan(GeneratePlanInput(
          goalEvent: cfg.goal,
          startDate: DateTime(2026, 8, 1),
          daysPerWeek: cfg.days,
          goalTimeSec: cfg.time,
        ));
        final raceWeek = plan.weeks.last;
        expect(raceWeek.phase, PlanPhase.race);
        expect(raceWeek.targetVolumeM <= plan.goalDistanceM * 1.15, isTrue,
            reason:
                'race week ${raceWeek.targetVolumeM}m must be <= goal*1.15 '
                '(${plan.goalDistanceM * 1.15}m) for ${cfg.goal} ${cfg.days}d');
        expect(raceWeek.targetVolumeM >= plan.goalDistanceM, isTrue,
            reason: 'race week volume still includes the full race distance');
      }
    });

    // #326: base/taper weeks over-reserved the empty qualityB slot, dividing the
    // easy budget over too few days and overshooting the week's weeklyKm ramp.
    // Mirrors training.test.ts.
    test('base/taper 5-day weeks do not exceed their weeklyKm target (#326)', () {
      const days = 5;
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 8, 1),
        daysPerWeek: days,
        goalTimeSec: 95 * 60,
      ));
      final total = plan.weeks.length;
      final peakKm = peakVolumeKm(plan.goalDistanceM, days, true);
      // Each easy day is rounded to a whole km, so the week can round up by ~0.5
      // km per easy day — far under the 25-70% overshoot the bug produced.
      const roundingHeadroomM = days * 500;
      for (final week in plan.weeks) {
        if (week.phase != PlanPhase.base && week.phase != PlanPhase.taper) {
          continue;
        }
        final weeklyKm =
            (peakKm * mileageFraction(week.weekIndex, total, week.phase))
                .round();
        expect(week.targetVolumeM <= weeklyKm * 1000 + roundingHeadroomM, isTrue,
            reason:
                '${week.phase} week ${week.weekIndex} volume '
                '${week.targetVolumeM}m exceeds its ${weeklyKm * 1000}m budget');
      }
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

    // DST parity guard. Mirrors web's `addDays` (setDate-based, calendar-safe).
    // `startDate.add(Duration(days: n))` adds n×24h of absolute elapsed time,
    // so on a device in a DST-observing timezone (e.g. America/New_York) the
    // extra hour inserted at the Nov 2 fall-back rolls the calendar day back by
    // one from week ~4 on — mobile-generated scheduled_dates then disagree with
    // web's for the same inputs. The engine must step dates through the
    // year/month/day constructor so every scheduled_date is calendar-correct
    // regardless of the host timezone.
    test('plan dates step by calendar days across a DST transition', () {
      final start = DateTime(2025, 10, 20); // Mon; US fall-back is 2025-11-02
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceFull,
        startDate: start,
        daysPerWeek: 5,
        recent5kSec: 22 * 60,
        weeks: 16,
      ));
      // Week index 4 starts start + 28 calendar days = 2025-11-17 (NOT -16).
      final wk4Start = plan.weeks[4].workouts.first.scheduledDate;
      expect(toIsoDate(wk4Start), '2025-11-17');

      // Every workout's date must equal the calendar-correct date for its
      // (weekIndex, dayOffset) — computed via the DST-safe constructor.
      for (final week in plan.weeks) {
        for (var d = 0; d < week.workouts.length; d++) {
          final expected =
              DateTime(start.year, start.month, start.day + week.weekIndex * 7 + d);
          expect(toIsoDate(week.workouts[d].scheduledDate), toIsoDate(expected),
              reason: 'week ${week.weekIndex} day $d off calendar date');
        }
      }
      // End date is start + totalWeeks*7 - 1 calendar days.
      expect(toIsoDate(plan.endDate),
          toIsoDate(DateTime(start.year, start.month, start.day + 16 * 7 - 1)));
    });

    test('walk-run plan dates step by calendar days across a DST transition',
        () {
      final start = DateTime(2025, 10, 20);
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: start,
        daysPerWeek: 3,
        beginnerWalkRun: true,
      ));
      for (final week in plan.weeks) {
        for (var d = 0; d < week.workouts.length; d++) {
          final expected =
              DateTime(start.year, start.month, start.day + week.weekIndex * 7 + d);
          expect(toIsoDate(week.workouts[d].scheduledDate), toIsoDate(expected),
              reason: 'walk-run week ${week.weekIndex} day $d off calendar date');
        }
      }
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

    // ─────────── masters age-band calibration (#30) ───────────
    // Mirrors the masters tests in apps/web/src/lib/training.test.ts.

    test('isMastersAge: boundary 50 inclusive; null is not masters', () {
      expect(isMastersAge(49), isFalse);
      expect(isMastersAge(50), isTrue);
      expect(isMastersAge(72), isTrue);
      expect(isMastersAge(null), isFalse);
    });

    // Mirrors isWorkoutSkipped in apps/web/src/lib/training/training.test.ts.
    test('isWorkoutSkipped: only a stamped skippedAt reads as skipped', () {
      expect(isWorkoutSkipped(null), isFalse);
      expect(isWorkoutSkipped(DateTime.utc(2026, 6, 13, 10)), isTrue);
    });

    test('masters push the first quality day to 72h after the long run', () {
      const quality = {
        WorkoutKind.tempo,
        WorkoutKind.interval,
        WorkoutKind.marathonPace,
      };
      int? offset(GeneratedWeek w) {
        final start = w.workouts.first.scheduledDate;
        final q = w.workouts
            .where((x) => quality.contains(x.kind))
            .cast<GeneratedWorkout?>()
            .firstWhere((x) => true, orElse: () => null);
        if (q == null) return null;
        return q.scheduledDate.difference(start).inDays;
      }

      final standard = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 5,
        goalTimeSec: 100 * 60,
      ));
      final masters = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceHalf,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 5,
        goalTimeSec: 100 * 60,
        age: 58,
      ));
      final stdWeek = standard.weeks.firstWhere((w) => offset(w) != null);
      final mstWeek = masters.weeks.firstWhere((w) => offset(w) != null);
      expect(offset(stdWeek), 2);
      expect(offset(mstWeek), 3);
    });

    test('masters never schedule a quality day < 72h after the long run', () {
      const quality = {
        WorkoutKind.tempo,
        WorkoutKind.interval,
        WorkoutKind.marathonPace,
      };
      final masters = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceFull,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 5,
        recent5kSec: 24 * 60,
        age: 55,
      ));
      for (final w in masters.weeks) {
        final start = w.workouts.first.scheduledDate;
        for (final x in w.workouts.where((x) => quality.contains(x.kind))) {
          expect(x.scheduledDate.difference(start).inDays >= 3, isTrue);
        }
      }
    });

    test('masters step back volume every 3rd week, not every 4th', () {
      final masters = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distanceFull,
        startDate: DateTime(2026, 6, 7),
        daysPerWeek: 5,
        recent5kSec: 22 * 60,
        age: 60,
      ));
      if (masters.weeks.length >= 4 &&
          masters.weeks[2].phase != PlanPhase.taper) {
        expect(
          masters.weeks[2].targetVolumeM <= masters.weeks[1].targetVolumeM,
          isTrue,
        );
        expect(masters.weeks[2].notes, contains('Step-back'));
      }
    });
  });

  group('fmtHms', () {
    test('zero/null/negative render the em-dash placeholder', () {
      expect(fmtHms(0), '—');
      expect(fmtHms(null), '—');
      expect(fmtHms(-90), '—');
    });

    test('formats a positive duration', () {
      expect(fmtHms(90), '1:30');
      expect(fmtHms(3661), '1:01:01');
    });
  });

  group('generatePlan zero anchor (parity guard)', () {
    test('a zero anchor is treated as no anchor (no Infinity vdot)', () {
      final base = GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 4,
      );
      final zero = generatePlan(GeneratePlanInput(
        goalEvent: GoalEvent.distance5k,
        startDate: DateTime(2026, 6, 1),
        daysPerWeek: 4,
        recent5kSec: 0,
      ));
      final noAnchor = generatePlan(base);
      // Before the fix `0 != null` made this a real anchor: vdotFromRace(5000,
      // 0) → velocity = distance/0 = Infinity → non-finite VDOT.
      expect(zero.vdot, isNull);
      double weekVol(GeneratedPlan p, int i) => p.weeks[i].workouts
          .fold(0.0, (s, w) => s + (w.targetDistanceM ?? 0));
      expect(weekVol(zero, 0), weekVol(noAnchor, 0));
    });
  });

  test('the race workout is prescribed at the goal pace, at every distance', () {
    // The generator used to hand the week builder a goal pace reconstructed
    // from the derived `marathon` band: `paces.marathon * (goalDistance >=
    // 21000 ? 1 : 0.95)`. Since that band is `goalPace * 1.06`, the 0.95
    // roughly undid it on 5K/10K plans but the `1` left half + marathon plans
    // prescribing the race 6% slower than the runner's goal.
    final cases = <List<Object>>[
      [GoalEvent.distance5k, 1200, 5000.0],
      [GoalEvent.distance10k, 2700, 10000.0],
      [GoalEvent.distanceHalf, 6300, 21097.5],
      [GoalEvent.distanceFull, 12600, 42195.0],
    ];
    for (final c in cases) {
      final goalEvent = c[0] as GoalEvent;
      final goalTimeSec = c[1] as int;
      final distanceM = c[2] as double;
      final plan = generatePlan(GeneratePlanInput(
        goalEvent: goalEvent,
        goalTimeSec: goalTimeSec,
        startDate: DateTime(2026, 1, 5),
        daysPerWeek: 5,
        weeks: 16,
      ));
      final goalPace = goalTimeSec / (distanceM / 1000);
      final race = plan.weeks
          .expand((w) => w.workouts)
          .firstWhere((w) => w.kind == WorkoutKind.race);
      expect(race.targetPaceSecPerKm, isNotNull, reason: '$goalEvent');
      // Within a second per km — the only slack is integer sec/km rounding.
      expect((race.targetPaceSecPerKm! - goalPace).abs() <= 1, isTrue,
          reason: '$goalEvent: race pace ${race.targetPaceSecPerKm} '
              'should be goal pace ${goalPace.toStringAsFixed(1)}');
    }
  });

  test('marathon_pace sessions are prescribed at the goal pace, not the band', () {
    final plan = generatePlan(GeneratePlanInput(
      goalEvent: GoalEvent.distanceFull,
      goalTimeSec: 12600,
      startDate: DateTime(2026, 1, 5),
      daysPerWeek: 5,
      weeks: 16,
    ));
    final goalPace = 12600 / 42.195;
    final mp = plan.weeks
        .expand((w) => w.workouts)
        .where((w) => w.kind == WorkoutKind.marathonPace)
        .toList();
    expect(mp, isNotEmpty);
    for (final w in mp) {
      expect((w.targetPaceSecPerKm! - goalPace).abs() <= 1, isTrue,
          reason: 'marathon_pace ${w.targetPaceSecPerKm} should be goal pace');
      // The structure the workout runner executes must agree with the headline.
      expect(w.structure!.steady!['pace_sec_per_km'], w.targetPaceSecPerKm);
    }
  });

  test('a 10K plan keeps marathon_pace on the training band, not the goal pace', () {
    // The other side of the same branch: on a short-distance goal this session
    // is steady aerobic work at marathon *effort*, legitimately slower than
    // goal pace. Pinning it stops the fix above from over-reaching.
    final plan = generatePlan(GeneratePlanInput(
      goalEvent: GoalEvent.distance10k,
      goalTimeSec: 2700,
      startDate: DateTime(2026, 1, 5),
      daysPerWeek: 5,
      weeks: 16,
    ));
    final resolved = resolveTrainingPacesWithMeta(
      goalDistanceM: 10000,
      goalTimeSec: 2700,
    );
    final mp = plan.weeks
        .expand((w) => w.workouts)
        .where((w) => w.kind == WorkoutKind.marathonPace)
        .toList();
    expect(mp, isNotEmpty);
    for (final w in mp) {
      expect(w.targetPaceSecPerKm, resolved.paces.marathon);
      expect(w.targetPaceSecPerKm! > 270, isTrue,
          reason: 'slower than the 10K goal pace');
    }
  });

  test('the goal pace the bands derive from is returned, ungendered', () {
    final male = resolveTrainingPacesWithMeta(
        goalDistanceM: 42195, goalTimeSec: 12600);
    final female = resolveTrainingPacesWithMeta(
        goalDistanceM: 42195, goalTimeSec: 12600, gender: 'female');
    expect(male.goalPaceSecPerKm, female.goalPaceSecPerKm);
    expect((male.goalPaceSecPerKm - 12600 / 42.195).abs() < 0.001, isTrue);
    expect(male.paces.easy == female.paces.easy, isFalse,
        reason: 'bands still calibrate');
  });
}
