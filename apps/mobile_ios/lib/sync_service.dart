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

  Future<void> _trySync(String reason) async {
    if (_syncing) return;
    final api = apiClient;
    if (api == null || api.userId == null) return;
    final unsynced = runStore.unsyncedRuns;
    if (unsynced.isEmpty) return;

    _syncing = true;
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
    } finally {
      _syncing = false;
    }
  }
}
