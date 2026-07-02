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
}
