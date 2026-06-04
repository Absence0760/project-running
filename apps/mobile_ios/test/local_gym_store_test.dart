import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gym_store.dart';

/// Fake [ApiClient] that records gym CRUD calls and lets a test inject
/// per-method failure modes. Tracks the order of operations so we can
/// assert the drain order (create → update → delete) and the sets that
/// travelled with each create/update.
class _FakeGymApi extends ApiClient {
  final List<String> calls = [];
  final Map<String, List<GymSetInput>> sentSets = {};
  Set<String> failedCreates = const {};
  Set<String> failedUpdates = const {};
  Set<String> failedDeletes = const {};

  @override
  Future<GymWorkoutRow> createGymWorkout({
    String? id,
    String? title,
    required DateTime startedAt,
    int? durationS,
    String? notes,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
    List<GymSetInput> sets = const [],
  }) async {
    calls.add('create:$id');
    sentSets['create:$id'] = sets;
    if (failedCreates.contains(id)) throw StateError('create failed');
    return GymWorkoutRow(
      id: id ?? 'server-generated',
      userId: 'test-user',
      title: title,
      startedAt: startedAt,
      durationS: durationS,
      notes: notes,
      isPublic: isPublic,
      externalId: externalId,
      lastModifiedAt: lastModifiedAt ?? DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> updateGymWorkout(
    String id, {
    String? title,
    int? durationS,
    String? notes,
    bool? isPublic,
    DateTime? lastModifiedAt,
    List<GymSetInput>? sets,
  }) async {
    calls.add('update:$id');
    if (sets != null) sentSets['update:$id'] = sets;
    if (failedUpdates.contains(id)) throw StateError('update failed');
  }

  @override
  Future<void> deleteGymWorkout(String id) async {
    calls.add('delete:$id');
    if (failedDeletes.contains(id)) throw StateError('delete failed');
  }
}

GymSetInput _set(String name, {int? reps, double? kg, double? rpe}) =>
    (exerciseName: name, reps: reps, weightKg: kg, rpe: rpe);

({Map<String, dynamic> workout, List<Map<String, dynamic>> sets}) _serverWorkout(
  String id, {
  String? title,
  DateTime? startedAt,
  DateTime? lastModifiedAt,
  List<Map<String, dynamic>> sets = const [],
}) =>
    (
      workout: {
        'id': id,
        'title': title,
        'started_at':
            (startedAt ?? DateTime.utc(2026, 6, 1)).toIso8601String(),
        'duration_s': null,
        'notes': null,
        'is_public': false,
        'external_id': null,
        'last_modified_at':
            (lastModifiedAt ?? DateTime.utc(2026, 6, 1)).toIso8601String(),
        'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
      },
      sets: sets,
    );

/// Tests for [LocalGymStore] — the disk-backed offline gym cache.
/// Mirrors the [LocalGearStore] coverage pattern: lifecycle (create /
/// update / delete) + drain semantics + reload after restart, plus the
/// gym-specific inline-sets handling.
void main() {
  late Directory dir;
  late LocalGymStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_gym_store_test_');
    store = LocalGymStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('createLocal', () {
    test('mints a v4 UUID and marks the workout pendingCreate', () async {
      final stored = await store.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 2, 8),
        sets: [_set('Bench', reps: 8, kg: 60, rpe: 8)],
      );
      expect(
          stored.id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(stored.syncState, GymSyncState.pendingCreate);
      expect(stored.sets, hasLength(1));
      expect(stored.sets.first['exercise_name'], 'Bench');
      expect(store.workouts, hasLength(1));
      expect(store.hasPending, isTrue);
    });

    test('survives a store reload with its sets', () async {
      await store.createLocal(
        title: 'Leg day',
        startedAt: DateTime.utc(2026, 6, 2),
        sets: [_set('Squat', reps: 5, kg: 100), _set('Squat', reps: 5, kg: 100)],
      );
      final fresh = LocalGymStore();
      await fresh.init(overrideDirectory: dir);
      expect(fresh.workouts, hasLength(1));
      expect(fresh.workouts.first.row['title'], 'Leg day');
      expect(fresh.workouts.first.sets, hasLength(2));
      expect(fresh.workouts.first.sets.last['weight_kg'], 100);
    });

    test('workouts are sorted newest-started first', () async {
      await store.createLocal(
          title: 'Older', startedAt: DateTime.utc(2026, 6, 1));
      await store.createLocal(
          title: 'Newer', startedAt: DateTime.utc(2026, 6, 3));
      expect(store.workouts.first.row['title'], 'Newer');
      expect(store.workouts.last.row['title'], 'Older');
    });
  });

  group('schema version (_v)', () {
    test('a persisted record carries the current schema version', () async {
      final stored =
          await store.createLocal(startedAt: DateTime.utc(2026, 6, 2));
      final raw = jsonDecode(
              File('${dir.path}/${stored.id}.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(raw[kLocalStoreVersionKey], kLocalStoreSchemaVersion);
    });

    test('a legacy (unstamped) record still loads via the migration hook',
        () async {
      final legacy = {
        'row': {
          'id': 'legacy',
          'title': 'Old',
          'started_at': DateTime.utc(2026, 6, 1).toIso8601String(),
          'duration_s': null,
          'notes': null,
          'is_public': false,
          'external_id': null,
          'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
          'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
        },
        'sets': const [],
        'sync_state': 'synced',
        'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
      };
      File('${dir.path}/legacy.json').writeAsStringSync(jsonEncode(legacy));

      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.byId('legacy'), isNotNull);
    });
  });

  group('updateLocal', () {
    test('pendingCreate stays pendingCreate and replaces sets', () async {
      final stored = await store.createLocal(
        title: 'Draft',
        startedAt: DateTime.utc(2026, 6, 2),
        sets: [_set('Bench', reps: 8, kg: 60)],
      );
      await store.updateLocal(stored.id,
          title: 'Push day', sets: [_set('Bench', reps: 10, kg: 62.5)]);
      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts.first.syncState, GymSyncState.pendingCreate);
      expect(reloaded.workouts.first.row['title'], 'Push day');
      expect(reloaded.workouts.first.sets.single['reps'], 10);
    });

    test('flips synced→pendingUpdate', () async {
      await store.replaceFromServer([_serverWorkout('abc-123', title: 'Old')]);
      expect(store.hasPending, isFalse);
      await store.updateLocal('abc-123', title: 'Edited');
      expect(store.hasPending, isTrue);
      expect(store.byId('abc-123')!.row['title'], 'Edited');
    });

    test('omitted set list is preserved on a field-only edit', () async {
      final stored = await store.createLocal(
        startedAt: DateTime.utc(2026, 6, 2),
        sets: [_set('Bench', reps: 8, kg: 60)],
      );
      await store.updateLocal(stored.id, title: 'Renamed');
      expect(store.byId(stored.id)!.sets, hasLength(1));
    });
  });

  group('deleteLocal', () {
    test('pendingCreate workouts disappear without a tombstone', () async {
      final stored =
          await store.createLocal(startedAt: DateTime.utc(2026, 6, 2));
      await store.deleteLocal(stored.id);
      expect(store.workouts, isEmpty);
      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts, isEmpty);
      expect(reloaded.hasPending, isFalse);
    });

    test('synced workouts become pendingDelete tombstones', () async {
      await store.replaceFromServer([_serverWorkout('abc-123')]);
      await store.deleteLocal('abc-123');
      expect(store.workouts, isEmpty,
          reason: 'tombstones don\'t appear in the live list');
      expect(store.byId('abc-123'), isNull);
      expect(store.hasPending, isTrue);
    });
  });

