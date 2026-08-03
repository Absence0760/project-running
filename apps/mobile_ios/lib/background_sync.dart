import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

import 'local_route_store.dart';
import 'local_run_store.dart';
import 'sync_service.dart'
    show drainPendingDeletes, drainUnsyncedRoutes, filterRunsForCurrentUser;

const backgroundSyncTaskName = 'com.threkir.backgroundSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env.development');

      final supabaseUrl = dotenv.env['SUPABASE_URL'];
      final anonKey = dotenv.env['SUPABASE_ANON_KEY'];
      if (supabaseUrl == null ||
          supabaseUrl.isEmpty ||
          anonKey == null ||
          anonKey.isEmpty) {
        return true;
      }

      await ApiClient.initialize(url: supabaseUrl, anonKey: anonKey);
      final api = ApiClient();
      if (api.userId == null) return true;

      final store = LocalRunStore();
      await store.init();
      final routeStore = LocalRouteStore();
      await routeStore.init();
      await runBackgroundSyncCycle(api, store, routeStore);
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
    return true;
  });
}

/// Drain the local queues to the cloud from the WorkManager callback:
/// unsynced runs, pending remote-deletes, and unsynced routes — the
/// same three queues the foreground [SyncService] drains every cycle.
/// Extracted from [callbackDispatcher] so it can be unit-tested without
/// the WorkManager + dotenv + Supabase bootstrap.
///
/// The delete + route drains reuse the shared [drainPendingDeletes] /
/// [drainUnsyncedRoutes] free functions so the background path can't
/// drift from the foreground one. Each queue is wrapped in its own
/// try/catch (layered resilience) so a failure draining one queue
/// doesn't abort the others.
///
/// **Always** routes the run queue through [filterRunsForCurrentUser]
/// so the background path honours the same owner-tag guard the
/// foreground [SyncService] does. Without this, on a shared device,
/// User A's unsynced runs would get pushed under User B's account the
/// next time WorkManager fires while B is signed in — every row would
/// land under the wrong user and RLS would silently accept them (the
/// row embeds the caller's `user_id`, not the run's tagged owner).
Future<void> runBackgroundSyncCycle(
  ApiClient api,
  LocalRunStore store,
  LocalRouteStore routeStore,
) async {
  final allUnsynced = store.unsyncedRuns;
  final unsynced = filterRunsForCurrentUser(allUnsynced, api.userId);
  final skippedForeignOwner = allUnsynced.length - unsynced.length;
  if (skippedForeignOwner > 0) {
    debugPrint(
      'Background sync: skipping $skippedForeignOwner runs owned by a '
      'different user (signed in as ${api.userId})',
    );
  }
  if (unsynced.isNotEmpty) {
    try {
      final failed = await api.saveRunsBatch(unsynced);
      await store.markManySynced(
        unsynced.where((r) => !failed.contains(r.id)).map((r) => r.id),
      );
      debugPrint(
        'Background sync: pushed ${unsynced.length - failed.length} '
        '(skipped ${failed.length} on track-upload failure)',
      );
    } catch (e) {
      debugPrint('Background sync batch failed: $e');
    }
  }
  try {
    await drainPendingDeletes(api, store);
  } catch (e) {
    debugPrint('Background sync delete drain failed: $e');
  }
  try {
    await drainUnsyncedRoutes(api, routeStore);
  } catch (e) {
    debugPrint('Background sync route drain failed: $e');
  }
}

/// Arm the background drain. Neither platform promises the task ever runs —
/// the foreground [SyncService] stays the primary drain and this is purely
/// opportunistic.
///
/// iOS and Android take different task types because iOS gates each type on
/// a matching `UIBackgroundModes` entry. A BGAppRefreshTask (what
/// `registerPeriodicTask` submits on iOS) needs the `fetch` capability and
/// gets ~30 s; draining a weekend of unsynced runs means uploading several
/// gzipped GPS tracks, which overruns that and ignores the network
/// constraint BGAppRefreshTaskRequest has no field for. A BGProcessingTask
/// gets minutes, honours [Constraints.networkType] via
/// `requiresNetworkConnectivity`, and runs while the device is idle — which
/// is what a fully deferrable queue drain wants. It is also the capability
/// the app already declares, so this needs no extra `UIBackgroundModes`
/// entry. iOS delivers it at most once per submission, so it is re-armed on
/// each launch; Android's periodic job re-fires on its own.
void registerBackgroundSync() {
  Workmanager().initialize(callbackDispatcher);
  final registered = Platform.isIOS
      ? Workmanager().registerProcessingTask(
          backgroundSyncTaskName,
          backgroundSyncTaskName,
          constraints: Constraints(networkType: NetworkType.connected),
        )
      : Workmanager().registerPeriodicTask(
          backgroundSyncTaskName,
          backgroundSyncTaskName,
          constraints: Constraints(networkType: NetworkType.connected),
          frequency: const Duration(hours: 1),
          existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        );
  registered.catchError((Object e) {
    debugPrint('Background sync registration failed: $e');
  });
}
