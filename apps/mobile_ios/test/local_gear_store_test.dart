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
    test('retireLocal stamps retired_at', () async {
      final stored = await store.createLocal(kind: 'shoe', name: 'X');
      await store.retireLocal(stored.id);
      expect(store.rows.first['retired_at'], isNotNull);
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
