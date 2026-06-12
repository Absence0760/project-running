import 'package:flutter_test/flutter_test.dart';

import '../lib/progression_prefill.dart';

DatedLoggedSet _s(
  String workoutId,
  String startedAt,
  String exerciseName,
  num? reps,
  num? weightKg,
) =>
    DatedLoggedSet(
      workoutId: workoutId,
      startedAt: startedAt,
      exerciseName: exerciseName,
      reps: reps,
      weightKg: weightKg,
    );

({num? reps, num? weightKg, num? rpe}) _t(s) =>
    (reps: s.reps, weightKg: s.weightKg, rpe: s.rpe);

void main() {
  test('returns null when the exercise was never logged', () {
    final sets = [_s('w1', '2026-01-01', 'Squat', 5, 100)];
    expect(lastSessionSets(sets, 'Bench Press'), isNull);
  });

  test('returns null for a blank exercise name', () {
    final sets = [_s('w1', '2026-01-01', 'Squat', 5, 100)];
    expect(lastSessionSets(sets, '   '), isNull);
  });

  test('picks the most recent session by startedAt, keeping logged order', () {
    final sets = [
      _s('w1', '2026-01-01', 'Bench', 5, 80),
      _s('w2', '2026-02-01', 'Bench', 5, 82.5),
      _s('w2', '2026-02-01', 'Bench', 4, 82.5),
    ];
    expect(lastSessionSets(sets, 'Bench')!.map(_t).toList(), [
      (reps: 5, weightKg: 82.5, rpe: null),
      (reps: 4, weightKg: 82.5, rpe: null),
    ]);
  });

  test('matches by normalised name (case / spacing insensitive)', () {
    final sets = [_s('w1', '2026-01-01', '  bench  press ', 5, 80)];
    expect(lastSessionSets(sets, 'Bench Press')!.map(_t).toList(),
        [(reps: 5, weightKg: 80, rpe: null)]);
  });

  test('ignores other exercises in the same workout', () {
    final sets = [
      _s('w1', '2026-02-01', 'Squat', 5, 120),
      _s('w1', '2026-02-01', 'Bench', 5, 80),
    ];
    expect(lastSessionSets(sets, 'Bench')!.map(_t).toList(),
        [(reps: 5, weightKg: 80, rpe: null)]);
  });

  test('ties on startedAt break by workout id (deterministic)', () {
    final sets = [
      _s('wA', '2026-02-01', 'Row', 8, 50),
      _s('wB', '2026-02-01', 'Row', 8, 55),
    ];
    expect(lastSessionSets(sets, 'Row')!.map(_t).toList(),
        [(reps: 8, weightKg: 55, rpe: null)]);
  });
}
