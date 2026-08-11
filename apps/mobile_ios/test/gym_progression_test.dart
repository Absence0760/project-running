import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_progression.dart';

ProgressionSetLike s(num? reps, num? weightKg, [num? rpe]) =>
    ProgressionSetLike(reps: reps, weightKg: weightKg, rpe: rpe);

void main() {
  test('none scheme suggests nothing', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.none,
      lastSets: [s(5, 100)],
    ));
    expect(out.suggestedWeightKg, isNull);
    expect(out.suggestedRepsMin, isNull);
    expect(out.suggestedRepsMax, isNull);
    expect(out.reason, ProgressionReason.none);
  });

  test('linear: all sets hit top reps -> +2.5kg increase_weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(5, 100), s(5, 100), s(5, 100)],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 102.5);
  });

  test('linear: a missed set -> hold at the same weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(5, 100), s(4, 100), s(5, 100)],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(out.reason, ProgressionReason.hold);
    expect(out.suggestedWeightKg, 100);
  });

  test('double_progression: below repsMax -> increase_reps, same weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.doubleProgression,
      lastSets: [s(8, 60), s(8, 60), s(8, 60)],
      targetRepsMin: 8,
      targetRepsMax: 12,
    ));
    expect(out.reason, ProgressionReason.increaseReps);
    expect(out.suggestedWeightKg, 60);
    expect(out.suggestedRepsMax, 12);
  });

  test('double_progression: at repsMax -> +2.5kg, reset reps to repsMin', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.doubleProgression,
      lastSets: [s(12, 60), s(12, 60), s(12, 60)],
      targetRepsMin: 8,
      targetRepsMax: 12,
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 62.5);
    expect(out.suggestedRepsMin, 8);
    expect(out.suggestedRepsMax, 8);
  });

  test('five_by_five: 5x5 success -> +2.5kg', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(5, 80)],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 82.5);
  });

  test('five_by_five: one rep short -> hold', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(4, 80)],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(out.reason, ProgressionReason.hold);
    expect(out.suggestedWeightKg, 80);
  });

  test('five_by_five: 3 consecutive misses -> deload', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: [s(5, 80), s(5, 80), s(5, 80), s(5, 80), s(3, 80)],
      targetRepsMin: 5,
      targetRepsMax: 5,
      params: const {'consecutiveMisses': 3},
    ));
    expect(out.reason, ProgressionReason.deload);
    expect(out.suggestedWeightKg, 72);
  });

  test('percent_cycle: prescribes params.percent * oneRmKg', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.percentCycle,
      lastSets: [s(3, 120)],
      params: const {'percent': 0.85, 'oneRmKg': 150},
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 127.5);
  });

  test('percent_cycle: prescription below last top weight -> hold', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.percentCycle,
      lastSets: [s(3, 120)],
      params: const {'percent': 0.7, 'oneRmKg': 100},
    ));
    expect(out.suggestedWeightKg, 70);
    expect(out.reason, ProgressionReason.hold);
  });

  test('percent_cycle: first/bodyweight session (no prior top weight) -> establishBaseline, not hold', () {
    // Regression: a concrete percentage-of-1RM prescription with no prior top
    // weight (first session, or a bodyweight-logged one) was mislabelled hold —
    // there was nothing to hold. The weight value is unchanged; only the label.
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.percentCycle,
      lastSets: [s(3, null)],
      params: const {'percent': 0.85, 'oneRmKg': 150},
    ));
    expect(out.reason, ProgressionReason.establishBaseline);
    expect(out.suggestedWeightKg, 127.5);
  });

  test('rpe_autoreg: achieved RPE below target -> increase_weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.rpeAutoreg,
      lastSets: [s(5, 100, 7), s(5, 100, 7.5)],
      params: const {'targetRpe': 8},
    ));
    expect(out.reason, ProgressionReason.increaseWeight);
    expect(out.suggestedWeightKg, 102.5);
  });

  test('rpe_autoreg: achieved RPE above target -> hold', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.rpeAutoreg,
      lastSets: [s(5, 100, 9), s(5, 100, 9.5)],
      params: const {'targetRpe': 8},
    ));
    expect(out.reason, ProgressionReason.hold);
    expect(out.suggestedWeightKg, 100);
  });

  test('empty lastSets -> hold (or none for none scheme)', () {
    final held = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: const [],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(held.reason, ProgressionReason.hold);
    final noneOut = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.none,
      lastSets: [],
    ));
    expect(noneOut.reason, ProgressionReason.none);
  });

  test('null weights (bodyweight) -> reps-only suggestion, never a weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(10, null), s(10, null), s(10, null)],
      targetRepsMin: 10,
      targetRepsMax: 10,
    ));
    expect(out.suggestedWeightKg, isNull);
    expect(out.reason, ProgressionReason.increaseReps);
  });

  test('linear bodyweight success raises the rep target, never re-prescribes the same count', () {
    // Regression: a maxed bodyweight linear set used to return the UNCHANGED reps
    // while labelling it increaseReps — mirrors the web twin's pinning test.
    final single = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(10, null), s(10, null)],
      targetRepsMin: 10,
      targetRepsMax: null,
    ));
    expect(single.suggestedWeightKg, isNull);
    expect(single.reason, ProgressionReason.increaseReps);
    expect(single.suggestedRepsMin, 11);
    expect(single.suggestedRepsMax, isNull);

    final range = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(8, null), s(8, null)],
      targetRepsMin: 6,
      targetRepsMax: 8,
    ));
    expect(range.suggestedWeightKg, isNull);
    expect(range.reason, ProgressionReason.increaseReps);
    expect(range.suggestedRepsMin, 6);
    expect(range.suggestedRepsMax, 9);
  });

  test('rpe_autoreg bodyweight below target raises the rep target, never re-prescribes the same count', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.rpeAutoreg,
      lastSets: [s(8, null, 6), s(8, null, 6.5)],
      targetRepsMin: 8,
      targetRepsMax: null,
      params: const {'targetRpe': 8},
    ));
    expect(out.suggestedWeightKg, isNull);
    expect(out.reason, ProgressionReason.increaseReps);
    expect(out.suggestedRepsMin, 9);
    expect(out.suggestedRepsMax, isNull);
  });

  test('double_progression bodyweight at top of range raises the rep ceiling, never reduces it', () {
    // Regression: a maxed bodyweight range used to collapse to repsMin (12 → 8)
    // while reporting increaseReps — a reduction mislabelled as progress.
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.doubleProgression,
      lastSets: [s(12, null), s(12, null)],
      targetRepsMin: 8,
      targetRepsMax: 12,
    ));
    expect(out.suggestedWeightKg, isNull);
    expect(out.reason, ProgressionReason.increaseReps);
    expect(out.suggestedRepsMax, 13);
    expect((out.suggestedRepsMax ?? 0) > 12, isTrue);
  });

  test('five_by_five bodyweight success raises the rep target, never re-prescribes the same count', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: [s(5, null), s(5, null), s(5, null), s(5, null), s(5, null)],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(out.suggestedWeightKg, isNull);
    expect(out.reason, ProgressionReason.increaseReps);
    expect(out.suggestedRepsMin, 6);
    expect(out.suggestedRepsMax, 6);
  });

  test('negative/zero params never suggest a negative weight', () {
    final out = nextPrescription(ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [s(5, 100), s(5, 100)],
      targetRepsMin: 5,
      targetRepsMax: 5,
      params: const {'incrementKg': -200},
    ));
    expect(out.suggestedWeightKg, isNotNull);
    expect(out.suggestedWeightKg! > 0, isTrue);
  });

  test('the load anchor is a weight the lifter completed, never one they missed',
      () {
    // `gym_sets.reps` is nullable and CHECK-allows 0, and the composer writes a
    // row for every set typed — so a failed top single logged as 0 reps, or a
    // set whose weight was entered before the reps, are normal stored shapes.
    // _topWeight scanned the raw list, so the missed 110 became the anchor and
    // the increment was added to IT: the app told the lifter to try 112.5 after
    // they had just failed 110.
    const threeGoodSets = [
      ProgressionSetLike(reps: 5, weightKg: 100),
      ProgressionSetLike(reps: 5, weightKg: 100),
      ProgressionSetLike(reps: 5, weightKg: 100),
    ];
    for (final missed in const [
      ProgressionSetLike(reps: 0, weightKg: 110),
      ProgressionSetLike(reps: null, weightKg: 110),
    ]) {
      final got = nextPrescription(ProgressionInput(
        scheme: ProgressionScheme.linear,
        lastSets: [...threeGoodSets, missed],
        targetRepsMin: 5,
        targetRepsMax: 5,
      ));
      expect(got.suggestedWeightKg, 102.5);
      expect(got.reason, ProgressionReason.increaseWeight);
    }
  });

  test('a missed heavier attempt does not inflate a hold either', () {
    final got = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [
        ProgressionSetLike(reps: 5, weightKg: 100),
        ProgressionSetLike(reps: 3, weightKg: 100),
        ProgressionSetLike(reps: 0, weightKg: 120),
      ],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(got.reason, ProgressionReason.hold);
    expect(got.suggestedWeightKg, 100);
  });

  test('a warmup set does not count as a failed working set', () {
    // The prescriber judges "did they hit the target?" with an `every` over the
    // completed sets. gym_sets.set_type has existed since 20270101_001 and the
    // composer writes it, but ProgressionSetLike dropped the column — so a
    // 2-rep ramp-up read as a working set that missed a 5-rep target and held
    // the load. Since the lifter warms up again next session, the stall
    // repeats: anyone who warms up never gets an increase at all.
    const working = [
      ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
      ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
      ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
    ];
    const withRamp = [
      ProgressionSetLike(reps: 5, weightKg: 40, setType: 'warmup'),
      ProgressionSetLike(reps: 3, weightKg: 60, setType: 'warmup'),
      ProgressionSetLike(reps: 2, weightKg: 80, setType: 'warmup'),
      ...working,
    ];
    final bare = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: working,
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    final ramped = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: withRamp,
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(bare.reason, ProgressionReason.increaseWeight);
    expect(ramped.reason, bare.reason);
    expect(ramped.suggestedWeightKg, bare.suggestedWeightKg);
  });

  test('a null set_type is treated as working', () {
    final got = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [
        ProgressionSetLike(reps: 5, weightKg: 100),
        ProgressionSetLike(reps: 5, weightKg: 100),
      ],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(got.reason, ProgressionReason.increaseWeight);
    expect(got.suggestedWeightKg, 102.5);
  });

  test('warmups do not pad the five_by_five completed-set count', () {
    final got = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.fiveByFive,
      lastSets: [
        ProgressionSetLike(reps: 5, weightKg: 40, setType: 'warmup'),
        ProgressionSetLike(reps: 5, weightKg: 60, setType: 'warmup'),
        ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
        ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
        ProgressionSetLike(reps: 5, weightKg: 100, setType: 'working'),
      ],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(got.reason, isNot(ProgressionReason.increaseWeight));
  });

  test('a warmup-only session yields no working evidence', () {
    final got = nextPrescription(const ProgressionInput(
      scheme: ProgressionScheme.linear,
      lastSets: [
        ProgressionSetLike(reps: 5, weightKg: 40, setType: 'warmup'),
        ProgressionSetLike(reps: 3, weightKg: 60, setType: 'warmup'),
      ],
      targetRepsMin: 5,
      targetRepsMax: 5,
    ));
    expect(got.reason, ProgressionReason.hold);
    expect(got.suggestedWeightKg, isNull);
  });
}
