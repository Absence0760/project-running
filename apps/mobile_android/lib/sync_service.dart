import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'local_run_store.dart';

/// Pushes unsynced runs to the backend whenever:
///
/// 1. Connectivity changes from offline to online (e.g. wifi reconnects)
/// 2. The app comes back to the foreground
/// 3. The user is signed in and there are unsynced runs
///
/// Sync attempts are silent and best-effort — failures are logged but don't
/// surface to the UI. The user can still trigger an explicit sync from the
/// Runs screen.
class SyncService with WidgetsBindingObserver {
  final ApiClient? apiClient;
  final LocalRunStore runStore;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _syncing = false;

  SyncService({required this.apiClient, required this.runStore});

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _connectivitySub = Connectivity().onConnectivityChanged.listen(_onConnectivity);
    // Initial attempt in case we're already online with pending runs.
    _trySync('startup');
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _trySync('foreground');
    }
  }

  void _onConnectivity(List<ConnectivityResult> results) {
    final online = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet);
    if (online) _trySync('connectivity');
  }

  /// Test-only: drives the same code path the connectivity / lifecycle
  /// observers do. Lets unit tests exercise the sync loop without the
  /// `WidgetsBindingObserver` subscription.
  @visibleForTesting
  Future<void> debugTrySync(String reason) => _trySync(reason);

  Future<void> _trySync(String reason) async {
    if (_syncing) return;
    final api = apiClient;
    if (api == null || api.userId == null) return;
    final unsynced = runStore.unsyncedRuns;
    final hasPendingDeletes = runStore.pendingRemoteDeleteIds.isNotEmpty;
    if (unsynced.isEmpty && !hasPendingDeletes) return;

    _syncing = true;
    try {
      if (unsynced.isNotEmpty) {
        debugPrint('SyncService: pushing ${unsynced.length} runs ($reason)');
        try {
          // saveRunsBatch uploads tracks 8-in-parallel and upserts rows in
          // chunks of 100. Used to be a serial per-run saveRun call with
          // per-run markSynced rewrite — an order of magnitude more
          // round-trips on a user with many offline runs.
          await api.saveRunsBatch(unsynced);
          await runStore.markManySynced(unsynced.map((r) => r.id));
          debugPrint('SyncService: pushed ${unsynced.length}');
        } catch (e) {
          debugPrint('SyncService: batch push failed ($reason): $e');
        }
      }
      if (hasPendingDeletes) {
        await _drainPendingDeletes(reason);
      }
    } finally {
      _syncing = false;
    }
  }

  /// Retry remote-side deletes that failed on first attempt (e.g. the
  /// user batch-deleted runs while offline). Each id is attempted
  /// independently so one persistent failure (e.g. an RLS rejection
  /// on a malformed id) doesn't poison the rest of the queue. On
  /// success the local copy is also removed — runs_screen kept it
  /// around precisely so the local list stayed consistent with the
  /// cloud, and now that the cloud row is gone the local row should
  /// follow.
  Future<void> _drainPendingDeletes(String reason) async {
    final api = apiClient;
    if (api == null) return;
    final ids = runStore.pendingRemoteDeleteIds.toList();
    if (ids.isEmpty) return;
    debugPrint(
      'SyncService: retrying ${ids.length} pending remote deletes ($reason)',
    );
    var ok = 0;
    for (final id in ids) {
      try {
        await api.deleteRunById(id);
        await runStore.delete(id);
        await runStore.clearPendingRemoteDelete(id);
        ok++;
      } catch (e) {
        debugPrint('SyncService: retry delete failed for $id: $e');
      }
    }
    debugPrint('SyncService: drained $ok / ${ids.length} pending deletes');
  }
}
