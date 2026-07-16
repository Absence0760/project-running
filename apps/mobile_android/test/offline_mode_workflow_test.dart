import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_run_store.dart';
import '../lib/sync_service.dart';

/// End-to-end workflows that pin the competitive "Fully offline mode
/// without an account — record locally, sync later if you ever sign
/// in" line. Composes [LocalRunStore] + [SyncService] over realistic
/// user journeys — onboard offline, record several runs, eventually
/// sign in, watch the queue drain. Plus the cross-user contamination
/// guard on a shared device.
///
/// See `docs/architecture/decisions.md § 67`.

class _SignInControllableApi extends ApiClient {
  String? _userId; // null until sign-in
  bool throwOnPush = false;

  // Capture every batch the SyncService sends.
  final List<List<Run>> pushedBatches = [];
  Set<String> nextBatchFailedIds = const {};
  int saveBatchCallCount = 0;

  /// Test-only helper for setting the signed-in userId.
  /// (Named differently from `signIn` to avoid colliding with
  /// the ApiClient base method's named-args signature.)
  void simulateSignIn(String userId) {
    _userId = userId;
  }

  void simulateSignOut() {
    _userId = null;
  }

  @override
  String? get userId => _userId;

  @override
  Future<Set<String>> saveRunsBatch(
    List<Run> runs, {
    int uploadConcurrency = 8,
    int rowChunkSize = 100,
    void Function(int saved)? onProgress,
  }) async {
    saveBatchCallCount++;
    if (throwOnPush) throw Exception('boom');
    pushedBatches.add(List<Run>.from(runs));
    return nextBatchFailedIds;
  }

  @override
  Future<void> deleteRunById(String runId) async {}
}

