import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_replan.dart';

ReplanWorkout _wo(
  String id,
  String scheduledDate,
  String kind,
  double? targetDistanceM, {
  bool completed = false,
  bool isPast = false,
}) {
  return ReplanWorkout(
    id: id,
    scheduledDate: scheduledDate,
    kind: kind,
    targetDistanceM: targetDistanceM,
    completed: completed,
    isPast: isPast,
  );
}

void main() {
  test('an on-track plan proposes no changes', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 39000,
        isComplete: true,
        workouts: [
          _wo('a', '2026-06-01', 'long', 20000, completed: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('b', '2026-06-08', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.onTrack, true);
    expect(r.changes.length, 0);
  });

  test('a missed long run in build is made up by bumping the next long', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [
          _wo('missed', '2026-06-01', 'long', 28000,
              completed: false, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-08', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.changes.any((c) => c.workoutId == 'missed'), false);
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.reason, ReplanReason.makeUpLong);
    expect(makeUp.toMetres, (22000 * (1 + makeUpMaxIncrease)).round());
  });

  test('a make-up never shrinks an already-longer next long run', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('missed', '2026-06-01', 'long', 16000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-08', 'long', 24000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.onTrack, true);
    expect(r.changes.length, 0);
  });

  test('a missed long run in the TAPER is skipped, never made up', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'taper',
        plannedMetres: 25000,
        actualMetres: 10000,
        isComplete: true,
        workouts: [_wo('missed', '2026-06-01', 'long', 18000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'race',
        plannedMetres: 10000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('race', '2026-06-08', 'race', 42195)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.onTrack, true);
    expect(r.changes.length, 0);
  });

  test('cumulative over-running eases the next future week', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 52000,
        isComplete: true,
        workouts: [
          _wo('a', '2026-06-01', 'easy', 10000, completed: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [
          _wo('tempo', '2026-06-08', 'tempo', 12000),
          _wo('long', '2026-06-13', 'long', 22000),
          _wo('rest', '2026-06-09', 'rest', null),
        ],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    final ease = r.changes.firstWhere((c) => c.workoutId == 'tempo');
    expect(ease.reason, ReplanReason.easeOverRunning);
    expect(ease.toMetres, (12000 * easeOffScale).round());
    expect(r.changes.any((c) => c.workoutId == 'long'), false);
    expect(r.changes.any((c) => c.workoutId == 'rest'), false);
  });

  test('never touches a past future-week placeholder or the taper', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 60000,
        isComplete: true,
        workouts: [
          _wo('done', '2026-06-01', 'tempo', 10000,
              completed: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'taper',
        plannedMetres: 30000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('taper-tempo', '2026-06-08', 'tempo', 8000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.changes.length, 0);
    expect(r.onTrack, true);
  });
}
