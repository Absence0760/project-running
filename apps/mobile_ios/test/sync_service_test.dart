import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';
import '../lib/sync_service.dart';

class _FakeApiClient extends ApiClient {
  String? fakeUserId = 'user-1';

  bool throwOnSaveBatch = false;
  Object? saveBatchError;
  final List<List<String>> savedBatchIds = [];

  final Set<String> deleteFailFor = {};
  final List<String> deletedIds = [];

  int saveBatchCallCount = 0;
  int deleteCallCount = 0;

  @override
  String? get userId => fakeUserId;

  @override
  Future<void> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    saveBatchCallCount++;
    if (throwOnSaveBatch) {
      throw saveBatchError ?? Exception('boom');
    }
    savedBatchIds.add(runs.map((r) => r.id).toList());
  }

  @override
  Future<void> deleteRunById(String runId) async {
    deleteCallCount++;
    if (deleteFailFor.contains(runId)) {
      throw Exception('rls denied $runId');
    }
    deletedIds.add(runId);
  }
}

Run makeRun(String id) => Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      track: const [],
      source: RunSource.app,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalRunStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('sync_service_test_');
    store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('SyncService._trySync — guard clauses', () {
    test('no-op when apiClient is null', () async {
      await store.save(makeRun('r-1'));
      final svc = SyncService(apiClient: null, runStore: store);

      await svc.debugTrySync('test');

      expect(store.unsyncedCount, 1);
    });

    test('no-op when apiClient.userId is null (signed out)', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..fakeUserId = null;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 0);
      expect(store.unsyncedCount, 1);
    });

    test('no-op when there is nothing unsynced and nothing pending to delete',
        () async {
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 0);
      expect(api.deleteCallCount, 0);
    });
  });

  group('SyncService._trySync — push path', () {
    test('pushes every unsynced run via saveRunsBatch and marks them synced',
        () async {
      await store.save(makeRun('r-1'));
      await store.save(makeRun('r-2'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.first.toSet(), {'r-1', 'r-2'});
      expect(store.unsyncedCount, 0);
    });

    test('saveRunsBatch failure leaves runs unsynced (failure swallowed)',
        () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      expect(store.unsyncedCount, 1,
          reason: 'failure must not flip the unsynced flag');
    });
  });

  group('SyncService._trySync — pending-delete drain', () {
    test('successful delete removes from cloud, local store, and pending set',
        () async {
      await store.save(makeRun('r-1'));
      await store.markSynced('r-1');
      await store.markPendingRemoteDelete('r-1');
      expect(store.pendingRemoteDeleteIds, contains('r-1'));

      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.deletedIds, ['r-1']);
      expect(store.runs, isEmpty);
      expect(store.pendingRemoteDeleteIds, isEmpty);
    });

    test('one failing delete does not poison the rest of the queue', () async {
      for (final id in ['r-bad', 'r-ok-1', 'r-ok-2']) {
        await store.save(makeRun(id));
        await store.markSynced(id);
        await store.markPendingRemoteDelete(id);
      }
      final api = _FakeApiClient()..deleteFailFor.add('r-bad');
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.deletedIds.toSet(), {'r-ok-1', 'r-ok-2'});
      expect(store.pendingRemoteDeleteIds, {'r-bad'});
      expect(store.runs.map((r) => r.id).toSet(), {'r-bad'});
    });

    test('deleteRunById is called once per pending id', () async {
      for (final id in ['r-1', 'r-2', 'r-3']) {
        await store.save(makeRun(id));
        await store.markSynced(id);
        await store.markPendingRemoteDelete(id);
      }
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.deleteCallCount, 3);
    });
  });

  group('SyncService._trySync — combined paths', () {
    test('runs unsynced + a pending delete: both branches fire in one cycle',
        () async {
      await store.save(makeRun('r-new'));
      await store.save(makeRun('r-old'));
      await store.markSynced('r-old');
      await store.markPendingRemoteDelete('r-old');

      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.first, ['r-new']);
      expect(api.deletedIds, ['r-old']);
      expect(store.unsyncedCount, 0);
      expect(store.pendingRemoteDeleteIds, isEmpty);
    });

    test('reentrant call while a sync is in flight is dropped', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      final first = svc.debugTrySync('test-a');
      final second = svc.debugTrySync('test-b');
      await Future.wait([first, second]);

      expect(api.saveBatchCallCount, 1,
          reason:
              'second call must short-circuit on the _syncing guard so the '
              'same batch is not pushed twice');
    });
  });
}
