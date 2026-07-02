import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_adherence.dart';

PlannedSetRef planned(
  String exerciseKey,
  int setIndex, [
  num? targetRepsMin,
  num? targetWeightKg,
  num? targetDurationS,
  num? targetRepsMax,
  String setType = 'working',
]) => PlannedSetRef(
  exerciseKey: exerciseKey,
  setIndex: setIndex,
  setType: setType,
  targetRepsMin: targetRepsMin,
  targetRepsMax: targetRepsMax,
  targetWeightKg: targetWeightKg,
  targetDurationS: targetDurationS,
);

ActualSetRef actual(
  String exerciseKey,
  int setIndex, [
  num? reps,
  num? weightKg,
  num? durationS,
]) => ActualSetRef(
  exerciseKey: exerciseKey,
  setIndex: setIndex,
  reps: reps,
  weightKg: weightKg,
  durationS: durationS,
);

void main() {
  test('all sets hit -> completed, pct 1.0', () {
    final r = computeRoutineAdherence(
      [planned('bench', 0, 5, 80), planned('bench', 1, 5, 80)],
      [actual('bench', 0, 5, 80), actual('bench', 1, 6, 85)],
    );
    expect(r.plannedCount, 2);
    expect(r.completedCount, 2);
    expect(r.adherencePct, 1.0);
    expect(r.verdict, RoutineVerdict.completed);
    expect(r.sets.map((s) => s.status).toList(), [
      SetAdherenceStatus.hit,
      SetAdherenceStatus.hit,
    ]);
  });

  test('zero completed -> abandoned', () {
    final r = computeRoutineAdherence(
      [planned('squat', 0, 5, 100), planned('squat', 1, 5, 100)],
      [],
    );
    expect(r.completedCount, 0);
    expect(r.adherencePct, 0);
    expect(r.verdict, RoutineVerdict.abandoned);
  });

  test('80% boundary -> completed', () {
    final plan = <PlannedSetRef>[];
    final act = <ActualSetRef>[];
    for (var i = 0; i < 10; i++) {
      plan.add(planned('row', i, 5, 50));
    }
    for (var i = 0; i < 8; i++) {
      act.add(actual('row', i, 5, 50));
    }
    final r = computeRoutineAdherence(plan, act);
    expect(r.completedCount, 8);
    expect(r.adherencePct, 0.8);
    expect(r.verdict, RoutineVerdict.completed);
  });

  test('79% -> partial', () {
    final plan = <PlannedSetRef>[];
    final act = <ActualSetRef>[];
    for (var i = 0; i < 100; i++) {
      plan.add(planned('row', i, 5, 50));
    }
    for (var i = 0; i < 79; i++) {
      act.add(actual('row', i, 5, 50));
    }
    final r = computeRoutineAdherence(plan, act);
    expect(r.completedCount, 79);
    expect(r.adherencePct, 0.79);
    expect(r.verdict, RoutineVerdict.partial);
  });

  test('reps below min -> partial status', () {
    final r = computeRoutineAdherence(
      [planned('curl', 0, 10, 20)],
      [actual('curl', 0, 7, 20)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.partial);
    expect(r.completedCount, 0);
  });

  test('weight below 80% of target -> missed', () {
    final r = computeRoutineAdherence(
      [planned('press', 0, 5, 60)],
      [actual('press', 0, 5, 45)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.missed);
    expect(r.completedCount, 0);
  });

  test('reps at 80% of floor -> hit', () {
    final r = computeRoutineAdherence(
      [planned('curl', 0, 10, 20)],
      [actual('curl', 0, 8, 20)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
    expect(r.verdict, RoutineVerdict.completed);
  });

  test('weight at 80% of target -> hit', () {
    final r = computeRoutineAdherence(
      [planned('press', 0, 5, 100)],
      [actual('press', 0, 5, 80)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
  });

  test('weight at 79% of target -> missed', () {
    final r = computeRoutineAdherence(
      [planned('press', 0, 5, 100)],
      [actual('press', 0, 5, 79)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.missed);
  });

  test('bodyweight set planned with targetWeightKg 0 is hit on reps alone', () {
    // Regression: a literal 0 weight target (bodyweight) must not fire the
    // weight gate (`!= null` is true for 0), which would auto-miss a set the
    // runner completed at full reps with no logged weight.
    final r = computeRoutineAdherence(
      [planned('pushup', 0, 5, 0)],
      [actual('pushup', 0, 5)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
    expect(r.completedCount, 1);
    expect(r.verdict, RoutineVerdict.completed);
  });

  test('warmup set is excluded from the verdict denominator', () {
    final r = computeRoutineAdherence(
      [
        planned('squat', 0, 5, 60, null, null, 'warmup'),
        planned('squat', 1, 5, 100),
      ],
      [actual('squat', 1, 5, 100)],
    );
    expect(r.plannedCount, 1);
    expect(r.completedCount, 1);
    expect(r.verdict, RoutineVerdict.completed);
    expect(
      r.sets.any((s) => s.exerciseKey == 'squat' && s.setIndex == 0),
      isFalse,
    );
  });

  test('amrap set is hit when any reps logged', () {
    final r = computeRoutineAdherence(
      [planned('pullup', 0, 5, null, null, null, 'amrap')],
      [actual('pullup', 0, 3, null)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
    expect(r.verdict, RoutineVerdict.completed);
  });

  test('extra unplanned set -> extra, not counted in plannedCount', () {
    final r = computeRoutineAdherence(
      [planned('bench', 0, 5, 80)],
      [actual('bench', 0, 5, 80), actual('bench', 1, 5, 80)],
    );
    expect(r.plannedCount, 1);
    expect(r.completedCount, 1);
    final extra = r.sets.firstWhere(
      (s) => s.status == SetAdherenceStatus.extra,
    );
    expect(extra.setIndex, 1);
    expect(r.adherencePct, 1.0);
  });

  test('duration-set hit by durationS', () {
    final r = computeRoutineAdherence(
      [planned('plank', 0, null, null, 60), planned('plank', 1, null, null, 60)],
      [actual('plank', 0, null, null, 75), actual('plank', 1, null, null, 45)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
    expect(r.sets[1].status, SetAdherenceStatus.partial);
  });

  test(
    'weighted-duration set: duration met, weight unlogged -> hit (duration is primary when weight is not recorded)',
    () {
      // A set carrying BOTH a weight and a duration target, logged with the
      // duration met but the weight left blank, must grade on duration — not
      // auto-miss on the unlogged weight. (Regression: the weight gate used to
      // fire on `weightKg == null`.)
      final r = computeRoutineAdherence(
        [planned('weighted-plank', 0, null, 10, 60)],
        [actual('weighted-plank', 0, null, null, 75)],
      );
      expect(r.sets[0].status, SetAdherenceStatus.hit);
      expect(r.completedCount, 1);
      expect(r.verdict, RoutineVerdict.completed);
    },
  );

  test(
    'weighted-duration set: weight logged but short still misses (a recorded weight stays primary)',
    () {
      // When the weight IS recorded and falls below 80%, the set misses
      // regardless of the duration — duration is only the primary axis while
      // the weight is unrecorded.
      final r = computeRoutineAdherence(
        [planned('weighted-plank', 0, null, 100, 60)],
        [actual('weighted-plank', 0, null, 50, 75)],
      );
      expect(r.sets[0].status, SetAdherenceStatus.missed);
      expect(r.completedCount, 0);
    },
  );

  test('deltas signed correctly', () {
    final r = computeRoutineAdherence(
      [planned('bench', 0, 5, 80), planned('bench', 1, 8, 100)],
      [actual('bench', 0, 7, 85), actual('bench', 1, 6, 90)],
    );
    expect(r.sets[0].repsDelta, 2);
    expect(r.sets[0].weightDeltaKg, 5);
    expect(r.sets[1].repsDelta, -2);
    expect(r.sets[1].weightDeltaKg, -10);
  });

  test('empty planned -> abandoned edge, pct 0', () {
    final r = computeRoutineAdherence([], [actual('bench', 0, 5, 80)]);
    expect(r.plannedCount, 0);
    expect(r.completedCount, 0);
    expect(r.adherencePct, 0);
    expect(r.verdict, RoutineVerdict.abandoned);
    expect(r.sets.length, 1);
    expect(r.sets[0].status, SetAdherenceStatus.extra);
  });

  test('empty actual -> all missed', () {
    final r = computeRoutineAdherence(
      [
        planned('squat', 0, 5, 100),
        planned('squat', 1, 5, 100),
        planned('squat', 2, 5, 100),
      ],
      [],
    );
    expect(r.sets.map((s) => s.status).toList(), [
      SetAdherenceStatus.missed,
      SetAdherenceStatus.missed,
      SetAdherenceStatus.missed,
    ]);
    expect(r.verdict, RoutineVerdict.abandoned);
  });

  test('match by key+setIndex, not name spelling', () {
    final r = computeRoutineAdherence(
      [planned('bench-press', 0, 5, 80)],
      [actual('bench-press', 0, 5, 80), actual('Bench Press', 0, 5, 80)],
    );
    expect(r.sets[0].status, SetAdherenceStatus.hit);
    final extra = r.sets.firstWhere((s) => s.exerciseKey == 'Bench Press');
    expect(extra.status, SetAdherenceStatus.extra);
    expect(r.plannedCount, 1);
    expect(r.completedCount, 1);
  });
}
