import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_progression.dart';
import '../lib/progression_prefill.dart';

const _fiveByFive = FiveByFiveTargets(targetSets: 5, targetReps: 5);

/// Five completed sets of [reps] at [weight] — one 5×5 session of [name].
List<DatedLoggedSet> _session(
  String workoutId,
  String startedAt,
  String name,
  num reps,
  num weight, [
  int count = 5,
]) =>
    List.generate(
        count, (_) => _s(workoutId, startedAt, name, reps, weight));

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

  test('setType is carried through to the prescriber', () {
    // The prescriber excludes warmups; it can only do that if this glue passes
    // the column along. Dropping it here is how the ramp-up set came to be
    // judged as a failed working set.
    final sets = [
      const DatedLoggedSet(
        workoutId: 'w1',
        startedAt: '2026-03-01',
        exerciseName: 'Squat',
        reps: 3,
        weightKg: 60,
        setType: 'warmup',
      ),
      const DatedLoggedSet(
        workoutId: 'w1',
        startedAt: '2026-03-01',
        exerciseName: 'Squat',
        reps: 5,
        weightKg: 100,
        setType: 'working',
      ),
    ];
    expect(
      lastSessionSets(sets, 'Squat')?.map((x) => x.setType).toList(),
      ['warmup', 'working'],
    );
  });

  test('consecutiveMissSessions: an unlogged exercise has no streak', () {
    expect(consecutiveMissSessions([], 'Squat', _fiveByFive), 0);
    expect(
      consecutiveMissSessions(
          _session('w1', '2026-01-01', 'Bench', 5, 80), 'Squat', _fiveByFive),
      0,
    );
  });

  test(
      'consecutiveMissSessions: counts back from the newest, stopping at the first cleared session',
      () {
    final sets = [
      ..._session('w1', '2026-01-01', 'Squat', 3, 100),
      ..._session('w2', '2026-01-08', 'Squat', 5, 100),
      ..._session('w3', '2026-01-15', 'Squat', 4, 100),
      ..._session('w4', '2026-01-22', 'Squat', 4, 100),
      ..._session('w5', '2026-01-29', 'Squat', 3, 100),
    ];
    expect(consecutiveMissSessions(sets, 'Squat', _fiveByFive), 3);
  });

  test('consecutiveMissSessions: too few completed sets is a miss even at target reps',
      () {
    // StrongLifts fails a session on the set count, not only on the reps: four
    // clean sets of five is still a failed 5×5.
    final sets = _session('w1', '2026-02-01', 'Squat', 5, 100, 4);
    expect(consecutiveMissSessions(sets, 'Squat', _fiveByFive), 1);
  });

  test(
      'consecutiveMissSessions: a session with no completed working set is skipped, not counted',
      () {
    // Warmups-only and rep-less rows are logging artifacts, not failures —
    // three of them must not add up to a prescribed load reduction.
    final sets = [
      ..._session('w1', '2026-02-01', 'Squat', 5, 100),
      const DatedLoggedSet(
        workoutId: 'w2',
        startedAt: '2026-02-08',
        exerciseName: 'Squat',
        reps: 3,
        weightKg: 60,
        setType: 'warmup',
      ),
      _s('w3', '2026-02-15', 'Squat', null, 100),
      _s('w4', '2026-02-22', 'Squat', 0, 100),
    ];
    expect(consecutiveMissSessions(sets, 'Squat', _fiveByFive), 0);
  });

  test('consecutiveMissSessions: unlabelled warmups do not manufacture a miss streak',
      () {
    // The history RPC does not return set_type, so a ramp-up reaches the
    // reducer looking like a working set. If it were graded as one, three clean
    // 5×5 sessions would read as three misses and prescribe a deload to a
    // lifter who never missed a rep.
    List<DatedLoggedSet> clean(String id, String at) => [
          _s(id, at, 'Squat', 5, 40),
          _s(id, at, 'Squat', 3, 60),
          ..._session(id, at, 'Squat', 5, 100),
        ];
    final sets = [
      ...clean('w1', '2026-07-01'),
      ...clean('w2', '2026-07-08'),
      ...clean('w3', '2026-07-15'),
    ];
    expect(consecutiveMissSessions(sets, 'Squat', _fiveByFive), 0);
  });

  test('progressionParamsWithStreak: a non-5×5 scheme passes its params through untouched',
      () {
    final params = <String, Object?>{'incrementKg': 5};
    expect(
      progressionParamsWithStreak(
        scheme: ProgressionScheme.linear,
        params: params,
        targetRepsMin: 5,
        targetRepsMax: 5,
        history: _session('w1', '2026-01-01', 'Squat', 2, 100),
        exerciseName: 'Squat',
      ),
      same(params),
    );
    expect(
      progressionParamsWithStreak(
        scheme: ProgressionScheme.none,
        params: null,
        history: const [],
        exerciseName: 'Squat',
      ),
      isNull,
    );
  });

  test('progressionParamsWithStreak: derives the count, overriding a stale authored one',
      () {
    final out = progressionParamsWithStreak(
      scheme: ProgressionScheme.fiveByFive,
      params: {'incrementKg': 5, 'consecutiveMisses': 99},
      targetRepsMin: 5,
      targetRepsMax: 5,
      history: [
        ..._session('w1', '2026-03-01', 'Squat', 4, 100),
        ..._session('w2', '2026-03-08', 'Squat', 4, 100),
      ],
      exerciseName: 'Squat',
    );
    expect(out, {'incrementKg': 5, 'consecutiveMisses': 2});
  });

  test(
      'progressionParamsWithStreak: a routine with no rep target grades on params targetSets/targetReps',
      () {
    // The bar has to be resolved the same way the prescriber resolves it, or
    // the streak grades sessions against a 5×5 the routine never prescribed.
    final params = <String, Object?>{'targetSets': 3, 'targetReps': 3};
    final cleared = [
      ..._session('w1', '2026-06-01', 'Dip', 3, 20, 3),
      ..._session('w2', '2026-06-08', 'Dip', 3, 20, 3),
    ];
    expect(
      progressionParamsWithStreak(
        scheme: ProgressionScheme.fiveByFive,
        params: params,
        history: cleared,
        exerciseName: 'Dip',
      ),
      {...params, 'consecutiveMisses': 0},
    );
    final short = [
      ..._session('w1', '2026-06-01', 'Dip', 2, 20, 3),
      ..._session('w2', '2026-06-08', 'Dip', 2, 20, 3),
    ];
    expect(
      progressionParamsWithStreak(
        scheme: ProgressionScheme.fiveByFive,
        params: params,
        history: short,
        exerciseName: 'Dip',
      ),
      {...params, 'consecutiveMisses': 2},
    );
  });

  test('a stall of three sessions now reaches the deload the prescriber could never fire',
      () {
    // Regression: progression_params is authored at routine-build time and
    // never carried consecutiveMisses, so `misses` was always 0 and fiveByFive
    // could only ever hold. A lifter stuck at 100 kg stayed at 100 kg forever.
    final history = [
      ..._session('w1', '2026-04-01', 'Squat', 4, 100),
      ..._session('w2', '2026-04-08', 'Squat', 4, 100),
      ..._session('w3', '2026-04-15', 'Squat', 4, 100),
    ];
    final stalled = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: lastSessionSets(history, 'Squat') ?? const [],
      targetRepsMin: 5,
      targetRepsMax: 5,
      params: progressionParamsWithStreak(
        scheme: ProgressionScheme.fiveByFive,
        params: null,
        targetRepsMin: 5,
        targetRepsMax: 5,
        history: history,
        exerciseName: 'Squat',
      ),
    ));
    expect(stalled.reason, ProgressionReason.deload);
    expect(stalled.suggestedWeightKg, 90);

    // Two misses is still a hold — the third is what earns the back-off.
    final twoMisses = history.where((x) => x.workoutId != 'w3').toList();
    final held = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: lastSessionSets(twoMisses, 'Squat') ?? const [],
      targetRepsMin: 5,
      targetRepsMax: 5,
      params: progressionParamsWithStreak(
        scheme: ProgressionScheme.fiveByFive,
        params: null,
        targetRepsMin: 5,
        targetRepsMax: 5,
        history: twoMisses,
        exerciseName: 'Squat',
      ),
    ));
    expect(held.reason, ProgressionReason.hold);
    expect(held.suggestedWeightKg, 100);
  });

  test('breaking the stall clears the streak, so the next session is not deloaded',
      () {
    final history = [
      ..._session('w1', '2026-05-01', 'Squat', 4, 100),
      ..._session('w2', '2026-05-08', 'Squat', 4, 100),
      ..._session('w3', '2026-05-15', 'Squat', 4, 100),
      ..._session('w4', '2026-05-22', 'Squat', 5, 100),
    ];
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: lastSessionSets(history, 'Squat') ?? const [],
      targetRepsMin: 5,
      targetRepsMax: 5,
      params: progressionParamsWithStreak(
        scheme: ProgressionScheme.fiveByFive,
        params: null,
        targetRepsMin: 5,
        targetRepsMax: 5,
        history: history,
        exerciseName: 'Squat',
      ),
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 102.5);
  });
}
