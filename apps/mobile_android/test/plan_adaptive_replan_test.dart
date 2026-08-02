import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_adaptive_replan.dart';
import '../lib/plan_replan.dart';

ReplanWorkout _wo(
  String id,
  String scheduledDate,
  String kind,
  double? targetDistanceM, {
  bool completed = false,
  bool skipped = false,
  bool isPast = false,
}) {
  return ReplanWorkout(
    id: id,
    scheduledDate: scheduledDate,
    kind: kind,
    targetDistanceM: targetDistanceM,
    completed: completed,
    skipped: skipped,
    isPast: isPast,
  );
}

// A completed week with a given planned/actual volume. `under` = actual far
// below planned (flagged under); `over` = far above; `ontrack` = close.
ReplanWeek _week(
  int weekIndex,
  String drift, {
  String phase = 'build',
  List<ReplanWorkout> workouts = const [],
}) {
  const plannedMetres = 40000.0;
  final actualMetres =
      drift == 'under' ? 26000.0 : (drift == 'over' ? 54000.0 : 39000.0);
  return ReplanWeek(
    weekIndex: weekIndex,
    phase: phase,
    plannedMetres: plannedMetres,
    actualMetres: actualMetres,
    isComplete: true,
    workouts: workouts,
  );
}

void main() {
  test('adaptiveReplanRemaining: on track when fewer than two weeks drift', () {
    final weeks = [_week(0, 'ontrack'), _week(1, 'over'), _week(2, 'ontrack')];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.onTrack);
    expect(r.confidence, AdaptiveConfidence.low);
    expect(r.onTrack, true);
    expect(r.changes.length, 0);
  });

  test('adaptiveReplanRemaining: a single noisy week does not trigger a trend', () {
    final weeks = [_week(0, 'ontrack'), _week(1, 'ontrack'), _week(2, 'under')];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.onTrack);
    expect(r.changes.length, 0);
  });

  test('adaptiveReplanRemaining: two-of-three under weeks → trend_underfitness, medium confidence', () {
    final missed = _wo('missed', '2026-06-15', 'long', 28000, isPast: true);
    final future = _wo('next', '2026-07-06', 'long', 22000);
    final weeks = [
      _week(0, 'under', workouts: [missed]),
      _week(1, 'ontrack'),
      _week(2, 'under'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [future],
      ),
    ];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.trendUnderfitness);
    expect(r.confidence, AdaptiveConfidence.medium);
    expect(r.onTrack, false);
    expect(
      r.changes.any((c) => c.workoutId == 'next' && c.reason == ReplanReason.makeUpLong),
      true,
    );
  });

  test('adaptiveReplanRemaining: three-of-three under weeks → high confidence', () {
    final missed = _wo('missed', '2026-06-15', 'long', 28000, isPast: true);
    final future = _wo('next', '2026-07-06', 'long', 22000);
    final weeks = [
      _week(0, 'under', workouts: [missed]),
      _week(1, 'under'),
      _week(2, 'under'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [future],
      ),
    ];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.trendUnderfitness);
    expect(r.confidence, AdaptiveConfidence.high);
  });

  test('adaptiveReplanRemaining: two-of-three over weeks → trend_overtraining with an ease-off change', () {
    final easy = _wo('easy', '2026-07-07', 'easy', 8000);
    final weeks = [
      _week(0, 'over'),
      _week(1, 'ontrack'),
      _week(2, 'over'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [easy],
      ),
    ];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.trendOvertraining);
    expect(
      r.changes.any((c) => c.workoutId == 'easy' && c.reason == ReplanReason.easeOverRunning),
      true,
    );
  });

  test('adaptiveReplanRemaining: a flagged under-trend with no safe change stays change-free', () {
    final weeks = [
      _week(0, 'under'),
      _week(1, 'under'),
      _week(2, 'under'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('f', '2026-07-06', 'easy', 8000)],
      ),
    ];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.trendUnderfitness);
    expect(r.changes.length, 0);
    expect(r.onTrack, true);
  });

  test('adaptiveReplanRemaining: in-progress + zero-planned weeks are excluded from the window', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'base',
        plannedMetres: 0,
        actualMetres: 30000,
        isComplete: true,
        workouts: const [],
      ),
      _week(1, 'under'),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 12000,
        isComplete: false,
        workouts: const [],
      ),
    ];
    final r = adaptiveReplanRemaining(weeks: weeks, today: '2026-07-01');
    expect(r.reason, AdaptiveReason.onTrack);
    expect(r.trailingDirections.length, 1);
  });

  // ── P2: fitness direction gate (branch feat/gen-v2-p2-fitness, CISO-gated) ──

  List<ReplanWeek> underTrendWeeks() {
    final missed = _wo('missed', '2026-06-15', 'long', 28000, isPast: true);
    final future = _wo('next', '2026-07-06', 'long', 22000);
    return [
      _week(0, 'under', workouts: [missed]),
      _week(1, 'under'),
      _week(2, 'under'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [future],
      ),
    ];
  }

  test('adaptiveReplanRemaining: an under-fitness trend is suppressed for a fatigued runner (tsb<0)', () {
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeks(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -18, atl: 90, ctl: 72),
    );
    expect(r.reason, AdaptiveReason.onTrack);
    expect(r.fitnessGated, true);
    expect(r.changes.length, 0);
  });

  test('adaptiveReplanRemaining: an under-fitness trend proceeds for a fresh runner (tsb>=0)', () {
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeks(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: 6, atl: 60, ctl: 66),
    );
    expect(r.reason, AdaptiveReason.trendUnderfitness);
    expect(r.fitnessGated, false);
    expect(r.changes.any((c) => c.workoutId == 'next'), true);
  });

  test('adaptiveReplanRemaining: an over-training trend is not fitness-gated even when fatigued', () {
    final easy = _wo('easy', '2026-07-07', 'easy', 8000);
    final weeks = [
      _week(0, 'over'),
      _week(1, 'ontrack'),
      _week(2, 'over'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [easy],
      ),
    ];
    final r = adaptiveReplanRemaining(
      weeks: weeks,
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -22, atl: 100, ctl: 78),
    );
    expect(r.reason, AdaptiveReason.trendOvertraining);
    expect(r.fitnessGated, false);
  });

  // ── P2 arm 2: the deep-fatigue deload override ──

  /// Deeply fatigued: TSB past the -25 floor AND ATL >= 1.3 * CTL.
  const deep = AdaptiveFitness(tsb: -34, atl: 104, ctl: 70);

  /// An under-running trend whose next week holds BOTH a future long (the
  /// make-up target) and a future easy run (the deload target), so a test can
  /// tell the two directions apart by which workout moved.
  List<ReplanWeek> underTrendWeeksWithEasy() {
    final missed = _wo('missed', '2026-06-15', 'long', 28000, isPast: true);
    final future = _wo('next', '2026-07-06', 'long', 22000);
    final easy = _wo('easy', '2026-07-07', 'easy', 8000);
    return [
      _week(0, 'under', workouts: [missed]),
      _week(1, 'under'),
      _week(2, 'under'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [future, easy],
      ),
    ];
  }

  test('adaptiveReplanRemaining: deep fatigue overrides an on-track plan into a deload', () {
    final easy = _wo('easy', '2026-07-07', 'easy', 8000);
    final weeks = [
      _week(0, 'ontrack'),
      _week(1, 'ontrack'),
      _week(2, 'ontrack'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [easy],
      ),
    ];
    final r = adaptiveReplanRemaining(
        weeks: weeks, today: '2026-07-01', fitness: deep);
    expect(r.reason, AdaptiveReason.deloadFatigue);
    expect(r.confidence, AdaptiveConfidence.high);
    expect(r.onTrack, false);
    expect(r.changes.length, 1);
    expect(r.changes.first.workoutId, 'easy');
    expect(r.changes.first.fromMetres, 8000);
    expect(r.changes.first.toMetres, 6800);
  });

  test('adaptiveReplanRemaining: deep fatigue overrides an under-trend to a deload, never a make-up', () {
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: deep,
    );
    expect(r.reason, AdaptiveReason.deloadFatigue);
    // The volume-adding make-up on the future long is NOT proposed...
    expect(r.changes.any((c) => c.workoutId == 'next'), false);
    // ...only the ease-off on the future easy run.
    expect(r.changes.any((c) => c.workoutId == 'easy'), true);
  });

  test('adaptiveReplanRemaining: high acute load with shallow TSB does not deload', () {
    // ACWR 100/70 = 1.43 (over the bar) but TSB -5 is a normal hard week.
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -5, atl: 100, ctl: 70),
    );
    expect(r.reason, isNot(AdaptiveReason.deloadFatigue));
    expect(r.fitnessGated, true);
    expect(r.changes.length, 0);
  });

  test('adaptiveReplanRemaining: deeply negative TSB without high acute load does not deload', () {
    // TSB -30 is past the floor, but ACWR 100/95 = 1.05 — a big, well-absorbed
    // block, not an acute spike.
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -30, atl: 100, ctl: 95),
    );
    expect(r.reason, isNot(AdaptiveReason.deloadFatigue));
    expect(r.fitnessGated, true);
  });

  test('adaptiveReplanRemaining: no chronic base (ctl 0) never deloads', () {
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -60, atl: 60, ctl: 0),
    );
    expect(r.reason, isNot(AdaptiveReason.deloadFatigue));
    expect(r.fitnessGated, true);
  });

  test('adaptiveReplanRemaining: non-finite load values fail closed', () {
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(
          tsb: double.negativeInfinity, atl: double.infinity, ctl: 70),
    );
    expect(r.reason, isNot(AdaptiveReason.deloadFatigue));
    expect(r.changes.length, 0);
  });

  test('adaptiveReplanRemaining: deep fatigue with only a taper week ahead proposes nothing', () {
    final easy = _wo('easy', '2026-07-07', 'easy', 8000);
    final weeks = [
      _week(0, 'ontrack'),
      _week(1, 'ontrack'),
      _week(2, 'ontrack'),
      ReplanWeek(
        weekIndex: 3,
        phase: 'taper',
        plannedMetres: 20000,
        actualMetres: 0,
        isComplete: false,
        workouts: [easy],
      ),
    ];
    final r = adaptiveReplanRemaining(
        weeks: weeks, today: '2026-07-01', fitness: deep);
    expect(r.reason, AdaptiveReason.deloadFatigue);
    expect(r.changes.length, 0);
    expect(r.onTrack, true);
  });

  test('adaptiveReplanRemaining: the fitness snapshot never leaves the function', () {
    // Structural, not behavioural: the result carries no load number back to
    // the caller, and the library logs nothing — so a TSB cannot reach a log
    // line, a plan row, or the network. A stated condition of the P2 sign-off.
    final r = adaptiveReplanRemaining(
      weeks: underTrendWeeksWithEasy(),
      today: '2026-07-01',
      fitness: const AdaptiveFitness(tsb: -33.7, atl: 101.3, ctl: 71.9),
    );
    for (final c in r.changes) {
      expect(c.fromMetres, isNot(anyOf(-33.7, 101.3, 71.9)));
      expect(c.toMetres, isNot(anyOf(-33.7, 101.3, 71.9)));
    }
    final source = File('lib/plan_adaptive_replan.dart').readAsStringSync();
    final start = source.indexOf('class AdaptiveReplanResult');
    final end = source.indexOf('/// Pure parse of the P2 fitness-gate deploy flag');
    expect(start >= 0 && end > start, true,
        reason: 'could not slice AdaptiveReplanResult — rename?');
    expect(RegExp(r'\b(tsb|atl|ctl)\s*[;,)]').hasMatch(source.substring(start, end)), false,
        reason: 'AdaptiveReplanResult must not carry a load number back out');
    expect(RegExp(r'\b(print|debugPrint)\s*\(').hasMatch(source), false,
        reason: 'the library must not log');
  });

  test('adaptiveFitnessGateEnabled: unset / empty / negative values are off', () {
    for (final raw in [null, '', '   ', 'false', '0', 'off', 'no', 'enabled', 'truthy']) {
      expect(adaptiveFitnessGateEnabled(raw), false, reason: '$raw must be off');
    }
  });

  test('adaptiveFitnessGateEnabled: only an explicit affirmative turns it on', () {
    for (final raw in ['1', 'true', 'yes', 'on', 'TRUE', ' On ', 'Yes']) {
      expect(adaptiveFitnessGateEnabled(raw), true, reason: '$raw must be on');
    }
  });
}
