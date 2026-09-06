import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_food_store.dart';
import '../lib/offline_sync_store.dart' show kUnknownStoredClock;

/// Fake [ApiClient] that records food-log CRUD calls and lets a test
/// inject per-method failure modes. Tracks the order of operations so we
/// can assert the drain order (create → update → delete).
class _FakeFoodApi extends ApiClient {
  final List<String> calls = [];
  Set<String> failedCreates = const {};
  Set<String> failedUpdates = const {};
  Set<String> failedDeletes = const {};

  @override
  Future<FoodLogRow> logFood({
    String? id,
    required DateTime startedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
  }) async {
    calls.add('create:$id');
    if (failedCreates.contains(id)) throw StateError('create failed');
    return FoodLogRow(
      id: id ?? 'server-generated',
      userId: 'test-user',
      startedAt: startedAt,
      itemName: itemName,
      mealSlot: mealSlot,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      isPublic: isPublic,
      externalId: externalId,
      lastModifiedAt: lastModifiedAt ?? DateTime.now().toUtc(),
      createdAt: DateTime.now().toUtc(),
    );
  }

  @override
  Future<void> updateFoodLog(
    String id, {
    String? itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    double? fiberG,
    double? sugarG,
    double? sodiumMg,
    double? saturatedFatG,
    double? cholesterolMg,
    bool? isPublic,
    DateTime? lastModifiedAt,
  }) async {
    calls.add('update:$id');
    if (failedUpdates.contains(id)) throw StateError('update failed');
  }

  @override
  Future<void> deleteFoodLog(String id) async {
    calls.add('delete:$id');
    if (failedDeletes.contains(id)) throw StateError('delete failed');
  }
}

Map<String, dynamic> _serverRow(
  String id, {
  String? itemName,
  DateTime? startedAt,
  DateTime? lastModifiedAt,
}) =>
    {
      'id': id,
      'started_at': (startedAt ?? DateTime.utc(2026, 6, 1, 12)).toIso8601String(),
      'item_name': itemName ?? 'Server item',
      'meal_slot': null,
      'calories': null,
      'protein_g': null,
      'carbs_g': null,
      'fat_g': null,
      'is_public': false,
      'external_id': null,
      'last_modified_at':
          (lastModifiedAt ?? DateTime.utc(2026, 6, 1)).toIso8601String(),
      'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
    };

