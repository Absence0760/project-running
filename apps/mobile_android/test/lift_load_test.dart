import 'package:flutter_test/flutter_test.dart';
import 'package:core_models/core_models.dart';
import 'package:mobile_android/lift_load.dart';
import 'package:mobile_android/training_load.dart';

void main() {
  group('liftsFromSetHistory (mirror of web lift_load.test.ts)', () {
    test('groups flat set rows by workout into LiftForLoad sessions', () {
      final out = liftsFromSetHistory(const [
        SetWithWorkoutDate(
            workoutId: 'w1',
            startedAt: '2026-06-03T08:00:00Z',
            reps: 5,
            weightKg: 60,
            rpe: 8),
        SetWithWorkoutDate(
            workoutId: 'w1',
            startedAt: '2026-06-03T08:00:00Z',
            reps: 5,
            weightKg: 60,
            rpe: null),
        SetWithWorkoutDate(
            workoutId: 'w2',
            startedAt: '2026-06-01T18:00:00Z',
            reps: 8,
            weightKg: 40,
            rpe: null),
      ]);
      expect(out.length, 2);
      final w1 = out.firstWhere(
          (l) => l.startedAt == DateTime.parse('2026-06-03T08:00:00Z'));
      expect(w1.sets.length, 2);
      expect(w1.sets[0].reps, 5);
      expect(w1.sets[0].weightKg, 60);
      expect(w1.sets[0].rpe, 8);
    });

    test('drops rows with no workout date or id (cannot land on a day)', () {
      final out = liftsFromSetHistory(const [
        SetWithWorkoutDate(
            workoutId: 'w1', startedAt: '', reps: 5, weightKg: 60, rpe: 8),
        SetWithWorkoutDate(
            workoutId: '',
            startedAt: '2026-06-03T08:00:00Z',
            reps: 5,
            weightKg: 60,
            rpe: 8),
      ]);
      expect(out, isEmpty);
    });

    test('grouped lifts raise the load series vs runs-only (separability)', () {
      final end = DateTime.parse('2026-06-10T12:00:00Z');
      final lifts = liftsFromSetHistory(const [
        SetWithWorkoutDate(
            workoutId: 'w1',
            startedAt: '2026-06-09T08:00:00Z',
            reps: 8,
            weightKg: 100,
            rpe: 8),
        SetWithWorkoutDate(
            workoutId: 'w1',
            startedAt: '2026-06-09T08:00:00Z',
            reps: 8,
            weightKg: 100,
            rpe: 8),
        SetWithWorkoutDate(
            workoutId: 'w1',
            startedAt: '2026-06-09T08:00:00Z',
            reps: 8,
            weightKg: 100,
            rpe: 8),
      ]);
      final runsOnly = computeTrainingLoadSeries(const <Run>[],
          windowDays: 30, endDate: end);
      final withLifts = computeTrainingLoadSeries(const <Run>[],
          windowDays: 30, endDate: end, lifts: lifts);
      final liftDay = withLifts.firstWhere((p) => p.liftStress > 0);
      expect(liftDay.runStress, 0, reason: 'no runs → run stress stays 0');
      expect(runsOnly.last.atl, 0, reason: 'run-only curve recoverable');
      expect(withLifts.last.atl, greaterThan(0), reason: 'lifts raise fatigue');
    });
  });
}
