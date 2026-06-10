import 'package:flutter_test/flutter_test.dart';

import '../lib/exercise_history.dart';
import '../lib/exercise_records.dart';

DatedGymSet s({
  String workoutId = 'w1',
  String startedAt = '2026-06-01T08:00:00Z',
  String exerciseName = 'Bench Press',
  num? reps = 5,
  num? weightKg = 100,
}) =>
    DatedGymSet(
      workoutId: workoutId,
      startedAt: startedAt,
      exerciseName: exerciseName,
      reps: reps,
      weightKg: weightKg,
    );

void main() {
  test('unknown exercise / blank name yields null', () {
    expect(exerciseProgress([], 'Bench Press'), null);
    expect(exerciseProgress([s()], '   '), null);
    expect(exerciseProgress([s(exerciseName: 'Squat')], 'Deadlift'), null);
  });

  test('collapses sessions chronologically with top set, e1rm, volume and set count', () {
    final p = exerciseProgress(
      [
        s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', reps: 3, weightKg: 110),
        s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 100),
        s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 90),
      ],
      'Bench Press',
    );
    expect(p, isNotNull);
    expect(p!.exerciseName, 'Bench Press');
    expect(p.sessions.length, 2);
    // Oldest first.
    expect(p.sessions[0].workoutId, 'w1');
    expect(p.sessions[1].workoutId, 'w2');
    // Session 1: heaviest 100 (5 reps), two sets, volume 5×100 + 5×90 = 950.
    expect(p.sessions[0].topWeightKg, 100);
    expect(p.sessions[0].topWeightReps, 5);
    expect(p.sessions[0].setCount, 2);
    expect(p.sessions[0].volumeKg, 950);
    // e1rm session 1: max(100·(1+5/30), 90·(1+5/30)) = 116.67 → 116.7.
    expect(p.sessions[0].bestEst1RmKg, 116.7);
  });

  test('marks the session that set a new estimated-1RM PR', () {
    final p = exerciseProgress(
      [
        s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 100), // e1rm 116.7
        s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', reps: 5, weightKg: 95), // e1rm 110.8 — no PR
        s(workoutId: 'w3', startedAt: '2026-06-09T08:00:00Z', reps: 3, weightKg: 110), // e1rm 121 — PR
      ],
      'Bench Press',
    );
    expect(p, isNotNull);
    expect(p!.sessions.map((x) => x.isEst1RmPr).toList(), [true, false, true]);
  });

  test('headline est-1RM delta is latest minus first across sessions with an e1rm', () {
    final p = exerciseProgress(
      [
        s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 100), // 116.7
        s(workoutId: 'w2', startedAt: '2026-06-09T08:00:00Z', reps: 3, weightKg: 110), // 121.0
      ],
      'Bench Press',
    );
    expect(p, isNotNull);
    expect(p!.firstEst1RmKg, 116.7);
    expect(p.latestEst1RmKg, 121);
    expect(p.bestEst1RmKg, 121);
    expect(p.est1RmDeltaKg, 4.3);
  });

  test('delta is null with only one e1rm data point', () {
    final p = exerciseProgress([s(reps: 5, weightKg: 100)], 'Bench Press');
    expect(p, isNotNull);
    expect(p!.est1RmDeltaKg, null);
    expect(p.firstEst1RmKg, 116.7);
  });

  test('case/whitespace name variants match the same exercise', () {
    final p = exerciseProgress(
      [
        s(workoutId: 'w1', exerciseName: 'Bench Press', weightKg: 100),
        s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', exerciseName: 'bench  press', weightKg: 110),
      ],
      'BENCH PRESS',
    );
    expect(p, isNotNull);
    expect(p!.sessions.length, 2);
    // Display spelling is the first-seen one, via the PR engine.
    expect(p.exerciseName, 'Bench Press');
  });

  test('a session with only bodyweight sets of the exercise is excluded', () {
    final p = exerciseProgress(
      [
        s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', weightKg: 100),
        s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', reps: 10, weightKg: null),
      ],
      'Bench Press',
    );
    expect(p, isNotNull);
    expect(p!.sessions.length, 1);
    expect(p.sessions[0].workoutId, 'w1');
  });

  test('a weighted session with no reps carries a top weight but no e1rm/volume', () {
    final p = exerciseProgress([s(exerciseName: 'Carry', reps: null, weightKg: 50)], 'Carry');
    expect(p, isNotNull);
    expect(p!.sessions[0].topWeightKg, 50);
    expect(p.sessions[0].bestEst1RmKg, null);
    expect(p.sessions[0].volumeKg, 0);
    expect(p.est1RmDeltaKg, null);
    expect(p.bestEst1RmKg, null);
  });

  test('previousExerciseSession returns the latest qualifying session before the cutoff', () {
    final sets = [
      s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 100),
      s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', reps: 5, weightKg: 105),
      s(workoutId: 'w3', startedAt: '2026-06-09T08:00:00Z', reps: 5, weightKg: 110),
    ];
    // Cutoff = w3's started_at: the previous session is w2 (105), not w3 itself.
    final prev = previousExerciseSession(sets, 'Bench Press', '2026-06-09T08:00:00Z');
    expect(prev, isNotNull);
    expect(prev!.workoutId, 'w2');
    expect(prev.topWeightKg, 105);
  });

  test('previousExerciseSession is null when nothing precedes the cutoff', () {
    final sets = [s(workoutId: 'w1', startedAt: '2026-06-05T08:00:00Z', weightKg: 100)];
    // Cutoff equals the only session's date — strict `<` excludes it.
    expect(previousExerciseSession(sets, 'Bench Press', '2026-06-05T08:00:00Z'), null);
    // Cutoff before everything.
    expect(previousExerciseSession(sets, 'Bench Press', '2026-06-01T00:00:00Z'), null);
  });

  test('previousExerciseSession ignores other exercises and bodyweight-only sessions', () {
    final sets = [
      s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', exerciseName: 'Squat', weightKg: 140),
      s(workoutId: 'w2', startedAt: '2026-06-03T08:00:00Z', exerciseName: 'Bench Press', reps: 10, weightKg: null),
      s(workoutId: 'w3', startedAt: '2026-06-05T08:00:00Z', exerciseName: 'Bench Press', reps: 5, weightKg: 100),
    ];
    // Looking back from w4's date for Bench Press: w2 is bodyweight-only (skipped),
    // w1 is a different exercise (skipped) → w3 is the previous Bench session.
    final prev = previousExerciseSession(sets, 'Bench Press', '2026-06-09T08:00:00Z');
    expect(prev, isNotNull);
    expect(prev!.workoutId, 'w3');
    expect(prev.topWeightKg, 100);
  });
}
