import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_food_store.dart';

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
    required DateTime loggedAt,
    required String itemName,
    String? mealSlot,
    double? calories,
    double? proteinG,
    double? carbsG,
    double? fatG,
    bool isPublic = false,
    String? externalId,
    DateTime? lastModifiedAt,
  }) async {
    calls.add('create:$id');
    if (failedCreates.contains(id)) throw StateError('create failed');
    return FoodLogRow(
      id: id ?? 'server-generated',
      userId: 'test-user',
      loggedAt: loggedAt,
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
  DateTime? loggedAt,
}) =>
    {
      'id': id,
      'logged_at': (loggedAt ?? DateTime.utc(2026, 6, 1, 12)).toIso8601String(),
      'item_name': itemName ?? 'Server item',
      'meal_slot': null,
      'calories': null,
      'protein_g': null,
      'carbs_g': null,
      'fat_g': null,
      'is_public': false,
      'external_id': null,
      'last_modified_at': DateTime.utc(2026, 6, 1).toIso8601String(),
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

  group('createLocal', () {
    test('mints a v4 UUID and marks the entry pendingCreate', () async {
      final stored = await store.createLocal(
        loggedAt: DateTime.utc(2026, 6, 2, 8),
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
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'Chicken bowl', calories: 640);
      final fresh = LocalFoodStore();
      await fresh.init(overrideDirectory: dir);
      expect(fresh.rows, hasLength(1));
      expect(fresh.rows.first['item_name'], 'Chicken bowl');
      expect(fresh.rows.first['calories'], 640);
    });

    test('rows are sorted newest-logged first', () async {
      await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 2, 8), itemName: 'Breakfast');
      await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 2, 13), itemName: 'Lunch');
      expect(store.rows.first['item_name'], 'Lunch');
      expect(store.rows.last['item_name'], 'Breakfast');
    });
  });

  group('entriesForRange', () {
    test('returns only entries within the half-open day window', () async {
      await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 1, 23), itemName: 'Yesterday');
      await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 2, 8), itemName: 'Today');
      await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 3, 0), itemName: 'Tomorrow');
      final today = store.entriesForRange(
          DateTime.utc(2026, 6, 2), DateTime.utc(2026, 6, 3));
      expect(today.map((r) => r['item_name']), ['Today']);
    });
  });

  group('updateLocal', () {
    test('pendingCreate stays pendingCreate', () async {
      final stored = await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'Old');
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
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
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
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'Mine');
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
  });

  group('syncWithServer drain', () {
    test('drains pendingCreate via logFood with the local id', () async {
      final api = _FakeFoodApi();
      final stored = await store.createLocal(
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'Oats');

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
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'Fresh');
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
          loggedAt: DateTime.utc(2026, 6, 2), itemName: 'X');
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
}
