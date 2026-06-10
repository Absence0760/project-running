import 'package:flutter_test/flutter_test.dart';

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
  test('empty input yields no records', () {
    expect(exerciseRecords([]), isEmpty);
  });

  test('single weighted exercise rolls up its bests, last date and session count', () {
    final out = exerciseRecords([
      s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 5, weightKg: 100),
      s(workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', reps: 3, weightKg: 105),
      s(workoutId: 'w2', startedAt: '2026-06-05T08:00:00Z', reps: 8, weightKg: 90),
    ]);
    expect(out.length, 1);
    final r = out[0];
    expect(r.exerciseName, 'Bench Press');
    expect(r.heaviestWeightKg, 105);
    expect(r.heaviestWeightReps, 3);
    // Best single-set volume = 8 × 90 = 720 (beats 5×100=500, 3×105=315).
    expect(r.bestVolumeKg, 720);
    // e1rm best: 90·(1+8/30)=114 beats 105 (single → 105) and 100·(1+5/30)≈116.67.
    expect(r.bestEst1RmKg, 116.7);
    expect(r.lastPerformedAt, '2026-06-05T08:00:00Z');
    expect(r.sessionCount, 2);
  });

  test('bodyweight-only exercise (no weight) is excluded — consistent with the PR engine', () {
    final out = exerciseRecords([
      s(exerciseName: 'Pull-up', reps: 12, weightKg: null),
      s(exerciseName: 'Squat', reps: 5, weightKg: 140),
    ]);
    expect(out.map((r) => r.exerciseName).toList(), ['Squat']);
  });

  test('sorted most-recently-performed first, ties broken alphabetically', () {
    final out = exerciseRecords([
      s(exerciseName: 'Deadlift', workoutId: 'w1', startedAt: '2026-06-01T08:00:00Z', weightKg: 180),
      s(exerciseName: 'Squat', workoutId: 'w2', startedAt: '2026-06-10T08:00:00Z', weightKg: 140),
      // Same last date as Squat → alphabetical: Bench before Squat.
      s(exerciseName: 'Bench Press', workoutId: 'w3', startedAt: '2026-06-10T08:00:00Z', weightKg: 100),
    ]);
    expect(out.map((r) => r.exerciseName).toList(), ['Bench Press', 'Squat', 'Deadlift']);
  });

  test('case/whitespace variants of a name collapse to one record', () {
    final out = exerciseRecords([
      s(exerciseName: 'Bench Press', weightKg: 100),
      s(exerciseName: 'bench  press', weightKg: 110),
      s(exerciseName: '  BENCH PRESS ', weightKg: 105),
    ]);
    expect(out.length, 1);
    expect(out[0].heaviestWeightKg, 110);
    // Display spelling is the first set's spelling (PR-engine behaviour).
    expect(out[0].exerciseName, 'Bench Press');
  });

  test('sessionCount counts distinct workouts, not sets', () {
    final out = exerciseRecords([
      s(workoutId: 'w1', weightKg: 100),
      s(workoutId: 'w1', weightKg: 100),
      s(workoutId: 'w1', weightKg: 100),
    ]);
    expect(out[0].sessionCount, 1);
  });

  test('blank exercise names are ignored', () {
    final out = exerciseRecords([
      s(exerciseName: '   ', weightKg: 100),
      s(exerciseName: '', weightKg: 100),
    ]);
    expect(out, isEmpty);
  });

  test('volume and e1rm stay null when an exercise was only ever logged without reps', () {
    final out = exerciseRecords([s(exerciseName: 'Carry', reps: null, weightKg: 50)]);
    expect(out.length, 1);
    expect(out[0].heaviestWeightKg, 50);
    expect(out[0].bestVolumeKg, null);
    expect(out[0].bestEst1RmKg, null);
  });
}
