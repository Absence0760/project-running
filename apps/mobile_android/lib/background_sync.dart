import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:workmanager/workmanager.dart';

import 'local_run_store.dart';

const backgroundSyncTaskName = 'com.threkir.backgroundSync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      await dotenv.load(fileName: '.env.local');

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
      final unsynced = store.unsyncedRuns;
      if (unsynced.isEmpty) return true;

      try {
        final failed = await api.saveRunsBatch(unsynced);
        // Mark only the runs that successfully uploaded (matches
        // SyncService — a corrupted track no longer poisons the
        // background sync queue).
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
    } catch (e) {
      debugPrint('Background sync error: $e');
    }
    return true;
  });
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
