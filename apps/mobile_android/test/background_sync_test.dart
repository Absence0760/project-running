import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/background_sync.dart';
import '../lib/local_run_store.dart';

class _FakeApiClient extends ApiClient {
  String? fakeUserId = 'user-1';
  bool throwOnSaveBatch = false;
  final List<List<String>> savedBatchIds = [];
  Set<String> saveBatchFailedIds = const <String>{};
  int saveBatchCallCount = 0;

  @override
  String? get userId => fakeUserId;

  @override
  Future<Set<String>> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    saveBatchCallCount++;
    if (throwOnSaveBatch) throw Exception('boom');
    savedBatchIds.add(runs.map((r) => r.id).toList());
    return saveBatchFailedIds;
  }
}

Run _runForOwner(String id, String? ownerUserId) => Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      track: const [],
      source: RunSource.app,
      metadata: ownerUserId == null
          ? null
          : {'created_by_user_id': ownerUserId},
    );

Run _untaggedRun(String id) => Run(
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
    tempDir = Directory.systemTemp.createTempSync('background_sync_test_');
    store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  // ────────────────────────────────────────────────────────────────
  // The headline guarantee. Background sync runs in its OWN process
  // (WorkManager spawns a fresh isolate, re-init Supabase from
  // dotenv) — without the owner-tag filter, on a shared device where
  // User A records a run, signs out, and User B signs in, the next
  // WorkManager fire would push A's run under B's account. The
  // foreground SyncService applies this filter via
  // `filterRunsForCurrentUser`; the background path must too.
  group('runBackgroundSyncCycle — owner-tag filter', () {
    test('signed in as user-b, store has runs owned by user-a → batch '
        'push is NOT called', () async {
      await store.save(_runForOwner('r-a-1', 'user-a'));
      await store.save(_runForOwner('r-a-2', 'user-a'));

      final api = _FakeApiClient()..fakeUserId = 'user-b';

      await runBackgroundSyncCycle(api, store);

      expect(api.saveBatchCallCount, 0,
          reason: 'background sync must NOT push user-a runs under '
              'user-b\'s session — the WorkManager path runs in its own '
              'process and must apply the same owner-tag guard as the '
              'foreground SyncService.');
      expect(store.unsyncedCount, 2,
          reason: 'foreign runs stay in the queue for their rightful '
              'owner to sync when they sign back in');
    });

    test('signed in as user-a, mix of user-a + user-b runs → only '
        'user-a runs are pushed', () async {
      await store.save(_runForOwner('r-a-1', 'user-a'));
      await store.save(_runForOwner('r-b-1', 'user-b'));
      await store.save(_runForOwner('r-a-2', 'user-a'));

      final api = _FakeApiClient()..fakeUserId = 'user-a';

      await runBackgroundSyncCycle(api, store);

      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.single.toSet(), {'r-a-1', 'r-a-2'});
      expect(store.unsyncedRuns.map((r) => r.id).toSet(), {'r-b-1'},
          reason: 'user-b\'s run remains unsynced after a user-a '
              'background drain');
    });

    test('untagged runs (legacy / saved-while-signed-out) adopt to '
        'the current user', () async {
      await store.save(_untaggedRun('legacy-1'));
      await store.save(_untaggedRun('legacy-2'));

      final api = _FakeApiClient()..fakeUserId = 'user-fresh';

      await runBackgroundSyncCycle(api, store);

      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.single.toSet(),
          {'legacy-1', 'legacy-2'},
          reason: 'untagged runs adopt to whichever user is signed in — '
              'matches the foreground SyncService contract');
    });
  });

  group('runBackgroundSyncCycle — partial track-upload failures', () {
    test('a corrupted track stays unsynced; the rest of the batch '
        'is marked synced', () async {
      await store.save(_runForOwner('r-good', 'user-a'));
      await store.save(_runForOwner('r-bad', 'user-a'));

      final api = _FakeApiClient()
        ..fakeUserId = 'user-a'
        ..saveBatchFailedIds = {'r-bad'};

      await runBackgroundSyncCycle(api, store);

      expect(store.unsyncedRuns.map((r) => r.id).toSet(), {'r-bad'},
          reason: 'r-good must be marked synced; r-bad retries next '
              'cycle when its track upload might succeed');
    });
  });

  group('runBackgroundSyncCycle — guard clauses', () {
    test('empty queue is a no-op (no API call)', () async {
      final api = _FakeApiClient()..fakeUserId = 'user-a';

      await runBackgroundSyncCycle(api, store);

      expect(api.saveBatchCallCount, 0);
    });

    test('a thrown saveRunsBatch is swallowed so the WorkManager '
        'task does not retry endlessly', () async {
      // Reason: WorkManager re-runs a task that throws — and re-runs
      // it again on the next firing too. A swallowed error here
      // means we get one shot per scheduled fire, which is the
      // intended cadence.
      await store.save(_runForOwner('r-1', 'user-a'));
      final api = _FakeApiClient()
        ..fakeUserId = 'user-a'
        ..throwOnSaveBatch = true;

      // Must NOT throw out of the helper.
      await runBackgroundSyncCycle(api, store);

      // Run stays unsynced, ready for the next cycle.
      expect(store.unsyncedCount, 1);
    });
  });
}
