import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/widgets.dart';
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

  /// Returned to the SyncService when `saveRunsBatch` "succeeds" —
  /// matches the partial-success contract: the set is the ids whose
  /// track upload failed and were therefore skipped from the upsert.
  /// Tests that want to exercise the "full success" path leave this
  /// empty; tests that want the partial-failure path populate it.
  Set<String> saveBatchFailedIds = const <String>{};

  @override
  Future<Set<String>> saveRunsBatch(
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
    return saveBatchFailedIds;
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

Run makeRun(String id, {Map<String, dynamic>? metadata}) => Run(
      id: id,
      startedAt: DateTime(2026, 4, 10, 8),
      duration: const Duration(minutes: 25),
      distanceMetres: 5000,
      track: const [],
      source: RunSource.app,
      metadata: metadata,
    );

/// Convenience for the owner-tag tests: build a run with the tag
/// pre-stamped (simulating what `LocalRunStore.save` produces).
Run makeOwnedRun(String id, String? ownerUserId) {
  return Run(
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
}

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

    test(
        'partial-success: track-upload failures stay unsynced, the rest '
        'are marked — the corrupted-track-poisons-the-queue regression',
        () async {
      // Three runs, one with a "corrupted" track (returned in the
      // failed set by saveRunsBatch). The fix should mark r-ok-1 and
      // r-ok-2 as synced and leave r-bad in the unsynced queue.
      // Before the fix, a single failing track upload bubbled through
      // `Future.wait`, the whole batch threw, no runs were marked,
      // and SyncService backed off — same three runs kept failing
      // forever.
      await store.save(makeRun('r-ok-1'));
      await store.save(makeRun('r-bad'));
      await store.save(makeRun('r-ok-2'));
      final api = _FakeApiClient()..saveBatchFailedIds = {'r-bad'};
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      expect(store.unsyncedRuns.map((r) => r.id).toList(), ['r-bad'],
          reason: 'failed-track run must stay unsynced for retry; the '
              'two clean runs must be marked synced.');
      expect(store.unsyncedCount, 1);
    });

    test(
        'partial-success failures trip the cycle-failure path so backoff '
        'kicks in (next cycle won\'t immediately retry the failed run)',
        () async {
      // When ANY run fails its track upload, the cycle counts as a
      // failure so the backoff window kicks in. Without this, a
      // permanently-corrupted track would keep retrying every second
      // on every connectivity flap.
      await store.save(makeRun('r-bad'));
      final api = _FakeApiClient()..saveBatchFailedIds = {'r-bad'};
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      final state = svc.debugBackoffState();
      expect(state.failures, 1,
          reason: 'partial failure must increment the failure counter '
              'so backoff applies to the next cycle.');
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

  group('SyncService — lifecycle wiring', () {
    test('didChangeAppLifecycleState(resumed) triggers a sync', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
      // _trySync is fire-and-forget from the observer; let microtasks drain.
      await Future<void>.delayed(Duration.zero);
      // The sync future itself is async; let one more macrotask round trip.
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 1);
    });

    test('didChangeAppLifecycleState(paused) does NOT trigger a sync',
        () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.didChangeAppLifecycleState(AppLifecycleState.paused);
      svc.didChangeAppLifecycleState(AppLifecycleState.inactive);
      svc.didChangeAppLifecycleState(AppLifecycleState.detached);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 0);
    });
  });

  group('SyncService — connectivity wiring', () {
    test('debugOnConnectivity([wifi]) triggers a sync', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.debugOnConnectivity([ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 1);
    });

    test('debugOnConnectivity([mobile]) and [ethernet] also trigger', () async {
      await store.save(makeRun('r-mobile'));
      await store.save(makeRun('r-ethernet'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.debugOnConnectivity([ConnectivityResult.mobile]);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      // The first sync drained both runs in one batch; mark them so a
      // second connectivity event has fresh work to do.
      await store.save(makeRun('r-after-mobile'));

      svc.debugOnConnectivity([ConnectivityResult.ethernet]);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      // Two distinct sync cycles → two batch pushes.
      expect(api.saveBatchCallCount, 2);
    });

    test('debugOnConnectivity([none]) does NOT trigger a sync', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.debugOnConnectivity([ConnectivityResult.none]);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 0);
    });

    test('debugOnConnectivity with ANY online result in the list triggers',
        () async {
      // Multi-result is the common shape on Android — connectivity_plus
      // can report `[wifi, vpn]` or similar. The guard uses .any, so a
      // mixed list with at least one online entry should fire.
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.debugOnConnectivity([ConnectivityResult.bluetooth, ConnectivityResult.wifi]);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 1);
    });

    test('debugOnConnectivity([bluetooth]) alone does NOT trigger', () async {
      // Bluetooth tethering isn't routed as wifi/mobile/ethernet by
      // connectivity_plus; the guard intentionally excludes it.
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.debugOnConnectivity([ConnectivityResult.bluetooth]);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 0);
    });
  });

  group('SyncService — start / stop', () {
    test('start() fires an initial sync and registers as a binding observer',
        () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      svc.start();
      // Wait for the startup _trySync future.
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 1, reason: 'startup _trySync should fire');

      // Sanity check: lifecycle events now route through the registered
      // observer. Save a fresh run, simulate a resume.
      await store.save(makeRun('r-2'));
      svc.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(api.saveBatchCallCount, 2);

      svc.stop();
    });

    test('stop() cancels the connectivity subscription and removes the observer',
        () async {
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);
      svc.start();
      // Allow startup _trySync to settle (no runs to push, so it's a
      // no-op anyway).
      await Future<void>.delayed(const Duration(milliseconds: 1));
      svc.stop();

      // After stop, lifecycle events on the binding don't route to us
      // anymore. We can't directly observe the unsubscription state,
      // but we can confirm a freshly-saved run and a resume DON'T fire
      // a sync via the observer (since we removed ourselves).
      await store.save(makeRun('r-1'));
      // Send a state change through the binding (not on us — we're
      // detached). The binding still calls handlers on registered
      // observers, but svc isn't one anymore.
      WidgetsBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 1));

      expect(api.saveBatchCallCount, 0,
          reason: 'svc unregistered itself in stop()');
    });
  });

  group('SyncService — backoff after failure', () {
    test('successful cycle leaves backoff state at zero', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      final s = svc.debugBackoffState();
      expect(s.failures, 0);
      expect(s.lastFailureAt, isNull);
      expect(s.backoff, Duration.zero);
    });

    test('failure increments the counter and arms a 60 s backoff', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      final s = svc.debugBackoffState();
      expect(s.failures, 1);
      expect(s.lastFailureAt, isNotNull);
      expect(s.backoff, const Duration(seconds: 60));
    });

    test('automatic retry inside the backoff window is short-circuited',
        () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');
      expect(api.saveBatchCallCount, 1);

      // Same connectivity flap fires twice in quick succession; backoff
      // should swallow the second.
      await svc.debugTrySync('connectivity');
      expect(api.saveBatchCallCount, 1,
          reason: 'in-backoff retry must NOT hit the API');
    });

    test('manual retry bypasses the backoff window', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');
      expect(api.saveBatchCallCount, 1);

      await svc.debugTrySync('manual');
      expect(api.saveBatchCallCount, 2,
          reason: 'manual reason must bypass backoff');
    });

    test('consecutive failures double the backoff up to a 30 min cap',
        () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      // Drive five failures using 'manual' to bypass the in-backoff guard.
      for (var i = 0; i < 5; i++) {
        await svc.debugTrySync('manual');
      }
      // 60s, 120s, 240s, 480s, 960s — fifth failure → 960s.
      expect(svc.debugBackoffState().failures, 5);
      expect(svc.debugBackoffState().backoff, const Duration(seconds: 960));

      // Now drive enough additional failures that the doubling would
      // exceed 30 min; the clamp should hold it at exactly 30 min.
      for (var i = 0; i < 20; i++) {
        await svc.debugTrySync('manual');
      }
      expect(svc.debugBackoffState().backoff,
          const Duration(minutes: 30),
          reason: 'backoff must clamp at the 30 min ceiling');
    });

    test('a successful cycle after failures clears backoff', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');
      expect(svc.debugBackoffState().failures, 1);

      api.throwOnSaveBatch = false;
      await svc.debugTrySync('manual');

      final s = svc.debugBackoffState();
      expect(s.failures, 0);
      expect(s.lastFailureAt, isNull);
      expect(s.backoff, Duration.zero);
    });

    test('a failed delete drain also arms backoff', () async {
      await store.save(makeRun('r-bad'));
      await store.markSynced('r-bad');
      await store.markPendingRemoteDelete('r-bad');
      final api = _FakeApiClient()..deleteFailFor.add('r-bad');
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(svc.debugBackoffState().failures, 1,
          reason: 'a failed delete should count as a cycle failure');
    });

    test('debugClearBackoff resets the window to zero', () async {
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');
      expect(svc.debugBackoffState().failures, 1);

      svc.debugClearBackoff();
      final s = svc.debugBackoffState();
      expect(s.failures, 0);
      expect(s.lastFailureAt, isNull);
    });

    test('signin reason bypasses the backoff window', () async {
      // Reason: when the user signs out and signs back in, any prior
      // auth-rejection backoff is stale — the session that triggered
      // the 401 is gone. Without this bypass, a fresh sign-in is stuck
      // waiting out the (up to 30 min) window from the signed-out
      // cycle and the freshly-recorded offline run sits unsynced.
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');
      expect(api.saveBatchCallCount, 1);
      expect(svc.debugBackoffState().failures, 1);

      // A connectivity-driven retry inside the backoff is gated.
      await svc.debugTrySync('connectivity');
      expect(api.saveBatchCallCount, 1,
          reason: 'connectivity retry must stay gated by backoff');

      // A sign-in trigger must bypass.
      await svc.triggerSync('signin');
      expect(api.saveBatchCallCount, 2,
          reason: 'signin must bypass backoff so a fresh session does '
              'not inherit the dead one\'s rate-limit window');
    });
  });

  group('SyncService.triggerSync — public entry point', () {
    test('drives the same code path as the lifecycle observers', () async {
      // Reason: pin the contract — triggerSync is the canonical way
      // for main.dart's auth-state listener to drive a sync from the
      // signedIn event. A regression that hides triggerSync behind a
      // wrapper or routes it through a different code path would
      // silently break the offline-record-then-sign-in flow.
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient();
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.triggerSync('signin');

      expect(api.saveBatchCallCount, 1);
      expect(store.unsyncedCount, 0,
          reason: 'triggerSync must drain the queue end-to-end, '
              'identically to a startup / foreground / connectivity sync');
    });

    test('a failed triggerSync arms the backoff like any other cycle',
        () async {
      // Reason: triggerSync is a thin wrapper around _trySync — the
      // backoff bookkeeping must apply identically. Without this, an
      // adversarial caller could drive triggerSync('signin') in a
      // tight loop and hammer the backend through a perma-broken auth
      // session.
      await store.save(makeRun('r-1'));
      final api = _FakeApiClient()..throwOnSaveBatch = true;
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.triggerSync('signin');

      expect(svc.debugBackoffState().failures, 1);
    });
  });

  // ────────────────────────────────────────────────────────────────
  // Owner-tag filter — the load-bearing guard for the
  // record-without-an-account + sign-in-later flow on a shared
  // device. See `docs/decisions.md § 67`.
  group('filterRunsForCurrentUser (pure helper)', () {
    test('null current userId returns empty list', () {
      // SyncService doesn't call this path (it guards on
      // api.userId != null before drain) but pin the contract
      // — a null user can't own any run.
      final filtered = filterRunsForCurrentUser(
        [makeOwnedRun('r-1', 'user-a'), makeOwnedRun('r-2', null)],
        null,
      );
      expect(filtered, isEmpty);
    });

    test('runs with no created_by_user_id tag are adopted to current user',
        () {
      // Legacy runs (recorded before owner-tagging shipped) OR
      // runs recorded while signed-out adopt to whoever signs
      // in next. This is the "record offline → sign up → push"
      // headline flow.
      final filtered = filterRunsForCurrentUser(
        [makeOwnedRun('r-1', null), makeOwnedRun('r-2', null)],
        'user-a',
      );
      expect(filtered.map((r) => r.id), ['r-1', 'r-2']);
    });

    test('runs tagged with the current user pass through', () {
      final filtered = filterRunsForCurrentUser(
        [makeOwnedRun('r-1', 'user-a'), makeOwnedRun('r-2', 'user-a')],
        'user-a',
      );
      expect(filtered.map((r) => r.id), ['r-1', 'r-2']);
    });

    test('runs tagged with a DIFFERENT user are filtered OUT', () {
      // The cross-user contamination case. User A's runs stay in
      // the queue when User B is signed in — they don't sync.
      final filtered = filterRunsForCurrentUser(
        [makeOwnedRun('r-1', 'user-a')],
        'user-b',
      );
      expect(filtered, isEmpty);
    });

    test('mixed input: tagged-mine + tagged-different + untagged → only '
        'mine + untagged pass', () {
      final filtered = filterRunsForCurrentUser(
        [
          makeOwnedRun('r-mine-1', 'user-b'),
          makeOwnedRun('r-foreign', 'user-a'),
          makeOwnedRun('r-untagged', null),
          makeOwnedRun('r-mine-2', 'user-b'),
          makeOwnedRun('r-foreign-2', 'user-c'),
        ],
        'user-b',
      );
      expect(filtered.map((r) => r.id),
          ['r-mine-1', 'r-untagged', 'r-mine-2']);
    });

    test('empty-string tag is treated as untagged (defensive)', () {
      final filtered = filterRunsForCurrentUser(
        [
          // metadata is non-null but the value is empty.
          makeRun('r-1', metadata: {'created_by_user_id': ''}),
        ],
        'user-a',
      );
      // Empty string falls through the type check; treated as
      // adoptable rather than rejected.
      expect(filtered.map((r) => r.id), ['r-1']);
    });

    test('non-string tag (corrupt) is treated as untagged', () {
      final filtered = filterRunsForCurrentUser(
        [
          makeRun('r-1', metadata: {'created_by_user_id': 42}),
        ],
        'user-a',
      );
      // The `owner is! String` check makes the run adoptable
      // rather than crashing — a corrupt metadata key shouldn't
      // block sync.
      expect(filtered.map((r) => r.id), ['r-1']);
    });

    test('preserves order of incoming runs', () {
      // The SyncService relies on input order for newest-first
      // pushes; the filter must not re-order.
      final inputs = [
        for (var i = 0; i < 10; i++) makeOwnedRun('r-$i', 'user-a'),
      ];
      final filtered = filterRunsForCurrentUser(inputs, 'user-a');
      expect(filtered.map((r) => r.id),
          ['r-0', 'r-1', 'r-2', 'r-3', 'r-4', 'r-5', 'r-6', 'r-7', 'r-8', 'r-9']);
    });

    test('100 mixed-owner runs: only the current user\'s 33 pass', () {
      final inputs = [
        for (var i = 0; i < 100; i++)
          makeOwnedRun('r-$i',
              i % 3 == 0 ? 'user-a' : (i % 3 == 1 ? 'user-b' : 'user-c')),
      ];
      final filtered = filterRunsForCurrentUser(inputs, 'user-b');
      // i % 3 == 1 → indices 1, 4, 7, …, 97 = 33 entries.
      expect(filtered, hasLength(33));
      for (final r in filtered) {
        expect(r.metadata!['created_by_user_id'], 'user-b');
      }
    });
  });

  // ────────────────────────────────────────────────────────────────
  // End-to-end: the owner-tag filter actually gates what gets
  // pushed via saveRunsBatch.
  group('SyncService — owner-tag drain integration', () {
    test('signed in as user-b, store has runs owned by user-a → batch '
        'push is NOT called', () async {
      // Pre-seed the store with user-a's runs.
      await store.save(_runForOwner('r-a-1', 'user-a'));
      await store.save(_runForOwner('r-a-2', 'user-a'));

      final api = _FakeApiClient()..fakeUserId = 'user-b';
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 0,
          reason: 'all unsynced runs are owned by user-a; user-b drain '
              'must SKIP — never invoke saveRunsBatch with foreign runs');
      // Runs stay in the unsynced queue.
      expect(store.unsyncedCount, 2);
    });

    test('signed in as user-a, mix of user-a + user-b runs → only '
        'user-a runs are pushed', () async {
      await store.save(_runForOwner('r-a-1', 'user-a'));
      await store.save(_runForOwner('r-b-1', 'user-b'));
      await store.save(_runForOwner('r-a-2', 'user-a'));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      // The batch carries only the user-a runs.
      expect(api.savedBatchIds.single.toSet(), {'r-a-1', 'r-a-2'});
      // After success: user-a runs synced; user-b's stays unsynced.
      expect(store.unsyncedRuns.map((r) => r.id).toSet(), {'r-b-1'});
    });

    test('signed in as user-a, ALL runs untagged → all push (legacy '
        'adoption)', () async {
      // Legacy runs in the queue (recorded before owner-tagging
      // shipped, or recorded signed-out) adopt to the current
      // user.
      await store.save(makeRun('r-1'));
      await store.save(makeRun('r-2'));

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.single.toSet(), {'r-1', 'r-2'});
    });

    test('signed in as user-a, all foreign runs → still drains pending '
        'deletes (the queues are independent)', () async {
      await store.save(_runForOwner('r-foreign', 'user-b'));
      // Also queue a pending delete (e.g. user-a deleted r-deleted
      // while offline).
      await store.markPendingRemoteDelete('r-deleted');

      final api = _FakeApiClient()..fakeUserId = 'user-a';
      final svc = SyncService(apiClient: api, runStore: store);

      await svc.debugTrySync('test');

      // Foreign runs skipped — no batch push.
      expect(api.saveBatchCallCount, 0);
      // BUT pending deletes still drain — they're independent.
      expect(api.deleteCallCount, 1);
      expect(api.deletedIds, ['r-deleted']);
    });

    test('signed in offline-saved runs adopt + push successfully',
        () async {
      // The "record without an account → sign in → push" headline
      // flow. The store records the run with no provider (signed
      // out at the time), the user signs in, SyncService picks
      // up the queue and adopts the untagged runs to the current
      // user.
      await store.save(makeRun('r-offline-1'));
      await store.save(makeRun('r-offline-2'));
      expect(store.unsyncedCount, 2);

      // User signs in.
      final api = _FakeApiClient()..fakeUserId = 'user-fresh';
      final svc = SyncService(apiClient: api, runStore: store);
      await svc.debugTrySync('test');

      // Both adopt + push.
      expect(api.saveBatchCallCount, 1);
      expect(api.savedBatchIds.single.toSet(),
          {'r-offline-1', 'r-offline-2'});
      expect(store.unsyncedCount, 0);
    });

    test('signed in as user-b, single user-a run → no push AND no failure '
        '(queue stays put, no backoff)', () async {
      // Skipping foreign runs is NOT a failure — the backoff
      // counter should NOT increment.
      await store.save(_runForOwner('r-a-1', 'user-a'));
      final api = _FakeApiClient()..fakeUserId = 'user-b';
      final svc = SyncService(apiClient: api, runStore: store);

      final beforeFailures = svc.debugBackoffState().failures;
      await svc.debugTrySync('test');
      final afterFailures = svc.debugBackoffState().failures;

      expect(afterFailures, beforeFailures,
          reason: 'skipping foreign runs is a no-op, not a failure — '
              "must not trigger exponential backoff that would slow "
              "down legitimate retries");
    });
  });
}

/// Build a run with a specific owner tag, used by integration tests
/// in this file. (The store's own save() stamps via the provider —
/// these tests bypass the store's save() to construct runs directly.)
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