  group('replaceFromServer', () {
    test('overwrites synced rows but preserves pendingCreate', () async {
      final mine =
          await store.createLocal(title: 'Mine', startedAt: DateTime.utc(2026, 6, 2));
      await store.replaceFromServer([_serverWorkout('server-1', title: 'Server')]);
      expect(store.workouts.any((w) => w.id == mine.id), isTrue,
          reason: 'pendingCreate workout must survive a server refresh');
      expect(store.workouts.any((w) => w.id == 'server-1'), isTrue);
    });

    test('preserves pendingUpdate edits across refresh', () async {
      await store.replaceFromServer([_serverWorkout('abc-123', title: 'Server')]);
      await store.updateLocal('abc-123', title: 'My edit');
      await store.replaceFromServer([_serverWorkout('abc-123', title: 'Server')]);
      expect(store.byId('abc-123')!.row['title'], 'My edit',
          reason: 'pendingUpdate edits override the server copy until drained');
    });

    test('hydrates server sets', () async {
      await store.replaceFromServer([
        _serverWorkout('abc-123', sets: [
          {'exercise_name': 'Deadlift', 'reps': 3, 'weight_kg': 140, 'rpe': 9},
        ]),
      ]);
      expect(store.byId('abc-123')!.sets.single['exercise_name'], 'Deadlift');
    });

    test('newer-wins: a stale server fetch does not clobber a locally-newer '
        'synced copy', () async {
      await store.replaceFromServer([
        _serverWorkout('w1',
            title: 'Recent', lastModifiedAt: DateTime.utc(2026, 6, 2)),
      ]);
      // A second fetch returns an OLDER copy (read-replica lag) — must keep
      // the more-recent local copy.
      await store.replaceFromServer([
        _serverWorkout('w1',
            title: 'Stale', lastModifiedAt: DateTime.utc(2026, 6, 1)),
      ]);
      expect(store.byId('w1')!.row['title'], 'Recent');
    });

    test('newer-wins: a newer server fetch overwrites the synced copy',
        () async {
      await store.replaceFromServer([
        _serverWorkout('w1',
            title: 'Old', lastModifiedAt: DateTime.utc(2026, 6, 1)),
      ]);
      await store.replaceFromServer([
        _serverWorkout('w1',
            title: 'New', lastModifiedAt: DateTime.utc(2026, 6, 2)),
      ]);
      expect(store.byId('w1')!.row['title'], 'New');
    });
  });

