import 'package:flutter_test/flutter_test.dart';

import '../lib/gym_routine.dart';

LoggedSet lset(String name, num? reps, num? weightKg, [num? rpe]) =>
    LoggedSet(exerciseName: name, reps: reps, weightKg: weightKg, rpe: rpe);

void main() {
  test('routineFromWorkout: groups consecutive equal names into one block', () {
    final draft = routineFromWorkout('Push day', [
      lset('Bench Press', 5, 80),
      lset('Bench Press', 5, 80),
      lset('Overhead Press', 8, 40),
    ]);
    expect(draft.title, 'Push day');
    expect(draft.exerciseCount, 2);
    expect(draft.exercises[0].exerciseName, 'Bench Press');
    expect(draft.exercises[0].sets.length, 2);
    expect(draft.exercises[1].exerciseName, 'Overhead Press');
    expect(draft.exercises[1].sets.length, 1);
  });

  test('routineFromWorkout: a re-entered exercise later is its own block', () {
    final draft = routineFromWorkout(null, [
      lset('Squat', 5, 100),
      lset('Curl', 10, 15),
      lset('Squat', 5, 100),
    ]);
    expect(draft.exercises.length, 3);
    expect(draft.exercises.map((e) => e.exerciseName).toList(),
        ['Squat', 'Curl', 'Squat']);
    expect(draft.exercises.map((e) => e.position).toList(), [0, 1, 2]);
  });

  test('routineFromWorkout: stamps exercise_key via normaliseExerciseName', () {
    final draft = routineFromWorkout(null, [lset('  Bench   Press ', 5, 80)]);
    expect(draft.exercises[0].exerciseName, 'Bench   Press');
    expect(draft.exercises[0].exerciseKey, 'bench press');
  });

  test('routineFromWorkout: logged values become planned targets', () {
    final draft = routineFromWorkout(null, [lset('Deadlift', 3, 180, 9)]);
    final s = draft.exercises[0].sets[0];
    expect(s.setIndex, 0);
    expect(s.setType, 'working');
    expect(s.targetRepsMin, 3);
    expect(s.targetRepsMax, null);
    expect(s.targetWeightKg, 180);
    expect(s.targetRpe, 9);
  });

  test('routineFromWorkout: drops blank-named sets', () {
    final draft =
        routineFromWorkout(null, [lset('   ', 5, 50), lset('Row', 8, 60)]);
    expect(draft.exercises.length, 1);
    expect(draft.exercises[0].exerciseName, 'Row');
  });

  test('routineFromWorkout: null reps/weight carry through as null targets', () {
    final draft = routineFromWorkout(null, [lset('Plank', null, null)]);
    final s = draft.exercises[0].sets[0];
    expect(s.targetRepsMin, null);
    expect(s.targetWeightKg, null);
  });

  test('routineFromWorkout: empty/whitespace title falls back', () {
    expect(routineFromWorkout('   ', [lset('X', 1, 1)]).title, 'Routine');
    expect(routineFromWorkout(null, [lset('X', 1, 1)]).title, 'Routine');
    expect(
        routineFromWorkout(null, [lset('X', 1, 1)], fallbackTitle: 'My plan')
            .title,
        'My plan');
  });

  test('routineFromWorkout: no sets yields an empty draft', () {
    final draft = routineFromWorkout('Empty', []);
    expect(draft.exerciseCount, 0);
    expect(draft.exercises, isEmpty);
  });

  test('prefillFromRoutine: orders by position and setIndex, fills targets', () {
    final routine = PlannedRoutine(title: 'Plan', exercises: [
      PlannedExercise(exerciseName: 'Overhead Press', position: 1, sets: [
        PlannedSet(setIndex: 1, targetRepsMin: 8, targetWeightKg: 40),
      ]),
      PlannedExercise(exerciseName: 'Bench Press', position: 0, sets: [
        PlannedSet(setIndex: 1, targetRepsMin: 5, targetWeightKg: 80, targetRpe: 8),
        PlannedSet(setIndex: 0, targetRepsMin: 5, targetWeightKg: 80, targetRpe: 8),
      ]),
    ]);
    final blocks = prefillFromRoutine(routine);
    expect(blocks.map((b) => b.name).toList(), ['Bench Press', 'Overhead Press']);
    expect(blocks[0].sets.length, 2);
    expect(blocks[0].sets[0].reps, '5');
    expect(blocks[0].sets[0].weightKg, 80);
    expect(blocks[0].sets[0].rpe, '8');
  });

  test('prefillFromRoutine: rep range prefills the min', () {
    final routine = PlannedRoutine(title: 'P', exercises: [
      PlannedExercise(exerciseName: 'DB Press', position: 0, sets: [
        PlannedSet(setIndex: 0, targetRepsMin: 8, targetRepsMax: 12, targetWeightKg: 20),
      ]),
    ]);
    final blocks = prefillFromRoutine(routine);
    expect(blocks[0].sets[0].reps, '8');
  });

  test('prefillFromRoutine: null targets prefill empty strings', () {
    final routine = PlannedRoutine(title: 'P', exercises: [
      PlannedExercise(exerciseName: 'Plank', position: 0, sets: [
        PlannedSet(setIndex: 0),
      ]),
    ]);
    final blocks = prefillFromRoutine(routine);
    expect(blocks[0].sets[0].reps, '');
    expect(blocks[0].sets[0].weightKg, null);
    expect(blocks[0].sets[0].rpe, '');
  });

  test('prefillFromRoutine: an empty routine yields one empty block', () {
    final blocks = prefillFromRoutine(const PlannedRoutine(title: 'P', exercises: []));
    expect(blocks.length, 1);
    expect(blocks[0].name, '');
    expect(blocks[0].sets.length, 1);
    expect(blocks[0].sets[0].reps, '');
  });

  test('prefillFromRoutine: an exercise with no sets yields one empty set', () {
    final blocks = prefillFromRoutine(PlannedRoutine(title: 'P', exercises: [
      const PlannedExercise(exerciseName: 'Squat', position: 0, sets: []),
    ]));
    expect(blocks[0].name, 'Squat');
    expect(blocks[0].sets.length, 1);
    expect(blocks[0].sets[0].reps, '');
  });
}
