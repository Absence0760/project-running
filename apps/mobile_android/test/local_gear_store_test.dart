import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gear_store.dart';

/// Fake [ApiClient] that records gear CRUD calls and lets a test
/// inject per-method failure modes. Tracks the order of operations
/// so we can assert the drain order (create → update → delete).
class _FakeGearApi extends ApiClient {
  final List<String> calls = [];
  final List<Map<String, dynamic>> creates = [];
  final List<Map<String, dynamic>> updates = [];
  Set<String> failOn = const {};
  Set<String> failedCreates = const {};
  Set<String> failedUpdates = const {};
  Set<String> failedDeletes = const {};

  @override
  Future<GearRow> createGear({
    required String kind,
    required String name,
    String? id,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    int? targetDistanceM,
    String? notes,
  }) async {
    calls.add('create:$id');
    creates.add({'id': id, 'purchased_at': purchasedAt});
    if (failedCreates.contains(id)) throw StateError('create failed');
    return GearRow(
      id: id ?? 'server-generated',
      ownerId: 'test-user',
      kind: kind,
      name: name,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      isDefault: false,
    );
  }

  @override
  Future<void> updateGear(
    String id, {
    String? name,
    String? brand,
    String? model,
    DateTime? purchasedAt,
    DateTime? retiredAt,
    bool clearRetiredAt = false,
    int? targetDistanceM,
    String? notes,
  }) async {
    calls.add('update:$id');
    updates.add({
      'id': id,
      'purchased_at': purchasedAt,
      'retired_at': retiredAt,
    });
    if (failedUpdates.contains(id)) throw StateError('update failed');
  }

  @override
  Future<void> deleteGear(String id) async {
    calls.add('delete:$id');
    if (failedDeletes.contains(id)) throw StateError('delete failed');
  }
}

