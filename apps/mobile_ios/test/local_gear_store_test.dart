import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/local_gear_store.dart';

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
}
