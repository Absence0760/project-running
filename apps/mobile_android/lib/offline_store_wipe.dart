import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_crossings_store.dart';
import 'local_run_store.dart';
import 'local_meal_template_store.dart';
import 'local_recipe_store.dart';
import 'local_routine_store.dart';
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

/// Drop the crash-recovery snapshot of a run in progress.
///
/// The one artifact the per-row wipe above cannot reach, and the only file in
/// the run store that carries no owner tag. Recovery runs at COLD START,
/// after `currentUserIdProvider` is wired, and stamps whatever it finds with
/// whoever is signed in at that moment (§67). So a partial left behind by A —
/// app force-killed mid-run, A signs out, B signs in, next cold start — is
/// promoted into B's list as B's own run and pushed to B's account, GPS trace
/// and all. Sign-out is the boundary where nothing of the prior user may
/// survive, and this file was the exemption.
///
/// Clearing it costs at most the tail of a recording that was live at
/// sign-out: the run screen re-writes the snapshot on its next incremental
/// tick, and `_stop` saves from memory rather than from this file.
Future<void> wipeInProgressRecording(LocalRunStore store) async {
  try {
    await store.clearInProgress();
  } catch (e) {
    debugPrint('In-progress recording wipe on signedOut failed: $e');
  }
}
