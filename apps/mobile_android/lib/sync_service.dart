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
    int pushed = 0;
    for (final run in unsynced) {
      try {
        await api.saveRun(run);
        await runStore.markSynced(run.id);
        pushed++;
      } catch (e) {
        debugPrint('SyncService: failed to push ${run.id}: $e');
      }
    }
    debugPrint('SyncService: pushed $pushed/${unsynced.length}');
    _syncing = false;
  }
}
