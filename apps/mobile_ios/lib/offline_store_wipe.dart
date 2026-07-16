import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_crossings_store.dart';
import 'local_meal_template_store.dart';
import 'local_recipe_store.dart';
import 'local_routine_store.dart';
import 'local_session_store.dart';
import 'offline_sync_store.dart';

/// Fresh instances of every SCREEN-OWNED [OfflineSyncStore] type, for the
/// sign-out wipe. These stores are constructed per-screen rather than
/// injected from main, so the auth listener has no live instance to
/// clear — but all instances of a type share one on-disk directory, so a
/// throwaway instance can wipe it. The app-singleton stores (gear, gym,
/// food) are cleared directly in main.dart; a new OfflineSyncStore
/// subclass must land in one list or the other, enforced by the
/// offline-store guard in architecture_guards_test.dart.
List<OfflineSyncStore> buildScreenOwnedOfflineStores() => [
      LocalRoutineStore(),
      LocalMealTemplateStore(),
      LocalRecipeStore(),
      LocalCrossingsStore(),
      LocalSessionStore(),
    ];

/// Init-then-clear each store, isolating per-store failures so one
/// undeletable directory can't strand the rest (the crossings store can
/// carry bibs + WEIGH_IN_GATE medical fields — it must not survive a
/// failure in an unrelated store's wipe). [dirFor] is a test seam
/// standing in for the app documents directory.
Future<void> wipeScreenOwnedOfflineStores({
  Directory Function(String storeSubdir)? dirFor,
}) async {
  for (final store in buildScreenOwnedOfflineStores()) {
    try {
      await store.init(overrideDirectory: dirFor?.call(store.storeSubdir));
      await store.clear();
    } catch (e) {
      debugPrint('Offline store wipe on signedOut failed '
          '(${store.debugLabel}): $e');
    }
  }
}
