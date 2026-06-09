import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

import 'local_run_store.dart';
import 'sync_service.dart' show filterRunsForCurrentUser;

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
      await runBackgroundSyncCycle(api, store);
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
    return true;
  });
}

/// Push the local unsynced queue to the cloud from the WorkManager
/// callback. Extracted from [callbackDispatcher] so it can be unit-
/// tested without the WorkManager + dotenv + Supabase bootstrap.
///
/// **Always** routes the queue through [filterRunsForCurrentUser] so
/// the background path honours the same owner-tag guard the foreground
/// [SyncService] does. Without this, on a shared device, User A's
/// unsynced runs would get pushed under User B's account the next
/// time WorkManager fires while B is signed in — every row would land
/// under the wrong user and RLS would silently accept them (the row
/// embeds the caller's `user_id`, not the run's tagged owner). The
/// guard mirrors `SyncService._trySync`'s owner-tag filter so a fresh
/// WorkManager job behaves identically to a foreground sync.
Future<void> runBackgroundSyncCycle(
  ApiClient api,
  LocalRunStore store,
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
  if (unsynced.isEmpty) return;
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

void registerBackgroundSync() {
  Workmanager().initialize(callbackDispatcher);
  Workmanager().registerPeriodicTask(
    backgroundSyncTaskName,
    backgroundSyncTaskName,
    constraints: Constraints(networkType: NetworkType.connected),
    frequency: const Duration(hours: 1),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