Run _makeRun(String id, {DateTime? startedAt, Map<String, dynamic>? metadata}) {
  return Run(
    id: id,
    startedAt: startedAt ?? DateTime(2026, 4, 10, 8),
    duration: const Duration(minutes: 25),
    distanceMetres: 5000,
    track: const [],
    source: RunSource.app,
    metadata: metadata,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalRunStore store;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('offline_mode_test_');
    store = LocalRunStore();
    await store.init(overrideDirectory: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('Record without an account → sign in later', () {
    test('saving while signed out → tag stays null', () async {
      // Production wires the provider to () => api?.userId. The
      // ApiClient hasn't been created yet (no Supabase init) OR
      // the user hasn't signed in. Either way the provider
      // returns null and the tag is absent.
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;
      expect(api.userId, isNull);

      await store.save(_makeRun('r-1'));
      await store.save(_makeRun('r-2'));
      await store.save(_makeRun('r-3'));

      for (final r in store.runs) {
        expect(r.metadata?['created_by_user_id'], isNull,
            reason: '${r.id} must be untagged while signed out');
      }
    });

    test('sign in → drain → all signed-out runs land under the new user',
        () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      // Record 3 runs offline.
      await store.save(_makeRun('r-1'));
      await store.save(_makeRun('r-2'));
      await store.save(_makeRun('r-3'));
      expect(store.unsyncedCount, 3);

      // User signs up + signs in.
      api.simulateSignIn('user-fresh');

      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('signin');

      // All 3 untagged runs adopted to user-fresh + pushed.
      expect(api.saveBatchCallCount, 1);
      expect(api.pushedBatches.single.map((r) => r.id).toSet(),
          {'r-1', 'r-2', 'r-3'});
      // Queue drained.
      expect(store.unsyncedCount, 0);
    });

    test('partial-failure on first sign-in drain: succeeded runs marked, '
        'failed stay in queue', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;
      await store.save(_makeRun('r-good'));
      await store.save(_makeRun('r-bad'));

      api.simulateSignIn('user-fresh');
      api.nextBatchFailedIds = {'r-bad'};

      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('signin');

      // The good run is now synced; the bad one stays unsynced.
      final unsynced = store.unsyncedRuns;
      expect(unsynced.map((r) => r.id), ['r-bad']);
    });

    test('record offline → sign in → record more (signed in) → next '
        'drain pushes both adopted + tagged', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      // Phase 1: offline.
      await store.save(_makeRun('r-offline-1'));
      await store.save(_makeRun('r-offline-2'));

      // Phase 2: sign in.
      api.simulateSignIn('user-a');

      // Phase 3: record more — these stamp 'user-a' on save.
      await store.save(_makeRun('r-online-1'));
      await store.save(_makeRun('r-online-2'));

      // Verify metadata shape:
      final byId = {for (final r in store.runs) r.id: r};
      expect(byId['r-offline-1']?.metadata?['created_by_user_id'], isNull);
      expect(byId['r-offline-2']?.metadata?['created_by_user_id'], isNull);
      expect(byId['r-online-1']?.metadata?['created_by_user_id'], 'user-a');
      expect(byId['r-online-2']?.metadata?['created_by_user_id'], 'user-a');

      // Phase 4: drain. All 4 push — offline-* adopt as user-a,
      // online-* already tagged user-a.
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('signin-then-record');

      expect(api.pushedBatches.single, hasLength(4));
      expect(store.unsyncedCount, 0);
    });
  });

  group('Shared device — cross-user contamination guard', () {
    test('user A records, signs out, user B signs in: B drain pushes '
        'NOTHING', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      // User A signs in + records.
      api.simulateSignIn('user-a');
      await store.save(_makeRun('r-a-1'));
      await store.save(_makeRun('r-a-2'));
      // Confirm A-tagged.
      for (final r in store.runs) {
        expect(r.metadata?['created_by_user_id'], 'user-a');
      }

      // User A signs out. The queue is still there on disk (we
      // deliberately don't wipe — A could sign back in and finish
      // syncing), but the getters are viewer-filtered (#230): a
      // signed-out viewer no longer sees A's tagged runs.
      api.simulateSignOut();
      expect(store.unsyncedCount, 0,
          reason: 'the badge must not show A\'s queue while signed out');
      api.simulateSignIn('user-a');
      expect(store.unsyncedCount, 2,
          reason: 'the queue is preserved for A, not wiped');
      api.simulateSignOut();

      // User B signs in.
      api.simulateSignIn('user-b');
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('user-b-first-sync');

      // Nothing pushed — A's runs are filtered out.
      expect(api.saveBatchCallCount, 0,
          reason: 'B must NOT silently push A\'s runs under B\'s '
              'account — the filter dropped them all');
      // A's runs stay queued for A; B's badge no longer counts them
      // (#230 — pre-fix B saw a stuck "2 unsynced" for foreign runs).
      expect(store.unsyncedCount, 0);
      api.simulateSignOut();
      api.simulateSignIn('user-a');
      expect(store.unsyncedCount, 2,
          reason: 'A\'s queue is intact, awaiting A\'s next drain');
    });

    test('user A returns → drain pushes A\'s runs successfully', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      // A records → signs out → B signs in → SKIPS A's runs.
      api.simulateSignIn('user-a');
      await store.save(_makeRun('r-a-1'));
      api.simulateSignOut();
      api.simulateSignIn('user-b');
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('b-sync');
      expect(api.saveBatchCallCount, 0);
      expect(store.unsyncedCount, 0,
          reason: 'B\'s badge no longer counts A\'s queued run (#230); '
              'the run itself stays on disk for A');

      // User A signs back in.
      api.simulateSignOut();
      api.simulateSignIn('user-a');
      await svc.debugTrySync('a-back');

      // A's run finally pushes.
      expect(api.saveBatchCallCount, 1);
      expect(api.pushedBatches.single.single.id, 'r-a-1');
      expect(store.unsyncedCount, 0);
    });

    test('mixed queue: A-tagged + B-tagged + untagged, signed in as B → '
        'only B + untagged push', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      // A's run.
      api.simulateSignIn('user-a');
      await store.save(_makeRun('r-a-1'));

      // B's run.
      api.simulateSignOut();
      api.simulateSignIn('user-b');
      await store.save(_makeRun('r-b-1'));

      // Untagged run (signed out save mid-sequence).
      api.simulateSignOut();
      await store.save(_makeRun('r-untagged'));

      // Back in as B.
      api.simulateSignIn('user-b');
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('mixed');

      // B + untagged pushed (untagged adopts to B); A's stays.
      expect(api.saveBatchCallCount, 1);
      expect(api.pushedBatches.single.map((r) => r.id).toSet(),
          {'r-b-1', 'r-untagged'});
      // A's run stays queued but is hidden from B's view (#230) —
      // switch to A to see it.
      expect(store.unsyncedRuns, isEmpty);
      api.simulateSignOut();
      api.simulateSignIn('user-a');
      expect(store.unsyncedRuns.map((r) => r.id), ['r-a-1']);
    });

    test('foreign-runs-only drain is NOT a failure (no backoff hit)',
        () async {
      // Skipping foreign runs is a no-op, not an error. The
      // backoff state machine treats it as success so legitimate
      // future drains aren't artificially delayed.
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;

      api.simulateSignIn('user-a');
      await store.save(_makeRun('r-a-1'));
      api.simulateSignOut();
      api.simulateSignIn('user-b');

      final svc = SyncService(apiClient: api, runStore: store);
      final before = svc.debugBackoffState().failures;
      await svc.debugTrySync('b-sync');
      final after = svc.debugBackoffState().failures;
      expect(after, before,
          reason: 'foreign-runs-only drain is success, not failure');
    });

    test('signing out preserves the queue (we do NOT wipe it)', () async {
      // Important UX contract: if a user signs out, their unsynced
      // runs stay locally so they can re-sign-in and push. Wiping
      // would be data loss.
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;
      api.simulateSignIn('user-a');
      await store.save(_makeRun('r-1'));
      expect(store.unsyncedCount, 1);

      // Sign out. The viewer-filtered badge drops to 0 (#230), but the
      // queue itself must survive on disk.
      api.simulateSignOut();
      expect(store.unsyncedCount, 0,
          reason: 'a signed-out viewer must not see A\'s queue');
      api.simulateSignIn('user-a');
      expect(store.unsyncedCount, 1,
          reason: 'sign-out must NOT wipe the local queue');
      // Runs still on disk (a fresh, unwired store reads everything).
      final fresh = LocalRunStore();
      await fresh.init(overrideDirectory: tempDir);
      expect(fresh.runs, hasLength(1));
    });
  });

  group('Cold-start with offline-saved runs', () {
    test('signed-out save → kill app → cold start → runs still in queue',
        () async {
      // Process restart simulation. The runs sit on disk through
      // both lifetimes.
      {
        final api = _SignInControllableApi();
        store.currentUserIdProvider = () => api.userId;
        await store.save(_makeRun('r-1'));
        await store.save(_makeRun('r-2'));
      }
      // "Process restart" — fresh store instance over the same dir.
      final fresh = LocalRunStore();
      await fresh.init(overrideDirectory: tempDir);
      expect(fresh.runs, hasLength(2));
      expect(fresh.unsyncedCount, 2,
          reason: 'unsynced state must survive a cold start');
    });

    test('cold start → sign in → drain (the classic returning-user flow)',
        () async {
      // Day 1: record offline.
      {
        final api = _SignInControllableApi();
        store.currentUserIdProvider = () => api.userId;
        await store.save(_makeRun('r-day-1'));
      }
      // App killed.
      // Day 2: cold start with a fresh store but same disk.
      final fresh = LocalRunStore();
      await fresh.init(overrideDirectory: tempDir);
      final api = _SignInControllableApi();
      fresh.currentUserIdProvider = () => api.userId;

      // User signs in.
      api.simulateSignIn('user-returning');
      final svc = SyncService(apiClient: api, runStore: fresh);
      await svc.debugTrySync('returning-user');

      expect(api.saveBatchCallCount, 1);
      expect(api.pushedBatches.single.single.id, 'r-day-1');
      expect(fresh.unsyncedCount, 0);
    });
  });

  group('Edit-while-offline + sync', () {
    test('edit an offline-saved run before signing in → push reflects '
        'the edit', () async {
      final api = _SignInControllableApi();
      store.currentUserIdProvider = () => api.userId;
      await store.save(_makeRun('r-1', metadata: {'title': 'first'}));

      // Edit the run while still offline. update() re-stamps
      // last_modified_at.
      await store.update(_makeRun('r-1', metadata: {'title': 'edited'}));

      // Sign in + drain. The edited title is what reaches the cloud.
      api.simulateSignIn('user-a');
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('after-edit');

      expect(api.pushedBatches.single.single.metadata!['title'],
          'edited');
    });
  });

  group('SyncService gate clauses', () {
    test('no api configured → no drain attempt', () async {
      // The "Supabase not configured" build path: api is null,
      // the bridge never tries to call out.
      store.currentUserIdProvider = () => null;
      await store.save(_makeRun('r-1'));
      final svc = SyncService(apiClient: null, runStore: store);
      await svc.debugTrySync('no-api');
      // Store untouched; queue still 1.
      expect(store.unsyncedCount, 1);
    });

    test('signed out (api.userId is null) → no drain attempt', () async {
      final api = _SignInControllableApi(); // userId starts null
      store.currentUserIdProvider = () => api.userId;
      await store.save(_makeRun('r-1'));
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('signed-out');
      expect(api.saveBatchCallCount, 0);
      expect(store.unsyncedCount, 1);
    });
  });
}