/// Tests for [LocalFoodStore] — the disk-backed offline food-log cache.
/// Mirrors the [LocalGearStore] coverage pattern: lifecycle (create /
/// update / delete) + drain semantics + reload after restart, plus the
/// nutrition-specific day-range query.
void main() {
  late Directory dir;
  late LocalFoodStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_food_store_test_');
    store = LocalFoodStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('rows cache (revision-keyed)', () {
    test('repeated reads with no mutation return the identical cached list',
        () async {
      await store.createLocal(
        startedAt: DateTime.utc(2026, 6, 1),
        itemName: 'Oats',
      );
      final first = store.rows;
      final second = store.rows;
      expect(identical(first, second), isTrue,
          reason: 'A read with no intervening mutation must hit the cache, '
              'not re-sort the whole food history.');
    });

    test('a mutation invalidates the cache and the new entry sorts in',
        () async {
      await store.createLocal(
        startedAt: DateTime.utc(2026, 6, 1),
        itemName: 'older',
      );
      final before = store.rows;
      expect(before, hasLength(1));
      await store.createLocal(
        startedAt: DateTime.utc(2026, 6, 5),
        itemName: 'newer',
      );
      final after = store.rows;
      expect(identical(before, after), isFalse,
          reason: 'A mutation must bump storeRevision so rows recomputes.');
      expect(after, hasLength(2));
      expect(after.first['item_name'], 'newer',
          reason: 'Newest-logged stays first after the cache refresh.');
    });
  });

  group('createLocal', () {
    test('mints a v4 UUID and marks the entry pendingCreate', () async {
      final stored = await store.createLocal(
        startedAt: DateTime.utc(2026, 6, 2, 8),
        itemName: 'Oats',
        mealSlot: 'breakfast',
        calories: 412,
        proteinG: 12,
      );
      expect(
          stored.id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(stored.syncState, FoodSyncState.pendingCreate);
      expect(store.rows, hasLength(1));
      expect(store.rows.first['item_name'], 'Oats');
      expect(store.hasPending, isTrue);
    });

    test('survives a store reload', () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Chicken bowl', calories: 640);
      final fresh = LocalFoodStore();
      await fresh.init(overrideDirectory: dir);
      expect(fresh.rows, hasLength(1));
      expect(fresh.rows.first['item_name'], 'Chicken bowl');
      expect(fresh.rows.first['calories'], 640);
    });

    test('rows are sorted newest-logged first', () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 8), itemName: 'Breakfast');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 13), itemName: 'Lunch');
      expect(store.rows.first['item_name'], 'Lunch');
      expect(store.rows.last['item_name'], 'Breakfast');
    });
  });

  group('entriesForRange', () {
    test('returns only entries within the half-open day window', () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 1, 23), itemName: 'Yesterday');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 8), itemName: 'Today');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 3, 0), itemName: 'Tomorrow');
      final today = store.entriesForRange(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(today.map((r) => r['item_name']), ['Today']);
    });
  });

  group('schema version (_v)', () {
    test('a persisted record carries the current schema version', () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Apple');
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
          'logged_at': DateTime.utc(2026, 6, 1, 12).toIso8601String(),
          'item_name': 'Old',
          'meal_slot': null,
          'calories': null,
          'protein_g': null,
          'carbs_g': null,
          'fat_g': null,
          'is_public': false,
          'external_id': null,
          'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
          'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
        },
        'sync_state': 'synced',
        'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
      };
      File('${dir.path}/legacy.json').writeAsStringSync(jsonEncode(legacy));

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.any((r) => r['id'] == 'legacy'), isTrue);
    });
  });

  group('updateLocal', () {
    test('pendingCreate stays pendingCreate', () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Old');
      await store.updateLocal(stored.id, itemName: 'New', calories: 500);
      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.first['item_name'], 'New');
      expect(reloaded.rows.first['calories'], 500);
    });

    test('flips synced→pendingUpdate', () async {
      await store.replaceFromServer([_serverRow('abc-123', itemName: 'Old')]);
      expect(store.hasPending, isFalse);
      await store.updateLocal('abc-123', itemName: 'Edited');
      expect(store.hasPending, isTrue);
      expect(store.rows.first['item_name'], 'Edited');
    });
  });

  group('deleteLocal', () {
    test('pendingCreate entries disappear without a tombstone', () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
      await store.deleteLocal(stored.id);
      expect(store.rows, isEmpty);
      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows, isEmpty);
      expect(reloaded.hasPending, isFalse);
    });

    test('synced entries become pendingDelete tombstones', () async {
      await store.replaceFromServer([_serverRow('abc-123')]);
      await store.deleteLocal('abc-123');
      expect(store.rows, isEmpty,
          reason: 'tombstones don\'t appear in the live list');
      expect(store.hasPending, isTrue);
    });
  });

  group('replaceFromServer', () {
    test('overwrites synced rows but preserves pendingCreate', () async {
      final mine = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Mine');
      await store.replaceFromServer([_serverRow('server-1', itemName: 'Server')]);
      expect(store.rows.any((r) => r['id'] == mine.id), isTrue,
          reason: 'pendingCreate entry must survive a server refresh');
      expect(store.rows.any((r) => r['id'] == 'server-1'), isTrue);
    });

    test('preserves pendingUpdate edits across refresh', () async {
      await store.replaceFromServer([_serverRow('abc-123', itemName: 'Server')]);
      await store.updateLocal('abc-123', itemName: 'My edit');
      await store.replaceFromServer([_serverRow('abc-123', itemName: 'Server')]);
      expect(store.rows.first['item_name'], 'My edit',
          reason: 'pendingUpdate edits override the server copy until drained');
    });

    test('newer-wins: a stale server fetch does not clobber a locally-newer '
        'synced copy', () async {
      await store.replaceFromServer([
        _serverRow('f1',
            itemName: 'Recent', lastModifiedAt: DateTime.utc(2026, 6, 2)),
      ]);
      await store.replaceFromServer([
        _serverRow('f1',
            itemName: 'Stale', lastModifiedAt: DateTime.utc(2026, 6, 1)),
      ]);
      expect(store.rows.first['item_name'], 'Recent');
    });

    test('newer-wins: a newer server fetch overwrites the synced copy',
        () async {
      await store.replaceFromServer([
        _serverRow('f1',
            itemName: 'Old', lastModifiedAt: DateTime.utc(2026, 6, 1)),
      ]);
      await store.replaceFromServer([
        _serverRow('f1',
            itemName: 'New', lastModifiedAt: DateTime.utc(2026, 6, 2)),
      ]);
      expect(store.rows.first['item_name'], 'New');
    });

    test(
        'a windowed fetch preserves synced rows older than the window — does '
        'not wipe history before windowStart', () async {
      // Seed a synced entry from 30 days ago and one inside the last week.
      await store.replaceFromServer([
        _serverRow('old', itemName: 'Old', startedAt: DateTime.utc(2026, 5, 1)),
        _serverRow('recent', itemName: 'Recent', startedAt: DateTime.utc(2026, 6, 1)),
      ]);
      expect(store.rows.any((r) => r['id'] == 'old'), isTrue);

      // The next 7-day windowed hydrate returns only the in-window entry. The
      // older one is outside [windowStart, windowEnd) and must be preserved,
      // not deleted as if absent==removed.
      await store.replaceFromServer(
        [_serverRow('recent', itemName: 'Recent', startedAt: DateTime.utc(2026, 6, 1))],
        windowStart: DateTime.utc(2026, 5, 26),
        windowEnd: DateTime.utc(2026, 6, 3),
      );
      expect(store.rows.any((r) => r['id'] == 'old'), isTrue,
          reason: 'a synced entry older than the window must survive');
      expect(store.rows.any((r) => r['id'] == 'recent'), isTrue);

      // On-disk state agrees — a fresh store reads both back.
      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.any((r) => r['id'] == 'old'), isTrue);
    });

    test(
        'a row absent WITHIN the window is still pruned (deletion propagates '
        'inside the window)', () async {
      await store.replaceFromServer([
        _serverRow('keep', startedAt: DateTime.utc(2026, 6, 1)),
        _serverRow('gone', startedAt: DateTime.utc(2026, 6, 2)),
      ]);
      // Both are inside the next window; 'gone' is now absent → real deletion.
      await store.replaceFromServer(
        [_serverRow('keep', startedAt: DateTime.utc(2026, 6, 1))],
        windowStart: DateTime.utc(2026, 5, 26),
        windowEnd: DateTime.utc(2026, 6, 3),
      );
      expect(store.rows.any((r) => r['id'] == 'gone'), isFalse,
          reason: 'an in-window absence is a deletion and must propagate');
      expect(store.rows.any((r) => r['id'] == 'keep'), isTrue);
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
        _serverRow('f1', itemName: 'One'),
        _serverRow('f2', itemName: 'Two'),
      ]);
      final mine = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 4), itemName: 'Offline');
      expect(jsonFiles(), hasLength(3));

      await store.replaceFromServer([_serverRow('f1', itemName: 'One')]);

      expect(store.rows.any((r) => r['id'] == 'f1'), isTrue);
      expect(store.rows.any((r) => r['id'] == 'f2'), isFalse);
      expect(store.rows.any((r) => r['id'] == mine.id), isTrue,
          reason: 'pendingCreate survives the rewrite');
      expect(tmpFiles(), isEmpty, reason: 'atomic writes leave no .tmp behind');

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.map((r) => r['id'] as String).toSet(),
          {'f1', mine.id});
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
        _serverRow('ok-1', itemName: 'One'),
        _serverRow('ok-2', itemName: 'Two'),
        _serverRow('bad', itemName: 'Bad'),
      ]);

      expect(jsonFiles(), containsAll(['ok-1.json', 'ok-2.json']),
          reason: 'the good rows write despite the bad one failing');
      expect(jsonFiles(), isNot(contains('orphan.json')),
          reason: 'orphan cleanup still runs after a write failure');
      expect(Directory('${dir.path}/bad.json').existsSync(), isTrue,
          reason: "the bad row's prior on-disk state is kept, not deleted");
      expect(tmpFiles(), isEmpty,
          reason: 'a failed atomic write cleans up its own .tmp sibling');
      expect(store.rows.any((r) => r['id'] == 'ok-1'), isTrue);
      expect(store.rows.any((r) => r['id'] == 'ok-2'), isTrue);
    });
  });

  group('syncWithServer drain', () {
    test('drains pendingCreate via logFood with the local id', () async {
      final api = _FakeFoodApi();
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Oats');

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'create:${stored.id}',
          reason:
              'pendingCreate must use the local-minted id so server + cache stay in lockstep.');
      expect(store.hasPending, isFalse);
    });

    test('drains pendingUpdate via updateFoodLog', () async {
      await store.replaceFromServer([_serverRow('srv-1', itemName: 'Old')]);
      await store.updateLocal('srv-1', itemName: 'New');
      final api = _FakeFoodApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'update:srv-1');
      expect(store.hasPending, isFalse);
    });

    test('drains pendingDelete via deleteFoodLog + drops the local row',
        () async {
      await store.replaceFromServer([_serverRow('kill-me')]);
      await store.deleteLocal('kill-me');
      final api = _FakeFoodApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'delete:kill-me');
      expect(store.rows, isEmpty);
      expect(store.hasPending, isFalse);
    });

    test('mixed queue: every state hits the server', () async {
      await store.replaceFromServer([
        _serverRow('sync-edit', itemName: 'Old'),
        _serverRow('sync-kill'),
      ]);
      final created = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Fresh');
      await store.updateLocal('sync-edit', itemName: 'Edited');
      await store.deleteLocal('sync-kill');

      final api = _FakeFoodApi();
      final drained = await store.syncWithServer(api);

      expect(drained, 3);
      expect(
          api.calls,
          containsAll(
              ['create:${created.id}', 'update:sync-edit', 'delete:sync-kill']));
      expect(store.rows.map((r) => r['id']).toSet(), {'sync-edit', created.id});
    });

    test('per-row failure isolation: failing create leaves the row pending',
        () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
      final api = _FakeFoodApi()..failedCreates = {stored.id};

      final drained = await store.syncWithServer(api);

      expect(drained, 0);
      expect(store.hasPending, isTrue);
    });

    test('clean store: syncWithServer is a no-op (drained=0)', () async {
      final api = _FakeFoodApi();
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
        startedAt: DateTime.utc(2026, 6, 2, 8),
        itemName: 'Oatmeal',
        calories: 350,
      );
      final s = indexSummaries().single;
      expect(s['id'], stored.id);
      expect(s['sync_state'], 'pending_create');
      expect(s['item_name'], 'Oatmeal');
      expect(s['calories'], 350);
      expect(s['started_at'], isNotNull);
      expect(readIndexFile()[kLocalStoreVersionKey], kLocalStoreSchemaVersion);
    });

    test('an update refreshes the summary in place', () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Snack', calories: 100);
      await store.updateLocal(stored.id, itemName: 'Big snack', calories: 250);
      final s = indexSummaries().single;
      expect(s['item_name'], 'Big snack');
      expect(s['calories'], 250);
    });

    test('a pendingCreate delete drops the summary', () async {
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
      await store.deleteLocal(stored.id);
      expect(indexSummaries(), isEmpty);
    });

    test('a synced delete (tombstone) removes the row from the index', () async {
      await store.replaceFromServer([_serverRow('kill-me')]);
      expect(indexSummaries().map((s) => s['id']), contains('kill-me'));
      await store.deleteLocal('kill-me');
      expect(indexSummaries().map((s) => s['id']), isNot(contains('kill-me')));
    });

    test('rewriteAll (via replaceFromServer) rebuilds the index to live rows',
        () async {
      await store.replaceFromServer([_serverRow('f1'), _serverRow('f2')]);
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 4), itemName: 'Offline');
      await store.replaceFromServer([_serverRow('f1')]);
      final ids = indexSummaries().map((s) => s['id']).toSet();
      expect(ids.contains('f1'), isTrue);
      expect(ids.contains('f2'), isFalse);
      expect(ids, hasLength(2));
    });

    test('restoreFromBackup writes the index once for the batch', () async {
      final imported = await store.restoreFromBackup([
        StoredFood(
          row: {
            'id': 'r1',
            'item_name': 'A',
            'started_at': DateTime.utc(2026, 6, 1).toIso8601String(),
          },
          syncState: FoodSyncState.synced,
        ).toJson(),
        StoredFood(
          row: {
            'id': 'r2',
            'item_name': 'B',
            'started_at': DateTime.utc(2026, 6, 2).toIso8601String(),
          },
          syncState: FoodSyncState.synced,
        ).toJson(),
      ]);
      expect(imported, 2);
      expect(indexSummaries().map((s) => s['id']).toSet(), {'r1', 'r2'});
    });

    test('restoreFromBackup keeps a record whose clock is the wrong type',
        () async {
      // decisions § 1290. The `as String?` cast this replaced threw on a
      // non-string clock, and `_restoreFromBackup` catches per record — so an
      // archive entry whose `last_modified_at` was a number was skipped whole,
      // taking a food entry that exists nowhere else with it, while the same
      // entry with NO clock field at all restored fine.
      final record = StoredFood(
        row: {
          'id': 'mistyped-clock',
          'item_name': 'Porridge',
          'started_at': DateTime.utc(2026, 6, 1).toIso8601String(),
        },
        syncState: FoodSyncState.synced,
      ).toJson();
      record['last_modified_at'] = 1757116800000;

      expect(await store.restoreFromBackup([record]), 1);
      expect(store.rowsById.containsKey('mistyped-clock'), isTrue);
      final stored = store.rowsById['mistyped-clock']!;
      expect(stored.row['item_name'], 'Porridge');
      expect(stored.syncState, FoodSyncState.pendingCreate);
      // § 1342: an unreadable clock is the epoch, not `now`. The record is
      // restored pendingCreate, so it is preserved across every
      // `replaceFromServer` and pushed regardless of what its clock says —
      // the epoch costs it nothing, where `now` would have let it win
      // newer-wins against the server for good once it went `synced`.
      expect(stored.lastModifiedAt, kUnknownStoredClock);
    });

    test('cold-load self-heals when index.json is deleted', () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Kept');
      File('${dir.path}/index.json').deleteSync();

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows, hasLength(1));
      expect(File('${dir.path}/index.json').existsSync(), isTrue);
    });

    test('cold-load self-heals when an orphan row file is not in the index',
        () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Kept');
      final orphan = StoredFood(
        row: {
          'id': 'orphan',
          'item_name': 'Orphan',
          'started_at': DateTime.utc(2026, 6, 3).toIso8601String(),
        },
        syncState: FoodSyncState.synced,
      );
      File('${dir.path}/orphan.json')
          .writeAsStringSync(jsonEncode(orphan.toJson()));

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.map((r) => r['id']), contains('orphan'),
          reason: 'drift forced a rebuild that picked up the orphan');
      expect(reloaded.rows, hasLength(2),
          reason: 'the kept create + the orphan');
      expect((jsonDecode(File('${dir.path}/index.json').readAsStringSync())
              as Map<String, dynamic>)['summaries'],
          hasLength(2));
    });

    test('debugReadIndex tolerates a structurally-invalid index', () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
      File('${dir.path}/index.json')
          .writeAsStringSync(jsonEncode({'_v': 1, 'summaries': 'nope'}));
      expect(await store.debugReadIndex(), isNull);
      File('${dir.path}/index.json').writeAsStringSync(jsonEncode({
        '_v': 1,
        'summaries': [
          {'no_id': true}
        ],
      }));
      expect(await store.debugReadIndex(), isNull);
      File('${dir.path}/index.json').writeAsStringSync('{ not json');
      expect(await store.debugReadIndex(), isNull);
    });

    test('a structurally-invalid index forces a clean cold-load rebuild',
        () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'Kept');
      File('${dir.path}/index.json')
          .writeAsStringSync(jsonEncode({'_v': 1, 'summaries': 'nope'}));

      final reloaded = LocalFoodStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows, hasLength(1));
      expect(await reloaded.debugReadIndex(), isNotNull);
    });
  });

  group('windowed queries', () {
    test('loadInWindow returns rows in the half-open [from, to) day window',
        () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 1, 9), itemName: 'Day 1');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 6), itemName: 'Day 2 AM');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 20), itemName: 'Day 2 PM');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 3, 0), itemName: 'Day 3');

      final inDay2 = await store.loadInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(inDay2.map((f) => f.row['item_name']).toSet(),
          {'Day 2 AM', 'Day 2 PM'},
          reason: 'the day-3 00:00 row is excluded by the half-open upper bound');
    });

    test('estimateRowsInWindow counts from the index without hydrating',
        () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 6), itemName: 'A');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 20), itemName: 'B');
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 4), itemName: 'C');
      final n = await store.estimateRowsInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(n, 2);
    });

    test('loadInWindow hydrates the full row from disk after a cold reload',
        () async {
      await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2, 8),
          itemName: 'Oatmeal',
          calories: 350);
      final fresh = LocalFoodStore();
      await fresh.init(overrideDirectory: dir);
      final inWindow = await fresh.loadInWindow(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(inWindow.single.row['item_name'], 'Oatmeal');
      expect(inWindow.single.row['calories'], 350);
    });
  });

  group('markSynced flow still works with the index', () {
    test('a drained pendingCreate flips to synced in the index', () async {
      final api = _FakeFoodApi();
      final stored = await store.createLocal(
          startedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
      await store.syncWithServer(api);
      expect(store.rows.any((r) => r['id'] == stored.id), isTrue);
      final summaries = (jsonDecode(
                  File('${dir.path}/index.json').readAsStringSync())
              as Map<String, dynamic>)['summaries'] as List;
      expect(summaries.single['sync_state'], 'synced');
    });
  });
}
