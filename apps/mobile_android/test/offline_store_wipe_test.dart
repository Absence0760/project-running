import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:core_models/core_models.dart';

import '../lib/local_run_store.dart';
import '../lib/offline_store_wipe.dart';
import 'source_scan.dart';

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
  group('the in-progress recording snapshot', () {
    // `in_progress.json` is the only file in the run store with no owner tag.
    // Recovery runs at cold start and stamps whatever it finds with whoever is
    // signed in THEN (§67), so a partial A left behind is promoted into B's
    // list, and pushed to B's account, as B's own run.
    Run partial() => Run(
          id: 'partial-1',
          startedAt: DateTime.utc(2026, 5, 1, 6),
          duration: const Duration(minutes: 12),
          distanceMetres: 2400,
          source: RunSource.app,
          track: const [
            Waypoint(lat: 51.5007, lng: -0.1246),
            Waypoint(lat: 51.5010, lng: -0.1250),
          ],
        );

    test('does not survive sign-out', () async {
      final dir = Directory.systemTemp.createTempSync('in_progress_wipe');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = LocalRunStore();
      await store.init(overrideDirectory: dir);
      await store.saveInProgress(partial());
      expect(File('${dir.path}/in_progress.json').existsSync(), isTrue,
          reason: 'the precondition this test exists for must hold');

      await wipeInProgressRecording(store);

      expect(File('${dir.path}/in_progress.json').existsSync(), isFalse,
          reason: "a stranger's GPS trace must not be left for the next "
              'account to adopt');
      expect(await store.loadInProgress(), isNull);
    });

    test('is idempotent when there is nothing to wipe', () async {
      final dir = Directory.systemTemp.createTempSync('in_progress_wipe_none');
      addTearDown(() => dir.deleteSync(recursive: true));
      final store = LocalRunStore();
      await store.init(overrideDirectory: dir);

      await expectLater(wipeInProgressRecording(store), completes);
    });

    test('a failure is isolated, like every other store wipe', () async {
      // Sign-out fires this alongside four other wipes; one throwing must not
      // strand the rest, and must not throw into the auth listener.
      final store = LocalRunStore();
      await expectLater(wipeInProgressRecording(store), completes);
    });

    test('sign-out actually calls it', () async {
      // The behaviour above is worth nothing if the auth listener does not
      // reach it. main.dart's signedOut branch is not mountable from a test,
      // so this reads it.
      final main = File('lib/main.dart').readAsStringSync();
      final code = blankNonCode(main);
      final at = code.indexOf('AuthChangeEvent.signedOut');
      expect(at, greaterThan(0),
          reason: 'the signedOut branch has moved — retarget this guard');
      expect(code.substring(at).contains('wipeInProgressRecording('), isTrue,
          reason: 'sign-out wipes every other local store but leaves the '
              "in-progress recording for the next account to adopt");
    });
  });

}
