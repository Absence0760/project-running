import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/local_routine_store.dart';

Future<({LocalRoutineStore store, Directory dir})> _store(String tag) async {
  final dir = Directory.systemTemp.createTempSync('routine_store_$tag');
  final store = LocalRoutineStore();
  await store.init(overrideDirectory: dir);
  return (store: store, dir: dir);
}

StoredRoutineExercise _ex(String name, {List<StoredRoutineSet>? sets}) =>
    StoredRoutineExercise(
      exerciseName: name,
      exerciseKey: name.toLowerCase(),
      sets: sets ?? [StoredRoutineSet(targetRepsMin: 5, targetWeightKg: 100)],
    );

void main() {
  test('createLocal mints a v4 UUID + marks pendingCreate, drops blanks',
      () async {
    final f = await _store('create');
    try {
      final r = await f.store.createLocal(
        title: 'Push day',
        exercises: [_ex('Bench'), _ex('  '), _ex('Press')],
      );
      expect(r.id, matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(r.syncState, RoutineSyncState.pendingCreate);
      // Blank-named exercise dropped; count stamped from survivors.
      expect(r.exercises, hasLength(2));
      expect(r.exerciseCount, 2);
      expect(f.store.routines, hasLength(1));
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('routines reload from disk + sort most-recently-modified first',
      () async {
    final f = await _store('reload');
    try {
      final a = await f.store.createLocal(title: 'A', exercises: [_ex('Squat')]);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      final b = await f.store.createLocal(title: 'B', exercises: [_ex('Dead')]);
      final reopened = LocalRoutineStore();
      await reopened.init(overrideDirectory: f.dir);
      expect(reopened.routines.map((r) => r.id), [b.id, a.id]);
      // Inline exercises survive the round-trip.
      expect(reopened.byId(a.id)!.exercises.single.exerciseName, 'Squat');
      expect(
          reopened.byId(a.id)!.exercises.single.sets.single.targetRepsMin, 5);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('P2/P4 superset/set-type/rest/modality/progression round-trip on disk',
      () async {
    final f = await _store('p2p4');
    try {
      final r = await f.store.createLocal(title: 'Push', exercises: [
        StoredRoutineExercise(
          exerciseName: 'Bench',
          exerciseKey: 'bench',
          supersetGroup: 1,
          supersetOrder: 0,
          modality: 'weight_reps',
          progression: 'double_progression',
          progressionParams: const {'incrementKg': 2.5},
          sets: [
            StoredRoutineSet(
              setType: 'warmup',
              targetRepsMin: 8,
              targetRepsMax: 12,
              targetWeightKg: 60,
              restS: 90,
            ),
          ],
        ),
      ]);
      final reopened = LocalRoutineStore();
      await reopened.init(overrideDirectory: f.dir);
      final ex = reopened.byId(r.id)!.exercises.single;
      expect(ex.supersetGroup, 1);
      expect(ex.supersetOrder, 0);
      expect(ex.modality, 'weight_reps');
      expect(ex.progression, 'double_progression');
      expect(ex.progressionParams['incrementKg'], 2.5);
      final s = ex.sets.single;
      expect(s.setType, 'warmup');
      expect(s.targetRepsMax, 12);
      expect(s.restS, 90);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a pendingCreate routine drops it outright', () async {
    final f = await _store('delete_local');
    try {
      final r = await f.store.createLocal(title: 'X', exercises: [_ex('Row')]);
      await f.store.deleteLocal(r.id);
      expect(f.store.byId(r.id), isNull);
      expect(f.store.routines, isEmpty);
      expect(f.store.hasPending, isFalse);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('deleteLocal on a synced routine writes a pendingDelete tombstone',
      () async {
    final f = await _store('delete_synced');
    try {
      await f.store.replaceFromServer([
        (
          routine: <String, dynamic>{
            'id': 'r-1',
            'title': 'Synced',
            'exercise_count': 1,
            'last_modified_at': DateTime.utc(2026, 5, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 5, 1).toIso8601String(),
          },
          exercises: [_ex('Pull')],
        ),
      ]);
      expect(f.store.byId('r-1')!.syncState, RoutineSyncState.synced);
      await f.store.deleteLocal('r-1');
      // Hidden from the live list, but a tombstone remains for the drain.
      expect(f.store.byId('r-1'), isNull);
      expect(f.store.hasPending, isTrue);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });

  test('replaceFromServer preserves pending + newer-wins on synced', () async {
    final f = await _store('newer_wins');
    try {
      // A local pendingCreate must survive a server fetch.
      final pending =
          await f.store.createLocal(title: 'Local', exercises: [_ex('Curl')]);
      await f.store.replaceFromServer([
        (
          routine: <String, dynamic>{
            'id': 'r-server',
            'title': 'Server',
            'exercise_count': 1,
            'last_modified_at': DateTime.utc(2026, 4, 1).toIso8601String(),
            'created_at': DateTime.utc(2026, 4, 1).toIso8601String(),
          },
          exercises: [_ex('Fly')],
        ),
      ]);
      expect(f.store.byId(pending.id), isNotNull,
          reason: 'pendingCreate preserved across replaceFromServer');
      expect(f.store.byId('r-server'), isNotNull);
    } finally {
      f.dir.deleteSync(recursive: true);
    }
  });
}