  group('_rewriteAll crash-atomic ordering', () {
    List<String> jsonFiles() => dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .toList();
    List<String> tmpFiles() => dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.tmp'))
        .toList();

    test('removes files for ids dropped server-side, keeps pending, no temp '
        'files left', () async {
      await store.replaceFromServer([
        _serverWorkout('w1', title: 'One'),
        _serverWorkout('w2', title: 'Two'),
      ]);
      final mine = await store.createLocal(
          title: 'Offline', startedAt: DateTime.utc(2026, 6, 4));
      expect(jsonFiles(), hasLength(3));

      // Server no longer returns w2 — replaceFromServer must clean up its
      // orphaned file without wiping the directory or losing the pending
      // create.
      await store.replaceFromServer([_serverWorkout('w1', title: 'One')]);

      expect(store.byId('w1'), isNotNull);
      expect(store.byId('w2'), isNull);
      expect(store.byId(mine.id), isNotNull,
          reason: 'pendingCreate survives the rewrite');
      expect(tmpFiles(), isEmpty, reason: 'atomic writes leave no .tmp behind');

      // The on-disk state must match the live rows exactly — a fresh store
      // reads back only w1 + the pending create.
      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts.map((w) => w.id).toSet(), {'w1', mine.id});
    });

    test('per-write failure isolation: one bad row keeps its prior state, '
        'other rows still rewrite, orphans still cleaned', () async {
      // A directory sitting where a row file should be makes that row's
      // atomic rename fail, while the other rows write normally.
      Directory('${dir.path}/bad.json').createSync();
      // A stale file for an id no longer in the store — must be cleaned.
      File('${dir.path}/orphan.json').writeAsStringSync('{}');

      // replaceFromServer rebuilds _rows then calls _rewriteAll. The 'bad'
      // write throws; without per-write isolation the whole rewrite would
      // abort (ok-2 unwritten, orphan never deleted) and the exception
      // would surface here.
      await store.replaceFromServer([
        _serverWorkout('ok-1', title: 'One'),
        _serverWorkout('ok-2', title: 'Two'),
        _serverWorkout('bad', title: 'Bad'),
      ]);

      expect(jsonFiles(), containsAll(['ok-1.json', 'ok-2.json']),
          reason: 'the good rows write despite the bad one failing');
      expect(jsonFiles(), isNot(contains('orphan.json')),
          reason: 'orphan cleanup still runs after a write failure');
      expect(Directory('${dir.path}/bad.json').existsSync(), isTrue,
          reason: "the bad row's prior on-disk state is kept, not deleted");
      expect(tmpFiles(), isEmpty,
          reason: 'a failed atomic write cleans up its own .tmp sibling');
      expect(store.byId('ok-1'), isNotNull);
      expect(store.byId('ok-2'), isNotNull);
    });
  });

  group('syncWithServer drain', () {
    test('drains pendingCreate via createGymWorkout with the local id + sets',
        () async {
      final api = _FakeGymApi();
      final stored = await store.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 2),
        sets: [_set('Bench', reps: 8, kg: 60)],
      );

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'create:${stored.id}',
          reason:
              'pendingCreate must use the local-minted id so server + cache stay in lockstep.');
      expect(api.sentSets['create:${stored.id}']!.single.exerciseName, 'Bench');
      expect(store.hasPending, isFalse);
    });

    test('drains pendingUpdate via updateGymWorkout', () async {
      await store.replaceFromServer([_serverWorkout('srv-1', title: 'Old')]);
      await store.updateLocal('srv-1',
          title: 'New', sets: [_set('Row', reps: 12, kg: 40)]);
      final api = _FakeGymApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'update:srv-1');
      expect(api.sentSets['update:srv-1']!.single.exerciseName, 'Row');
      expect(store.hasPending, isFalse);
    });

    test('drains pendingDelete via deleteGymWorkout + drops the local row',
        () async {
      await store.replaceFromServer([_serverWorkout('kill-me')]);
      await store.deleteLocal('kill-me');
      final api = _FakeGymApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'delete:kill-me');
      expect(store.byId('kill-me'), isNull);
      expect(store.hasPending, isFalse);
    });

    test('mixed queue: every state hits the server', () async {
      await store.replaceFromServer([
        _serverWorkout('sync-edit', title: 'Old'),
        _serverWorkout('sync-kill'),
      ]);
      final created =
          await store.createLocal(title: 'Fresh', startedAt: DateTime.utc(2026, 6, 2));
      await store.updateLocal('sync-edit', title: 'Edited');
      await store.deleteLocal('sync-kill');

      final api = _FakeGymApi();
      final drained = await store.syncWithServer(api);

      expect(drained, 3);
      expect(
          api.calls,
          containsAll(
              ['create:${created.id}', 'update:sync-edit', 'delete:sync-kill']));
      expect(store.workouts.map((w) => w.id).toSet(), {'sync-edit', created.id});
    });

    test('per-row failure isolation: failing create leaves the row pending',
        () async {
      final stored =
          await store.createLocal(startedAt: DateTime.utc(2026, 6, 2));
      final api = _FakeGymApi()..failedCreates = {stored.id};

      final drained = await store.syncWithServer(api);

      expect(drained, 0);
      expect(store.hasPending, isTrue);
    });

    test('clean store: syncWithServer is a no-op (drained=0)', () async {
      final api = _FakeGymApi();
      final drained = await store.syncWithServer(api);
      expect(drained, 0);
      expect(api.calls, isEmpty);
    });
  });
}
