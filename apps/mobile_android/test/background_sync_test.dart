import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/background_sync.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';

class _FakeApiClient extends ApiClient {
  String? fakeUserId = 'user-1';
  bool throwOnSaveBatch = false;
  final List<List<String>> savedBatchIds = [];
  Set<String> saveBatchFailedIds = const <String>{};
  int saveBatchCallCount = 0;

  final List<String> deletedIds = [];
  final Set<String> deleteFailFor = {};

  final List<String> savedRouteIds = [];
  final Set<String> routeSaveFailFor = {};

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

  @override
  Future<void> deleteRunById(String runId) async {
    if (deleteFailFor.contains(runId)) throw Exception('rls denied $runId');
    deletedIds.add(runId);
  }

  @override
  Future<void> saveRoute(Route route) async {
    if (routeSaveFailFor.contains(route.id)) {
      throw Exception('route push denied ${route.id}');
    }
    savedRouteIds.add(route.id);
  }
}

Route _route(String id) => Route(
      id: id,
      userId: 'test-user',
      name: 'Park loop',
      waypoints: const [
        Waypoint(lat: 47.37, lng: 8.54),
        Waypoint(lat: 47.371, lng: 8.541),
      ],
      distanceMetres: 5000,
      isPublic: false,
      isStarred: false,
    );

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
  late Directory routeTempDir;
  late LocalRunStore store;
  late LocalRouteStore routeStore;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('background_sync_test_');
    store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
    routeTempDir =
        Directory.systemTemp.createTempSync('background_sync_route_test_');
    routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: routeTempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    if (routeTempDir.existsSync()) routeTempDir.deleteSync(recursive: true);
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

      await runBackgroundSyncCycle(api, store, routeStore);

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

      await runBackgroundSyncCycle(api, store, routeStore);

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

      await runBackgroundSyncCycle(api, store, routeStore);

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

      await runBackgroundSyncCycle(api, store, routeStore);

      expect(store.unsyncedRuns.map((r) => r.id).toSet(), {'r-bad'},
          reason: 'r-good must be marked synced; r-bad retries next '
              'cycle when its track upload might succeed');
    });
  });

  group('runBackgroundSyncCycle — never-synced + queued for delete '
      '(issue #675)', () {
    test('a run deleted offline before its first push is never uploaded',
        () async {
      await store.save(_runForOwner('r-never-synced', 'user-a'));
      await store.markPendingRemoteDelete('r-never-synced',
          ownerUserId: 'user-a');

      final api = _FakeApiClient()..fakeUserId = 'user-a';

      await runBackgroundSyncCycle(api, store, routeStore);

      expect(api.saveBatchCallCount, 0,
          reason: 'the background cycle must never push a run that is '
              'already queued for deletion, even if it was never synced');
      expect(api.deletedIds, ['r-never-synced']);
      expect(store.runs, isEmpty);
      expect(store.pendingRemoteDeleteIds, isEmpty);
    });
  });

  group('runBackgroundSyncCycle — guard clauses', () {
    test('empty queue is a no-op (no API call)', () async {
      final api = _FakeApiClient()..fakeUserId = 'user-a';

      await runBackgroundSyncCycle(api, store, routeStore);

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
      await runBackgroundSyncCycle(api, store, routeStore);

      // Run stays unsynced, ready for the next cycle.
      expect(store.unsyncedCount, 1);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Issue #385: the WorkManager cycle used to push unsynced runs ONLY,
  // silently skipping the pending-remote-delete and unsynced-route
  // queues the foreground SyncService drains every cycle. So an offline
  // delete or an offline-built route never made progress while the app
  // was backgrounded. The cycle now drains all three.
  group('runBackgroundSyncCycle — drains deletes + routes (issue #385)', () {
    test('a pending remote-delete AND an unsynced route both drain', () async {
      await store.markPendingRemoteDelete('r-deleted');
      await routeStore.save(_route('route-offline'));
      expect(routeStore.unsyncedRoutes.map((r) => r.id), ['route-offline']);

      final api = _FakeApiClient()..fakeUserId = 'user-a';

      await runBackgroundSyncCycle(api, store, routeStore);

      expect(api.deletedIds, ['r-deleted'],
          reason: 'the pending remote-delete queue must drain in the '
              'background, not only on a foreground trigger');
      expect(store.pendingRemoteDeleteIds, isEmpty);
      expect(api.savedRouteIds, ['route-offline'],
          reason: 'the offline-built route must upload in the background');
      expect(routeStore.unsyncedRoutes, isEmpty);
    });

    test('a failing delete queue does not abort the route drain '
        '(layered resilience)', () async {
      await store.markPendingRemoteDelete('r-bad');
      await routeStore.save(_route('route-ok'));

      final api = _FakeApiClient()
        ..fakeUserId = 'user-a'
        ..deleteFailFor.add('r-bad');

      await runBackgroundSyncCycle(api, store, routeStore);

      expect(store.pendingRemoteDeleteIds, {'r-bad'},
          reason: 'the failed delete stays queued for the next cycle');
      expect(api.savedRouteIds, ['route-ok'],
          reason: 'a failure draining one queue must not abort the others');
      expect(routeStore.unsyncedRoutes, isEmpty);
    });

    test('a failing route push leaves the route queued but still drains '
        'the delete queue', () async {
      await store.markPendingRemoteDelete('r-gone');
      await routeStore.save(_route('route-bad'));

      final api = _FakeApiClient()
        ..fakeUserId = 'user-a'
        ..routeSaveFailFor.add('route-bad');

      await runBackgroundSyncCycle(api, store, routeStore);

      expect(api.deletedIds, ['r-gone']);
      expect(routeStore.unsyncedRoutes.map((r) => r.id), ['route-bad'],
          reason: 'a failed route push stays unsynced for the next cycle');
    });
  });
}
