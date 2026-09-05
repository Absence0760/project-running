import 'package:flutter_test/flutter_test.dart';
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

  test('several missed long runs make up the LARGEST, not the earliest', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('miss-a', '2026-06-01', 'long', 24000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 44000,
        actualMetres: 22000,
        isComplete: true,
        workouts: [_wo('miss-b', '2026-06-08', 'long', 30000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 46000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-15', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-12');
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.reason, ReplanReason.makeUpLong);
    // Driven by the 30 km miss → capped to 22 km * 1.15, not the 24 km miss.
    expect(makeUp.toMetres, (22000 * (1 + makeUpMaxIncrease)).round());
    expect(
      r.changes.where((c) => c.reason == ReplanReason.makeUpLong).length,
      1,
    );
  });

  test('largest missed long wins even when it is the EARLIEST week', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 44000,
        actualMetres: 22000,
        isComplete: true,
        workouts: [_wo('big', '2026-06-01', 'long', 30000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('small', '2026-06-08', 'long', 24000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 46000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-15', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-12');
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.toMetres, (22000 * (1 + makeUpMaxIncrease)).round());
    expect(
      r.changes.where((c) => c.reason == ReplanReason.makeUpLong).length,
      1,
    );
  });

  test('when the largest miss is under the cap the make-up reaches it exactly',
      () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('small', '2026-06-01', 'long', 20000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 21000,
        isComplete: true,
        workouts: [_wo('mid', '2026-06-08', 'long', 24000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 44000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-15', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-12');
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.toMetres, 24000);
  });

  test('a taper miss is excluded from the make-up max even if it is the largest',
      () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('build-miss', '2026-06-01', 'long', 23000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'taper',
        plannedMetres: 38000,
        actualMetres: 10000,
        isComplete: true,
        workouts: [_wo('taper-miss', '2026-06-08', 'long', 35000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-15', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-12');
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.toMetres, 23000);
  });

  test('three missed longs still produce exactly one capped make-up', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 36000,
        actualMetres: 18000,
        isComplete: true,
        workouts: [_wo('m1', '2026-06-01', 'long', 18000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 44000,
        actualMetres: 22000,
        isComplete: true,
        workouts: [_wo('m2', '2026-06-08', 'long', 31000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('m3', '2026-06-15', 'long', 24000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 3,
        phase: 'build',
        plannedMetres: 46000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-22', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-19');
    final makeUps =
        r.changes.where((c) => c.reason == ReplanReason.makeUpLong).toList();
    expect(makeUps.length, 1);
    expect(makeUps[0].toMetres, (22000 * (1 + makeUpMaxIncrease)).round());
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

  test('an explicitly SKIPPED long run is never made up', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 44000,
        actualMetres: 18000,
        isComplete: true,
        workouts: [
          _wo('skipped', '2026-06-01', 'long', 30000,
              skipped: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 46000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-08', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    expect(r.changes.any((c) => c.reason == ReplanReason.makeUpLong), false);
    expect(r.onTrack, true);
    expect(r.changes.length, 0);
  });

  test('a skipped long is excluded but a genuine miss still makes up', () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('genuine-miss', '2026-06-01', 'long', 23000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 48000,
        actualMetres: 12000,
        isComplete: true,
        workouts: [
          _wo('skipped', '2026-06-08', 'long', 35000,
              skipped: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 2,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('next', '2026-06-15', 'long', 22000)],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-12');
    final makeUp = r.changes.firstWhere((c) => c.workoutId == 'next');
    expect(makeUp.toMetres, 23000);
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

  test('easeOffNextWeek: scales the first future non-taper week, skipping long / rest / past / skipped ids',
      () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 40000,
        isComplete: true,
        workouts: [
          _wo('done', '2026-06-01', 'tempo', 10000, completed: true, isPast: true)
        ],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [
          _wo('gone', '2026-06-06', 'easy', 6000, isPast: true),
          _wo('easy', '2026-06-09', 'easy', 12000),
          _wo('tempo', '2026-06-10', 'tempo', 9000),
          _wo('long', '2026-06-11', 'long', 24000),
          _wo('rest', '2026-06-12', 'rest', null),
        ],
      ),
    ];
    final changes = easeOffNextWeek(weeks, 0, skipWorkoutIds: {'tempo'});
    expect(changes.length, 1);
    expect(changes.first.workoutId, 'easy');
    expect(changes.first.toMetres, (12000 * easeOffScale).round().toDouble());
    expect(changes.first.reason, ReplanReason.easeOverRunning);
  });

  test('easeOffNextWeek: returns nothing when the only week ahead is a taper (and -1 eases the earliest)',
      () {
    final taperOnly = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'taper',
        plannedMetres: 30000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('t', '2026-06-08', 'tempo', 8000)],
      ),
    ];
    expect(easeOffNextWeek(taperOnly, -1).length, 0);

    final buildOnly = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 30000,
        actualMetres: 0,
        isComplete: false,
        workouts: [_wo('t', '2026-06-08', 'tempo', 8000)],
      ),
    ];
    // -1 means "no completed week yet" — the earliest eligible week is eased.
    expect(easeOffNextWeek(buildOnly, -1).length, 1);
  });

  test('two future long runs on the same date: the first in plan order absorbs the make-up',
      () {
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('missed', '2026-06-01', 'long', 28000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: [
          _wo('first', '2026-06-08', 'long', 22000),
          _wo('second', '2026-06-08', 'long', 22000),
        ],
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    final makeUps =
        r.changes.where((c) => c.reason == ReplanReason.makeUpLong).toList();
    expect(makeUps.length, 1);
    expect(makeUps.first.workoutId, 'first');
  });

  test('the same-date tie holds on a plan past the small-array sort path', () {
    // 40 future long runs, the first and last sharing the earliest date, so an
    // unstable ordering of the equal pair would pick the wrong session.
    // `List.sort` hands off to an unstable quicksort past 33 elements, which is
    // what made a shipped tie-break by sort unsafe on either platform.
    final future = <ReplanWorkout>[
      _wo('first', '2026-06-08', 'long', 22000),
      for (var i = 0; i < 38; i++) _wo('mid', '2026-06-15', 'long', 22000),
      _wo('last', '2026-06-08', 'long', 22000),
    ];
    final weeks = [
      ReplanWeek(
        weekIndex: 0,
        phase: 'build',
        plannedMetres: 40000,
        actualMetres: 20000,
        isComplete: true,
        workouts: [_wo('missed', '2026-06-01', 'long', 28000, isPast: true)],
      ),
      ReplanWeek(
        weekIndex: 1,
        phase: 'build',
        plannedMetres: 42000,
        actualMetres: 0,
        isComplete: false,
        workouts: future,
      ),
    ];
    final r = replanRemaining(weeks: weeks, today: '2026-06-05');
    final makeUps =
        r.changes.where((c) => c.reason == ReplanReason.makeUpLong).toList();
    expect(makeUps.length, 1);
    expect(makeUps.first.workoutId, 'first');
  });
}
