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
    Map<String, dynamic>? metadata,
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
      setCount: sets.length,
      volumeKg: sets.fold(
        0.0,
        (sum, s) => sum + (s.reps ?? 0) * (s.weightKg ?? 0),
      ),
      lastModifiedAt: lastModifiedAt ?? DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
      metadata: const <String, dynamic>{},
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
    Map<String, dynamic>? metadata,
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

GymSetInput _set(String name,
        {int? reps, double? kg, double? rpe, int? durationS}) =>
    (
      exerciseName: name,
      reps: reps,
      weightKg: kg,
      rpe: rpe,
      durationS: durationS,
    );

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
        'set_count': sets.length,
        'volume_kg': sets.fold<double>(
          0,
          (sum, s) =>
              sum +
              ((s['reps'] as num?) ?? 0) * ((s['weight_kg'] as num?) ?? 0),
        ),
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

  group('workouts cache (revision-keyed)', () {
    test('repeated reads with no mutation return the identical cached list',
        () async {
      await store.createLocal(
        title: 'A',
        startedAt: DateTime.utc(2026, 6, 1),
        sets: [_set('Bench', reps: 5, kg: 60)],
      );
      final first = store.workouts;
      final second = store.workouts;
      expect(identical(first, second), isTrue,
          reason: 'A read with no intervening mutation must hit the cache, '
              'not re-sort the whole history.');
    });

    test('a mutation invalidates the cache and the new workout sorts in',
        () async {
      await store.createLocal(
        title: 'older',
        startedAt: DateTime.utc(2026, 6, 1),
        sets: [_set('Bench', reps: 5, kg: 60)],
      );
      final before = store.workouts;
      expect(before, hasLength(1));
      await store.createLocal(
        title: 'newer',
        startedAt: DateTime.utc(2026, 6, 5),
        sets: [_set('Squat', reps: 5, kg: 100)],
      );
      final after = store.workouts;
      expect(identical(before, after), isFalse,
          reason: 'A mutation must bump storeRevision so the getter recomputes.');
      expect(after, hasLength(2));
      expect(after.first.row['title'], 'newer',
          reason: 'Newest-started stays first after the cache refresh.');
    });
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

    test(
        'a count-windowed fetch (fetchLimit) preserves synced rows older than '
        'the returned page — does not wipe history beyond the newest N',
        () async {
      // Seed two synced workouts: an old one (Jan) and a newer one (Jun).
      await store.replaceFromServer([
        _serverWorkout('old', title: 'January', startedAt: DateTime.utc(2026, 1, 1)),
        _serverWorkout('new', title: 'June', startedAt: DateTime.utc(2026, 6, 1)),
      ]);
      expect(store.byId('old'), isNotNull);

      // A later "newest N" hydrate returns a FULL page (limit 1) of only the
      // newest workout. The old one is outside the fetch window, so it must be
      // preserved rather than pruned as if deleted.
      await store.replaceFromServer(
        [_serverWorkout('new', title: 'June', startedAt: DateTime.utc(2026, 6, 1))],
        fetchLimit: 1,
      );
      expect(store.byId('old'), isNotNull,
          reason: 'a synced workout older than the page must survive');
      expect(store.byId('new'), isNotNull);

      // The on-disk state must agree — a fresh store still reads both back.
      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.byId('old'), isNotNull);
    });

    test(
        'a partial page (count below fetchLimit) is still a full replace — '
        'an absent synced row is a real deletion', () async {
      await store.replaceFromServer([
        _serverWorkout('old', startedAt: DateTime.utc(2026, 1, 1)),
        _serverWorkout('new', startedAt: DateTime.utc(2026, 6, 1)),
      ]);
      // The page (1 row) is BELOW the limit of 100, so it's the complete set:
      // the missing 'old' was genuinely deleted server-side and must be pruned.
      await store.replaceFromServer(
        [_serverWorkout('new', startedAt: DateTime.utc(2026, 6, 1))],
        fetchLimit: 100,
      );
      expect(store.byId('old'), isNull,
          reason: 'a sub-limit page is the full set; deletion propagates');
      expect(store.byId('new'), isNotNull);
    });
  });

  group('_rewriteAll crash-atomic ordering', () {
    List<String> jsonFiles() => dir
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.json'))
        .where((n) => n != 'index.json')
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

    test('a no-change refresh performs zero atomic rewrites (diff-before-write)',
        () async {
      await store.replaceFromServer([
        _serverWorkout('w1', title: 'One'),
        _serverWorkout('w2', title: 'Two'),
      ]);
      final afterFirst = store.rewriteAtomicWrites;
      expect(afterFirst, greaterThan(0),
          reason: 'the initial ingest writes the rows');

      // Identical server payload — every row is byte-identical on disk, so the
      // refresh must skip every per-row fsync (the write-amplification fix).
      await store.replaceFromServer([
        _serverWorkout('w1', title: 'One'),
        _serverWorkout('w2', title: 'Two'),
      ]);
      expect(store.rewriteAtomicWrites, afterFirst,
          reason: 'an unchanged refresh must not re-write any row');

      // A single changed row rewrites only itself.
      await store.replaceFromServer([
        _serverWorkout('w1', title: 'One CHANGED'),
        _serverWorkout('w2', title: 'Two'),
      ]);
      expect(store.rewriteAtomicWrites, afterFirst + 1,
          reason: 'only the changed row is re-written');
      expect(store.byId('w1')!.row['title'], 'One CHANGED');

      // The skip kept the unchanged files intact — a fresh store reads both.
      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts.map((w) => w.id).toSet(), {'w1', 'w2'});
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

  group('summary index (index.json)', () {
    Map<String, dynamic> readIndexFile() => jsonDecode(
            File('${dir.path}/index.json').readAsStringSync())
        as Map<String, dynamic>;
    List<Map<String, dynamic>> indexSummaries() =>
        (readIndexFile()['summaries'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    test('a create writes a summary carrying the windowed fields', () async {
      final stored = await store.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 2, 8),
        sets: [_set('Bench', reps: 8, kg: 60), _set('Bench', reps: 8, kg: 60)],
      );
      final summaries = indexSummaries();
      expect(summaries, hasLength(1));
      final s = summaries.single;
      expect(s['id'], stored.id);
      expect(s['sync_state'], 'pending_create');
      expect(s['title'], 'Push day');
      expect(s['set_count'], 2);
      expect(s['started_at'], isNotNull);
      expect(readIndexFile()[kLocalStoreVersionKey], kLocalStoreSchemaVersion);
    });

    test('an update refreshes the summary in place', () async {
      final stored = await store.createLocal(
        title: 'Draft',
        startedAt: DateTime.utc(2026, 6, 2),
        sets: [_set('Bench', reps: 8, kg: 60)],
      );
      await store.updateLocal(stored.id,
          title: 'Renamed', sets: [_set('Bench', reps: 8, kg: 60), _set('Row')]);
      final s = indexSummaries().single;
      expect(s['title'], 'Renamed');
      expect(s['set_count'], 2);
    });

    test('a pendingCreate delete drops the summary', () async {
      final stored =
          await store.createLocal(startedAt: DateTime.utc(2026, 6, 2));
      await store.deleteLocal(stored.id);
      expect(indexSummaries(), isEmpty);
    });

    test('a synced delete (tombstone) removes the row from the index', () async {
      await store.replaceFromServer([_serverWorkout('kill-me')]);
      expect(indexSummaries().map((s) => s['id']), contains('kill-me'));
      await store.deleteLocal('kill-me');
      expect(indexSummaries().map((s) => s['id']), isNot(contains('kill-me')),
          reason: 'a tombstone is not a live row and must leave the index');
    });

    test('rewriteAll (via replaceFromServer) rebuilds the index to live rows',
        () async {
      await store.replaceFromServer([
        _serverWorkout('w1', title: 'One'),
        _serverWorkout('w2', title: 'Two'),
      ]);
      await store.createLocal(
          title: 'Offline', startedAt: DateTime.utc(2026, 6, 4));
      await store.replaceFromServer([_serverWorkout('w1', title: 'One')]);
      final ids = indexSummaries().map((s) => s['id']).toSet();
      expect(ids.contains('w1'), isTrue);
      expect(ids.contains('w2'), isFalse,
          reason: 'a server-dropped row leaves the index');
      expect(ids, hasLength(2), reason: 'w1 + the surviving pendingCreate');
    });

    test('restoreFromBackup writes the index once for the batch', () async {
      final imported = await store.restoreFromBackup([
        StoredGymWorkout(
          row: {
            'id': 'r1',
            'title': 'Restored A',
            'started_at': DateTime.utc(2026, 6, 1).toIso8601String(),
          },
          sets: const [],
          syncState: GymSyncState.synced,
        ).toJson(),
        StoredGymWorkout(
          row: {
            'id': 'r2',
            'title': 'Restored B',
            'started_at': DateTime.utc(2026, 6, 2).toIso8601String(),
          },
          sets: const [],
          syncState: GymSyncState.synced,
        ).toJson(),
      ]);
      expect(imported, 2);
      expect(indexSummaries().map((s) => s['id']).toSet(), {'r1', 'r2'});
    });

    test('cold-load self-heals when index.json is deleted', () async {
      await store.createLocal(
          title: 'Kept', startedAt: DateTime.utc(2026, 6, 2));
      File('${dir.path}/index.json').deleteSync();

      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts, hasLength(1));
      expect(File('${dir.path}/index.json').existsSync(), isTrue,
          reason: 'a missing index is rebuilt + persisted on cold-load');
    });

    test('cold-load self-heals when an orphan row file is not in the index',
        () async {
      await store.createLocal(
          title: 'Kept', startedAt: DateTime.utc(2026, 6, 2));
      // A row file the on-disk index doesn't know about (a crash between the
      // row write and the index flush) — drift must trigger a full-walk
      // rebuild so the orphan is picked up.
      final orphan = StoredGymWorkout(
        row: {
          'id': 'orphan',
          'title': 'Orphan',
          'started_at': DateTime.utc(2026, 6, 3).toIso8601String(),
        },
        sets: const [],
        syncState: GymSyncState.synced,
      );
      File('${dir.path}/orphan.json').writeAsStringSync(jsonEncode(orphan.toJson()));

      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts.map((w) => w.id), contains('orphan'),
          reason: 'drift forced a rebuild that picked up the orphan');
      expect(reloaded.workouts, hasLength(2),
          reason: 'the kept create + the orphan');
      expect((jsonDecode(File('${dir.path}/index.json').readAsStringSync())
              as Map<String, dynamic>)['summaries'],
          hasLength(2));
    });

    test('debugReadIndex tolerates a structurally-invalid index', () async {
      await store.createLocal(startedAt: DateTime.utc(2026, 6, 2));
      // summaries is not a List → structurally invalid → null, never a throw.
      File('${dir.path}/index.json')
          .writeAsStringSync(jsonEncode({'_v': 1, 'summaries': 'nope'}));
      expect(await store.debugReadIndex(), isNull);
      // A malformed element (no String id) is also a miss.
      File('${dir.path}/index.json').writeAsStringSync(jsonEncode({
        '_v': 1,
        'summaries': [
          {'no_id': true}
        ],
      }));
      expect(await store.debugReadIndex(), isNull);
      // Outright garbage.
      File('${dir.path}/index.json').writeAsStringSync('{ not json');
      expect(await store.debugReadIndex(), isNull);
    });

    test('a structurally-invalid index forces a clean cold-load rebuild',
        () async {
      await store.createLocal(
          title: 'Kept', startedAt: DateTime.utc(2026, 6, 2));
      File('${dir.path}/index.json')
          .writeAsStringSync(jsonEncode({'_v': 1, 'summaries': 'nope'}));

      final reloaded = LocalGymStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.workouts, hasLength(1));
      expect(await reloaded.debugReadIndex(), isNotNull,
          reason: 'cold-load rebuilt a valid index over the corrupt one');
    });
  });

  group('windowed queries', () {
    test('loadInWindow returns rows in the half-open [from, to) day window',
        () async {
      await store.createLocal(
          title: 'Day 1', startedAt: DateTime.utc(2026, 6, 1, 9));
      await store.createLocal(
          title: 'Day 2 AM', startedAt: DateTime.utc(2026, 6, 2, 6));
      await store.createLocal(
          title: 'Day 2 PM', startedAt: DateTime.utc(2026, 6, 2, 20));
      await store.createLocal(
          title: 'Day 3', startedAt: DateTime.utc(2026, 6, 3, 0));

      final inDay2 = await store.loadInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(inDay2.map((w) => w.row['title']).toSet(), {'Day 2 AM', 'Day 2 PM'},
          reason: 'the day-3 00:00 row is excluded by the half-open upper bound');
    });

    test('estimateRowsInWindow counts from the index without hydrating',
        () async {
      await store.createLocal(startedAt: DateTime.utc(2026, 6, 2, 6));
      await store.createLocal(startedAt: DateTime.utc(2026, 6, 2, 20));
      await store.createLocal(startedAt: DateTime.utc(2026, 6, 4));
      final n = await store.estimateRowsInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(n, 2);
    });

    test('loadInWindow hydrates the full row (with its sets)', () async {
      await store.createLocal(
        title: 'Leg day',
        startedAt: DateTime.utc(2026, 6, 2, 8),
        sets: [_set('Squat', reps: 5, kg: 100)],
      );
      final fresh = LocalGymStore();
      await fresh.init(overrideDirectory: dir);
      final inWindow = await fresh.loadInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(inWindow.single.sets.single['exercise_name'], 'Squat');
    });
  });

  group('markSynced flow still works with the index', () {
    test('a drained pendingCreate flips to synced in the index', () async {
      final api = _FakeGymApi();
      final stored = await store.createLocal(
          title: 'Push', startedAt: DateTime.utc(2026, 6, 2));
      await store.syncWithServer(api);
      expect(store.byId(stored.id)!.syncState, GymSyncState.synced);
      final summaries = (jsonDecode(
                  File('${dir.path}/index.json').readAsStringSync())
              as Map<String, dynamic>)['summaries'] as List;
      expect(summaries.single['sync_state'], 'synced',
          reason: 'markSynced persists via asSynced → persist → index flush');
    });
  });
}