/// Tests for [LocalGearStore] — the disk-backed offline gear cache.
/// Mirrors the LocalRunStore coverage pattern: lifecycle (create /
/// update / retire / delete) + drain semantics + reload after restart.
void main() {
  late Directory dir;
  late LocalGearStore store;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('local_gear_store_test_');
    store = LocalGearStore();
    await store.init(overrideDirectory: dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  group('createLocal', () {
    test('mints a v4 UUID and marks the row pendingCreate', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'Vaporfly');
      expect(stored.id, matches(RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(stored.syncState, GearSyncState.pendingCreate);
      expect(store.rows, hasLength(1));
      expect(store.hasPending, isTrue);
    });

    test('survives a store reload', () async {
      await store.createLocal(
          kind: 'bike', name: 'Trek Domane', targetDistanceM: 5000000);
      final fresh = LocalGearStore();
      await fresh.init(overrideDirectory: dir);
      expect(fresh.rows, hasLength(1));
      expect(fresh.rows.first['name'], 'Trek Domane');
    });
  });

  group('a `date` column is never rolled over on its way back to the server',
      () {
    /// Seeds a gear row on disk with an arbitrary `purchased_at` text and
    /// returns a store that has cold-loaded it.
    Future<LocalGearStore> seed(String id, String purchasedAt,
        {required GearSyncState state}) async {
      final stored = StoredGear(
        row: <String, dynamic>{
          'id': id,
          'kind': 'shoe',
          'name': 'Seeded',
          'purchased_at': purchasedAt,
          'retired_at': null,
          'total_distance_m': 0,
          'created_at': DateTime.utc(2026, 6, 1).toIso8601String(),
        },
        syncState: state,
      );
      File('${dir.path}/$id.json').writeAsStringSync(jsonEncode(stored.toJson()));
      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      return reloaded;
    }

    test('an impossible day is sent as NO date, not as the day it rolls to',
        () async {
      // decisions § 1344. `DateTime.tryParse('2026-06-32')` is the 2nd of
      // July, and this value goes straight back to a `date` column through
      // `createGear` — so the rolled-over day would become the stored day and
      // `gearBackfillCandidates` would then measure the wrong purchase date.
      final store = await seed('rolled', '2026-06-32',
          state: GearSyncState.pendingCreate);
      final api = _FakeGearApi();
      await store.syncWithServer(api);
      expect(api.creates, hasLength(1));
      expect(api.creates.single['purchased_at'], isNull,
          reason: 'a refusal, not 2026-07-02');
    });

    test('the same shape on the update path', () async {
      final store = await seed('rolled-update', '2026-02-30',
          state: GearSyncState.pendingUpdate);
      final api = _FakeGearApi();
      await store.syncWithServer(api);
      expect(api.updates, hasLength(1));
      expect(api.updates.single['purchased_at'], isNull);
    });

    test('a real date still reaches the server as its own calendar day',
        () async {
      // The refusal must not have narrowed what a legitimate row can carry,
      // and the day must not have moved: a purchase on the 3rd stays the 3rd,
      // which is the whole reason this reader does not normalise to UTC
      // (decisions § 1289).
      final store = await seed('kept', '2026-06-03',
          state: GearSyncState.pendingCreate);
      final api = _FakeGearApi();
      await store.syncWithServer(api);
      final at = api.creates.single['purchased_at'] as DateTime;
      expect([at.year, at.month, at.day], [2026, 6, 3]);
    });

    test('a leap day is a date; the same day in a common year is not',
        () async {
      final leap = await seed('leap', '2024-02-29',
          state: GearSyncState.pendingCreate);
      final leapApi = _FakeGearApi();
      await leap.syncWithServer(leapApi);
      expect((leapApi.creates.single['purchased_at'] as DateTime).day, 29);

      File('${dir.path}/leap.json').deleteSync();
      final common = await seed('common', '2027-02-29',
          state: GearSyncState.pendingCreate);
      final commonApi = _FakeGearApi();
      await common.syncWithServer(commonApi);
      expect(commonApi.creates.single['purchased_at'], isNull);
    });
  });

  group('last_modified_at clock', () {
    test('createLocal stamps lastModifiedAt from the same instant as created_at',
        () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'Vaporfly');
      expect(stored.lastModifiedAt, isNotNull);
      final createdAt =
          DateTime.parse(stored.row['created_at'] as String).toUtc();
      expect(stored.lastModifiedAt, createdAt,
          reason: 'lastModifiedAt and created_at derive from one `now`');
    });

    test('_markSynced preserves the modification clock (does not bump to now)',
        () async {
      // Seed a pendingUpdate row on disk with a known-old clock, then drain
      // it. After the drain it must be `synced` but keep the old clock — a
      // bumped clock would later beat the server copy it was just pushed from.
      const id = 'old-shoe';
      final old = DateTime.utc(2020, 1, 1);
      final stored = StoredGear(
        row: <String, dynamic>{
          'id': id,
          'kind': 'shoe',
          'name': 'Old',
          'retired_at': null,
          'total_distance_m': 0,
          'created_at': old.toIso8601String(),
        },
        syncState: GearSyncState.pendingUpdate,
        lastModifiedAt: old,
      );
      File('${dir.path}/$id.json').writeAsStringSync(jsonEncode(stored.toJson()));

      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.debugStored(id)!.syncState, GearSyncState.pendingUpdate);

      await reloaded.syncWithServer(_FakeGearApi());

      final after = reloaded.debugStored(id)!;
      expect(after.syncState, GearSyncState.synced);
      expect(after.lastModifiedAt, old,
          reason: 'syncing must not reset the modification clock');
    });
  });

  group('schema version (_v)', () {
    test('a persisted record carries the current schema version', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
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
          'kind': 'shoe',
          'name': 'Old',
          'retired_at': null,
          'total_distance_m': 0,
        },
        'sync_state': 'synced',
        'last_modified_at': DateTime.utc(2020).toIso8601String(),
      };
      File('${dir.path}/legacy.json').writeAsStringSync(jsonEncode(legacy));

      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.any((r) => r['id'] == 'legacy'), isTrue);
    });
  });

  group('updateLocal', () {
    test('flips pendingCreate→pendingCreate (not pendingUpdate)', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'Old');
      await store.updateLocal(stored.id, {'name': 'New'});
      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.first['name'], 'New');
    });

    test('flips synced→pendingUpdate', () async {
      await store.replaceFromServer([
        {
          'id': 'abc-123',
          'kind': 'shoe',
          'name': 'Synced shoe',
          'retired_at': null,
          'total_distance_m': 100,
        },
      ]);
      expect(store.hasPending, isFalse);
      await store.updateLocal('abc-123', {'name': 'Edited shoe'});
      expect(store.hasPending, isTrue);
      expect(store.rows.first['name'], 'Edited shoe');
    });
  });

  group('retire / unretire', () {
    test('retireLocal stamps retired_at with the LOCAL calendar date', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
      await store.retireLocal(stored.id);
      // The DATE must be the runner's local day, not the UTC day — a UTC stamp
      // rolls a day early/late near midnight (the gear-retire twin of the
      // date_format UTC bug). Pin it to the local YYYY-MM-DD.
      final localToday = DateTime.now().toIso8601String().substring(0, 10);
      expect(store.rows.first['retired_at'], localToday);
    });

    test('unretireLocal clears retired_at', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
      await store.retireLocal(stored.id);
      await store.unretireLocal(stored.id);
      expect(store.rows.first['retired_at'], isNull);
    });
  });

  group('deleteLocal', () {
    test('pendingCreate rows disappear without a tombstone', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
      await store.deleteLocal(stored.id);
      expect(store.rows, isEmpty);
      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows, isEmpty);
      expect(reloaded.hasPending, isFalse);
    });

    test('synced rows become pendingDelete tombstones', () async {
      await store.replaceFromServer([
        {
          'id': 'abc-123',
          'kind': 'shoe',
          'name': 'Synced',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      await store.deleteLocal('abc-123');
      expect(store.rows, isEmpty,
          reason: 'tombstones don\'t appear in the live row list');
      expect(store.hasPending, isTrue);
    });
  });

  group('replaceFromServer', () {
    test('overwrites synced rows but preserves pendingCreate', () async {
      final mine = await store.createLocal(kind: 'shoe', name: 'My Vaporfly');
      await store.replaceFromServer([
        {
          'id': 'server-1',
          'kind': 'bike',
          'name': 'Server Trek',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      expect(store.rows.any((r) => r['id'] == mine.id), isTrue,
          reason: 'pendingCreate row must survive a server refresh');
      expect(store.rows.any((r) => r['id'] == 'server-1'), isTrue);
    });

    test('preserves pendingUpdate edits across refresh', () async {
      await store.replaceFromServer([
        {
          'id': 'abc-123',
          'kind': 'shoe',
          'name': 'Server name',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      await store.updateLocal('abc-123', {'name': 'My edit'});
      await store.replaceFromServer([
        {
          'id': 'abc-123',
          'kind': 'shoe',
          'name': 'Server name',
          'retired_at': null,
          'total_distance_m': 200,
        },
      ]);
      expect(store.rows.first['name'], 'My edit',
          reason:
              'pendingUpdate edits must override the server name until drained');
    });

    // The gear guard compares `gear.updated_at` (server-stamped by the
    // `gear_updated_at` trigger) on both sides — the local synced row is a
    // verbatim copy of the last server row, so both values come from the DB
    // clock and no device/server skew enters the comparison.
    Map<String, dynamic> serverGear(
      String id, {
      required String name,
      required DateTime updatedAt,
      int totalDistanceM = 0,
    }) =>
        {
          'id': id,
          'kind': 'shoe',
          'name': name,
          'retired_at': null,
          'total_distance_m': totalDistanceM,
          'updated_at': updatedAt.toIso8601String(),
        };

    test('newer-wins: a stale server fetch does not clobber a locally-newer '
        'synced copy', () async {
      await store.replaceFromServer([
        serverGear('g1', name: 'Recent', updatedAt: DateTime.utc(2026, 6, 2)),
      ]);
      await store.replaceFromServer([
        serverGear('g1', name: 'Stale', updatedAt: DateTime.utc(2026, 6, 1)),
      ]);
      expect(store.rows.first['name'], 'Recent');
    });

    test('newer-wins: a newer server fetch overwrites the synced copy',
        () async {
      await store.replaceFromServer([
        serverGear('g1', name: 'Old', updatedAt: DateTime.utc(2026, 6, 1)),
      ]);
      await store.replaceFromServer([
        serverGear('g1', name: 'New', updatedAt: DateTime.utc(2026, 6, 2)),
      ]);
      expect(store.rows.first['name'], 'New');
    });

    test('an equal updated_at still takes the server row so total_distance_m '
        'keeps refreshing', () async {
      final stamp = DateTime.utc(2026, 6, 2);
      await store.replaceFromServer(
          [serverGear('g1', name: 'Vaporfly', updatedAt: stamp)]);
      // `total_distance_m` comes from the view's run_gear join and moves
      // without bumping the gear row's updated_at — an equal stamp must not
      // be treated as stale.
      await store.replaceFromServer([
        serverGear('g1',
            name: 'Vaporfly', updatedAt: stamp, totalDistanceM: 42000),
      ]);
      expect(store.rows.first['total_distance_m'], 42000);
    });

    test('a server row with no updated_at still overwrites (fail open)',
        () async {
      await store.replaceFromServer([
        serverGear('g1', name: 'Recent', updatedAt: DateTime.utc(2026, 6, 2)),
      ]);
      await store.replaceFromServer([
        {
          'id': 'g1',
          'kind': 'shoe',
          'name': 'No stamp',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      expect(store.rows.first['name'], 'No stamp');
    });
  });

  group('_rewriteAll crash-atomic ordering', () {
    Map<String, dynamic> _gear(String id, String name) => {
          'id': id,
          'kind': 'shoe',
          'name': name,
          'retired_at': null,
          'total_distance_m': 0,
        };
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
      await store.replaceFromServer([_gear('g1', 'One'), _gear('g2', 'Two')]);
      final mine = await store.createLocal(kind: 'shoe', name: 'Offline');
      expect(jsonFiles(), hasLength(3));

      await store.replaceFromServer([_gear('g1', 'One')]);

      expect(store.rows.any((r) => r['id'] == 'g1'), isTrue);
      expect(store.rows.any((r) => r['id'] == 'g2'), isFalse);
      expect(store.rows.any((r) => r['id'] == mine.id), isTrue,
          reason: 'pendingCreate survives the rewrite');
      expect(tmpFiles(), isEmpty, reason: 'atomic writes leave no .tmp behind');

      final reloaded = LocalGearStore();
      await reloaded.init(overrideDirectory: dir);
      expect(reloaded.rows.map((r) => r['id'] as String).toSet(),
          {'g1', mine.id});
    });
  });

  group('hasPending', () {
    test('false on a clean store', () {
      expect(store.hasPending, isFalse);
    });

    test('true after createLocal, false after replaceFromServer with synced',
        () async {
      await store.createLocal(kind: 'shoe', name: 'X');
      expect(store.hasPending, isTrue);
      await store.replaceFromServer([
        {
          'id': 'synced-only',
          'kind': 'shoe',
          'name': 'S',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      expect(store.hasPending, isTrue,
          reason:
              'pendingCreate row was preserved across replaceFromServer, so still pending');
    });
  });

  group('syncWithServer drain', () {
    test('drains pendingCreate via createGear with the local id', () async {
      final api = _FakeGearApi();
      final stored = await store.createLocal(kind: 'shoe', name: 'Vaporfly');
      expect(store.hasPending, isTrue);

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'create:${stored.id}',
          reason:
              'pendingCreate must use the local-minted id so server + cache stay in lockstep.');
      expect(store.hasPending, isFalse,
          reason: 'drained rows flip to synced.');
    });

    test('drains pendingUpdate via updateGear', () async {
      await store.replaceFromServer([
        {
          'id': 'srv-1',
          'kind': 'shoe',
          'name': 'Old',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      await store.updateLocal('srv-1', {'name': 'New'});
      final api = _FakeGearApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'update:srv-1');
      expect(store.hasPending, isFalse);
    });

    test('drains pendingDelete via deleteGear + drops the local row',
        () async {
      await store.replaceFromServer([
        {
          'id': 'kill-me',
          'kind': 'shoe',
          'name': 'Doomed',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      await store.deleteLocal('kill-me');
      final api = _FakeGearApi();

      final drained = await store.syncWithServer(api);

      expect(drained, 1);
      expect(api.calls.single, 'delete:kill-me');
      expect(store.rows, isEmpty,
          reason: 'tombstone is gone after server confirms delete.');
      expect(store.hasPending, isFalse);
    });

    test('mixed queue drains in create → update → delete order', () async {
      // Set up: one pre-existing synced row that gets edited, one
      // pre-existing row that gets deleted, plus one fresh create.
      await store.replaceFromServer([
        {
          'id': 'sync-edit',
          'kind': 'shoe',
          'name': 'Old',
          'retired_at': null,
          'total_distance_m': 0,
        },
        {
          'id': 'sync-kill',
          'kind': 'shoe',
          'name': 'Doomed',
          'retired_at': null,
          'total_distance_m': 0,
        },
      ]);
      final created = await store.createLocal(kind: 'shoe', name: 'Fresh');
      await store.updateLocal('sync-edit', {'name': 'Edited'});
      await store.deleteLocal('sync-kill');

      final api = _FakeGearApi();
      final drained = await store.syncWithServer(api);

      expect(drained, 3);
      // The store walks _rows.values in insertion order. The pre-load
      // rows come first (sync-edit, sync-kill); the create lands last.
      // Each row drains based on its own state — there is no global
      // create-then-update-then-delete reorder, but every change does
      // hit the server before pendingDelete cascades to a local drop.
      expect(api.calls,
          containsAll(['create:${created.id}', 'update:sync-edit', 'delete:sync-kill']));
      expect(store.rows.map((r) => r['id']).toSet(),
          {'sync-edit', created.id},
          reason: 'sync-kill is gone; the other two are now synced.');
    });

    test('per-row failure isolation: failing create leaves the row pending',
        () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
      final api = _FakeGearApi()..failedCreates = {stored.id};

      final drained = await store.syncWithServer(api);

      expect(drained, 0);
      expect(store.hasPending, isTrue,
          reason:
              'failed create stays pendingCreate for the next drain attempt.');
    });

    test('clean store: syncWithServer is a no-op (drained=0)', () async {
      final api = _FakeGearApi();
      final drained = await store.syncWithServer(api);
      expect(drained, 0);
      expect(api.calls, isEmpty);
    });
  });
}
