import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/offline_store_wipe.dart';

/// Pins the issue #228 fix: sign-out must wipe EVERY OfflineSyncStore-backed
/// local store, including the screen-owned types that main.dart holds no
/// singleton for (routines, meal templates, recipes, checkpoint crossings).
/// Before the fix, a different user signing in on the same device both saw
/// the prior user's rows and adopted them — replaceFromServer
/// preserves pendingCreate rows and syncWithServer pushes them into the new
/// account. The list-completeness half (a NEW subclass must land in a wipe
/// list) is the offline-store guard in architecture_guards_test.dart.
void main() {
  test('registry builds one instance of each screen-owned store type', () {
    final types = buildScreenOwnedOfflineStores()
        .map((s) => s.runtimeType.toString())
        .toList();
    expect(types, [
      'LocalRoutineStore',
      'LocalMealTemplateStore',
      'LocalRecipeStore',
      'LocalCrossingsStore',
    ]);
  });

  test('wipe clears every screen-owned store directory on disk', () async {
    final root = Directory.systemTemp.createTempSync('wipe_test');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory dirFor(String subdir) => Directory('${root.path}/$subdir');

    // Plant a row-shaped file in each store's directory, the way a prior
    // user's unsynced rows would sit there at sign-out.
    for (final store in buildScreenOwnedOfflineStores()) {
      final d = dirFor(store.storeSubdir)..createSync(recursive: true);
      File('${d.path}/prior-user-row.json').writeAsStringSync('{}');
    }

    await wipeScreenOwnedOfflineStores(dirFor: dirFor);

    for (final store in buildScreenOwnedOfflineStores()) {
      final left = dirFor(store.storeSubdir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(left, isEmpty,
          reason: '${store.debugLabel} must not survive sign-out');
    }
  });

  test('a failing store does not strand the rest', () async {
    final root = Directory.systemTemp.createTempSync('wipe_fail_test');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory dirFor(String subdir) => Directory('${root.path}/$subdir');

    for (final store in buildScreenOwnedOfflineStores()) {
      final d = dirFor(store.storeSubdir)..createSync(recursive: true);
      File('${d.path}/prior-user-row.json').writeAsStringSync('{}');
    }

    // The first store's init throws (unreadable path); the others must
    // still be wiped.
    final failingSubdir = buildScreenOwnedOfflineStores().first.storeSubdir;
    Directory failingDirFor(String subdir) => subdir == failingSubdir
        ? (throw const FileSystemException('boom'))
        : dirFor(subdir);

    await wipeScreenOwnedOfflineStores(dirFor: failingDirFor);

    for (final store in buildScreenOwnedOfflineStores().skip(1)) {
      final left = dirFor(store.storeSubdir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();
      expect(left, isEmpty,
          reason: '${store.debugLabel} must be wiped even when an earlier '
              'store failed');
    }
  });

  test('an atomic-write temp orphan does not survive sign-out', () async {
    // writeStringAtomic leaves `<name>.json.<n>.tmp` behind when the process
    // dies between its flush and its rename, and every listing in this layer
    // filters on `.json` — so the orphan was invisible to the store and
    // outlived the wipe still holding a full row (a LocalCrossingsStore one
    // carries a bib number and weigh-in fields).
    final root = Directory.systemTemp.createTempSync('wipe_tmp_test');
    addTearDown(() => root.deleteSync(recursive: true));
    Directory dirFor(String subdir) => Directory('${root.path}/$subdir');

    for (final store in buildScreenOwnedOfflineStores()) {
      final d = dirFor(store.storeSubdir)..createSync(recursive: true);
      File('${d.path}/prior-user-row.json').writeAsStringSync('{}');
      File('${d.path}/prior-user-row.json.0.tmp')
          .writeAsStringSync('{"bib":"1234"}');
    }

    await wipeScreenOwnedOfflineStores(dirFor: dirFor);

    for (final store in buildScreenOwnedOfflineStores()) {
      expect(dirFor(store.storeSubdir).listSync().whereType<File>(), isEmpty,
          reason: 'nothing of ${store.debugLabel} may survive sign-out');
    }
  });
}
