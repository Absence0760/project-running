import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/local_route_store.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory _root;
  _FakePathProvider(this._root);
  @override
  Future<String?> getApplicationDocumentsPath() async => _root.path;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('local_route_store_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Route makeRoute({
    String id = 'route-1',
    String name = 'Park loop',
    double distance = 5000,
    bool isPublic = false,
    bool isStarred = false,
  }) {
    return Route(
      id: id,
      userId: 'test-user',
      name: name,
      waypoints: const [
        Waypoint(lat: 47.37, lng: 8.54),
        Waypoint(lat: 47.371, lng: 8.541),
      ],
      distanceMetres: distance,
      isPublic: isPublic,
      isStarred: isStarred,
    );
  }

  group('init', () {
    test('creates the routes directory if it does not exist', () async {
      final nested = Directory('${tempDir.path}/nonexistent_routes');
      expect(nested.existsSync(), isFalse);

      final store = LocalRouteStore();
      await store.init(overrideDirectory: nested);

      expect(nested.existsSync(), isTrue);
      expect(store.routes, isEmpty);
    });

    test('returns empty when directory has no .json files', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.routes, isEmpty);
    });

    test('ignores non-.json files in the directory', () async {
      File('${tempDir.path}/notes.txt').writeAsStringSync('hi');
      File('${tempDir.path}/data.bin').writeAsBytesSync([1, 2, 3]);

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.routes, isEmpty);
    });

    test('skips a corrupt .json file instead of crashing', () async {
      File('${tempDir.path}/corrupt.json').writeAsStringSync('{not valid');
      final goodRoute = makeRoute(id: 'route-good');
      File('${tempDir.path}/${goodRoute.id}.json')
          .writeAsStringSync(jsonEncode(goodRoute.toJson()));

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.routes, hasLength(1));
      expect(store.routes.first.id, 'route-good');
    });

    test('does not load the synced/pinned sidecars as routes', () async {
      final s1 = LocalRouteStore();
      await s1.init(overrideDirectory: tempDir);
      await s1.save(makeRoute(id: 'r-1'), markSynced: true);
      await s1.pinOffline('r-1');

      // Both sidecars now exist as {_v, ids:[...]} JSON Maps that match the
      // `*.json` directory glob. _loadAll must exclude them by filename so
      // they don't get fed to Route.fromJson.
      expect(File('${tempDir.path}/synced_route_ids.json').existsSync(), isTrue);
      expect(
          File('${tempDir.path}/offline_pinned_route_ids.json').existsSync(),
          isTrue);

      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);

      expect(s2.routes, hasLength(1));
      expect(s2.routes.single.id, 'r-1');
      expect(s2.unsyncedRoutes, isEmpty);
      expect(s2.isOfflinePinned('r-1'), isTrue);
    });

    // The absent-file branch defaults every route to SYNCED so an upgrade
    // doesn't re-push the library. An unreadable sidecar used to fail the other
    // way — empty set means "all unsynced", so drainUnsyncedRoutes pushes the
    // whole library and tagRoutesOwner then stamps every route as the CURRENT
    // user. On a shared device with untagged routes that copies user A's
    // library into user B's account.
    for (final corrupt in const <String, String>{
      'truncated JSON': '{"ids": ["r-1"',
      'zero bytes': '',
      'wrong shape': '{"ids": {"r-1": true}}',
      'a bare list': '["r-1","r-2"]',
      'not JSON at all': 'not json',
    }.entries)
      test('a ${corrupt.key} synced sidecar fails closed to presumed-synced',
          () async {
        final s1 = LocalRouteStore();
        await s1.init(overrideDirectory: tempDir);
        await s1.save(makeRoute(id: 'r-1'), markSynced: true);
        await s1.save(makeRoute(id: 'r-2'), markSynced: true);

        File('${tempDir.path}/synced_route_ids.json')
            .writeAsStringSync(corrupt.value);

        final s2 = LocalRouteStore();
        await s2.init(overrideDirectory: tempDir);

        expect(s2.routes, hasLength(2));
        expect(s2.unsyncedRoutes, isEmpty,
            reason: 'a damaged sidecar must not re-push + re-own the library');
        expect(s2.unsyncedCount, 0);
      });

    test('a valid sidecar still reports genuinely unsynced routes', () async {
      // Guards the fail-closed default from swallowing real unsynced work.
      final s1 = LocalRouteStore();
      await s1.init(overrideDirectory: tempDir);
      await s1.save(makeRoute(id: 'r-synced'), markSynced: true);
      await s1.save(makeRoute(id: 'r-pending'));

      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);

      expect(s2.unsyncedRoutes.map((r) => r.id), ['r-pending']);
    });
  });

  group('save', () {
    test('writes the route to a {id}.json file', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-42'));

      final file = File('${tempDir.path}/r-42.json');
      expect(file.existsSync(), isTrue);
      final raw = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      expect(raw['id'], 'r-42');
      expect(raw['name'], 'Park loop');
    });

    test('round-trips through a fresh store instance', () async {
      final s1 = LocalRouteStore();
      await s1.init(overrideDirectory: tempDir);
      await s1.save(makeRoute(
        id: 'r-1',
        name: 'Riverside',
        distance: 7421,
        isPublic: true,
        isStarred: true,
      ));

      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);

      expect(s2.routes, hasLength(1));
      final loaded = s2.routes.single;
      expect(loaded.id, 'r-1');
      expect(loaded.name, 'Riverside');
      expect(loaded.distanceMetres, 7421);
      expect(loaded.isPublic, isTrue);
      expect(loaded.isStarred, isTrue);
      expect(loaded.waypoints, hasLength(2));
      expect(loaded.waypoints.first.lat, 47.37);
    });

    test('saving the same id twice replaces — does not duplicate', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1', name: 'v1'));
      await store.save(makeRoute(id: 'r-1', name: 'v2'));

      expect(store.routes, hasLength(1));
      expect(store.routes.single.name, 'v2');
    });

    test('inserts the saved route at index 0 (newest-first)', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-old'));
      await store.save(makeRoute(id: 'r-new'));

      expect(store.routes.map((r) => r.id), ['r-new', 'r-old']);
    });

    test('notifies listeners exactly once per save', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.save(makeRoute(id: 'r-1'));
      expect(calls, 1);
      await store.save(makeRoute(id: 'r-2'));
      expect(calls, 2);
    });
  });

  group('saveBatch', () {
    test('writes every file and notifies once for the batch', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.saveBatch([
        makeRoute(id: 'a'),
        makeRoute(id: 'b'),
        makeRoute(id: 'c'),
      ]);

      expect(calls, 1);
      expect(store.routes.map((r) => r.id), ['c', 'b', 'a']);
      for (final id in ['a', 'b', 'c']) {
        expect(File('${tempDir.path}/$id.json').existsSync(), isTrue);
      }
    });

    test('empty iterable is a no-op (does not notify)', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.saveBatch(const []);

      expect(calls, 0);
      expect(store.routes, isEmpty);
    });

    test('overlapping ids replace existing entries (no duplicates)', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      // r-1 starts synced (server ingest) so the overwrite path is exercised
      // — saveBatch only preserves UNsynced local edits.
      await store.saveBatch([makeRoute(id: 'r-1', name: 'v1')]);
      await store.saveBatch([
        makeRoute(id: 'r-1', name: 'v2'),
        makeRoute(id: 'r-2'),
      ]);

      expect(store.routes, hasLength(2));
      expect(store.routes.firstWhere((r) => r.id == 'r-1').name, 'v2');
    });

    test('server ingest preserves an unsynced local edit (newer-wins)',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      // Local-only edit: save() marks the route unsynced (pending push).
      await store.save(makeRoute(id: 'r-1', name: 'My offline edit'));
      expect(store.unsyncedRoutes.map((r) => r.id), contains('r-1'));

      // A server pull returns an older copy of the same id. It must NOT
      // clobber the pending local edit or flag it synced.
      await store.saveBatch([makeRoute(id: 'r-1', name: 'Server stale copy')]);

      expect(store.routes.single.name, 'My offline edit');
      expect(store.unsyncedRoutes.map((r) => r.id), contains('r-1'),
          reason: 'the pending push must survive the server ingest');
    });

    test('server ingest overwrites a synced local route', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveBatch([makeRoute(id: 'r-1', name: 'v1')]); // synced
      expect(store.unsyncedRoutes, isEmpty);

      await store.saveBatch([makeRoute(id: 'r-1', name: 'v2')]);

      expect(store.routes.single.name, 'v2',
          reason: 'a clean (synced) route takes the server copy');
    });
  });

  group('schema version (_v)', () {
    test('a saved route file carries the current schema version', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-v'));
      final raw = jsonDecode(File('${tempDir.path}/r-v.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(raw[kLocalStoreVersionKey], kLocalStoreSchemaVersion);
      // The route fields remain top-level — Route.fromJson ignores `_v`.
      expect(raw['id'], 'r-v');
    });

    test('a legacy (bare, unstamped) route file still loads', () async {
      // v0 shape: a bare Route.toJson() with no _v key.
      final legacy = makeRoute(id: 'legacy', name: 'Old route');
      File('${tempDir.path}/legacy.json')
          .writeAsStringSync(jsonEncode(legacy.toJson()));

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.routes.any((r) => r.id == 'legacy'), isTrue);
      expect(store.routes.single.name, 'Old route');
    });
  });

  group('delete', () {
    test('removes the file from disk and from in-memory list', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1'));
      expect(File('${tempDir.path}/r-1.json').existsSync(), isTrue);

      await store.delete('r-1');

      expect(File('${tempDir.path}/r-1.json').existsSync(), isFalse);
      expect(store.routes, isEmpty);
    });

    test('deleting an unknown id is a no-op (no exception, still notifies)',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.delete('not-a-real-id');

      expect(calls, 1);
      expect(store.routes, isEmpty);
    });

    test('only deletes the requested id, leaves others intact', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'keep-1'));
      await store.save(makeRoute(id: 'kill'));
      await store.save(makeRoute(id: 'keep-2'));

      await store.delete('kill');

      expect(store.routes.map((r) => r.id).toSet(), {'keep-1', 'keep-2'});
      expect(File('${tempDir.path}/kill.json').existsSync(), isFalse);
      expect(File('${tempDir.path}/keep-1.json').existsSync(), isTrue);
    });
  });

  group('deleteMany', () {
    test('removes every file from disk and from the in-memory list',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'a'));
      await store.save(makeRoute(id: 'b'));
      await store.save(makeRoute(id: 'c'));

      await store.deleteMany({'a', 'c'});

      expect(store.routes.map((r) => r.id).toList(), ['b']);
      expect(File('${tempDir.path}/a.json').existsSync(), isFalse);
      expect(File('${tempDir.path}/b.json').existsSync(), isTrue);
      expect(File('${tempDir.path}/c.json').existsSync(), isFalse);
    });

    test('coalesces into a single notify call — no per-row flicker',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'a'));
      await store.save(makeRoute(id: 'b'));
      await store.save(makeRoute(id: 'c'));
      var calls = 0;
      store.addListener(() => calls++);

      await store.deleteMany({'a', 'b', 'c'});

      expect(calls, 1,
          reason:
              'deleteMany must batch notifications so the list does not flicker through N intermediate states.');
    });

    test('empty input is a no-op (no notify, no file work)', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'a'));
      var calls = 0;
      store.addListener(() => calls++);

      await store.deleteMany(const <String>{});

      expect(calls, 0);
      expect(store.routes.map((r) => r.id).toList(), ['a']);
    });

    test('idempotent on already-deleted ids', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'a'));

      await store.deleteMany({'never-existed', 'a'});

      expect(store.routes, isEmpty);
      expect(File('${tempDir.path}/a.json').existsSync(), isFalse);
    });
  });

  group('routes getter', () {
    test('returns an unmodifiable view — caller cannot mutate internal list',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1'));

      expect(() => store.routes.add(makeRoute(id: 'sneak')),
          throwsUnsupportedError);
    });
  });

  group('offline pin', () {
    test('isOfflinePinned defaults to false for any id', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.isOfflinePinned('any'), isFalse);
      expect(store.offlinePinnedIds, isEmpty);
      expect(store.offlinePinnedRoutes, isEmpty);
    });

    test('pinOffline flips the flag and notifies once', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.pinOffline('r-1');

      expect(store.isOfflinePinned('r-1'), isTrue);
      expect(store.offlinePinnedIds, {'r-1'});
      expect(calls, 1);
    });

    test('pinOffline is idempotent — re-pinning is a no-op', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      await store.pinOffline('r-1');
      await store.pinOffline('r-1');
      await store.pinOffline('r-1');

      expect(calls, 1);
      expect(store.offlinePinnedIds, {'r-1'});
    });

    test('unpinOffline only fires when the id was pinned', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var calls = 0;
      store.addListener(() => calls++);

      // Unknown id — no-op.
      await store.unpinOffline('never-pinned');
      expect(calls, 0);

      await store.pinOffline('r-1');
      expect(calls, 1);

      await store.unpinOffline('r-1');
      expect(calls, 2);
      expect(store.isOfflinePinned('r-1'), isFalse);
    });

    test('pin state round-trips through a fresh store', () async {
      final s1 = LocalRouteStore();
      await s1.init(overrideDirectory: tempDir);
      await s1.save(makeRoute(id: 'r-1'));
      await s1.save(makeRoute(id: 'r-2'));
      await s1.pinOffline('r-1');

      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);

      expect(s2.isOfflinePinned('r-1'), isTrue);
      expect(s2.isOfflinePinned('r-2'), isFalse);
      expect(s2.offlinePinnedRoutes.single.id, 'r-1');
    });

    test('deleting a pinned route also clears the pin', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1'));
      await store.pinOffline('r-1');
      expect(store.isOfflinePinned('r-1'), isTrue);

      await store.delete('r-1');

      expect(store.isOfflinePinned('r-1'), isFalse);
      // Sidecar reflects the removal across a cold start.
      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);
      expect(s2.offlinePinnedIds, isEmpty);
    });

    test('offlinePinnedIds is unmodifiable', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.pinOffline('r-1');
      expect(() => store.offlinePinnedIds.add('sneak'),
          throwsUnsupportedError);
    });

    test('offlinePinnedRoutes is unmodifiable', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1'));
      await store.pinOffline('r-1');
      expect(() => store.offlinePinnedRoutes.add(makeRoute(id: 'sneak')),
          throwsUnsupportedError);
    });

    test('pin is independent of save/markSynced — local-only flag', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      // Pin a route that doesn't exist yet — flag stands, route absent.
      await store.pinOffline('r-future');
      expect(store.isOfflinePinned('r-future'), isTrue);
      expect(store.offlinePinnedRoutes, isEmpty);

      // Add the route — it now shows up in offlinePinnedRoutes.
      await store.save(makeRoute(id: 'r-future'));
      expect(store.offlinePinnedRoutes.single.id, 'r-future');
    });

    test('pin survives saveBatch overwrite of the same id', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.saveBatch([makeRoute(id: 'r-1', name: 'v1')]); // synced
      await store.pinOffline('r-1');

      // Fresh server pull overwrites the same (synced) id with a newer name.
      // The pin must survive — it's per-device, not per-row-version.
      await store.saveBatch([makeRoute(id: 'r-1', name: 'v2')]);

      expect(store.isOfflinePinned('r-1'), isTrue);
      expect(store.routes.single.name, 'v2');
      expect(store.offlinePinnedRoutes.single.name, 'v2');
    });

    test('concurrent pinOffline + unpinOffline serialise correctly', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var notifyCount = 0;
      store.addListener(() => notifyCount++);

      // Fire 10 pin/unpin pairs concurrently for the same id. The
      // sidecar persist runs through writeAsString awaits — these
      // calls must serialise without one clobbering the other or
      // double-notifying for a no-op.
      final futures = <Future<void>>[];
      for (var i = 0; i < 10; i++) {
        futures.add(store.pinOffline('r-x'));
        futures.add(store.unpinOffline('r-x'));
      }
      await Future.wait(futures);

      // Exactly one of the final states wins; either is fine. The
      // contract is that the on-disk sidecar matches in-memory.
      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);
      expect(s2.isOfflinePinned('r-x'), store.isOfflinePinned('r-x'),
          reason: 'sidecar must match the final in-memory state');

      // Notifications fired — at minimum a couple, at most one per
      // state transition (10 each way could collapse into ~10 net
      // events depending on interleaving). Asserting "at least one"
      // is the durable contract; the upper bound is observability.
      expect(notifyCount, greaterThanOrEqualTo(1));
    });

    test('pin tolerates a corrupt sidecar on cold start', () async {
      // Hand-write a broken sidecar then init() — the loader
      // logs + skips it, leaving pinned ids empty rather than
      // crashing the app launch.
      File('${tempDir.path}/offline_pinned_route_ids.json')
          .writeAsStringSync('{this is not json');

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.offlinePinnedIds, isEmpty);
      // And the store is still operable — a fresh pin lands.
      await store.pinOffline('r-1');
      expect(store.isOfflinePinned('r-1'), isTrue);
    });

    test('pin tolerates a sidecar with wrong shape', () async {
      // Valid JSON but the wrong shape — `ids` is not a list. The
      // loader skips the bad entries; no exception.
      File('${tempDir.path}/offline_pinned_route_ids.json')
          .writeAsStringSync('{"ids": "not-a-list"}');

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.offlinePinnedIds, isEmpty);
    });

    test('pin tolerates entries that aren\'t strings', () async {
      // A sidecar that mixed strings + numbers (corruption from a
      // future-format write) shouldn't crash — the loader's `if
      // (id is String)` guard picks just the strings.
      File('${tempDir.path}/offline_pinned_route_ids.json')
          .writeAsStringSync('{"ids": ["r-good", 42, null, "r-also-good"]}');

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(store.offlinePinnedIds, {'r-good', 'r-also-good'});
    });

    test('100 pinned ids round-trip without performance pathology', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      // Populate the store first so the pathology this guards — a pin
      // that rewrites every route record instead of only the pin
      // sidecar — would cost ~10,000 file writes across the loop and
      // blow any bound. The bound itself is deliberately loose: 100
      // sidecar writes are I/O-bound and a loaded shared CI runner has
      // taken 28ms/write (run 29520492396 failed a 2s bound at 2.8s),
      // so a tight wall-clock number flakes on runner speed rather
      // than catching a regression.
      await store.saveBatch(
          [for (var i = 0; i < 100; i++) makeRoute(id: 'r-$i')]);
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await store.pinOffline('r-$i');
      }
      sw.stop();
      expect(store.offlinePinnedIds, hasLength(100));
      expect(sw.elapsedMilliseconds, lessThan(10000),
          reason: '100 sequential pin writes took ${sw.elapsedMilliseconds}ms');

      // Survives cold start with the full set intact.
      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);
      expect(s2.offlinePinnedIds, hasLength(100));
    });
  });

  group('two stores over one directory', () {
    // H2: background_sync.dart builds a second LocalRouteStore over
    // <appDocs>/routes/ in the WorkManager isolate and calls
    // markManyRoutesSynced + tagRoutesOwner. All three sidecars were unlocked
    // whole-file replaces from a per-process snapshot, so the foreground's
    // next save() discarded the background isolate's work.
    test('a background markRouteSynced cannot cost the foreground a re-upload',
        () async {
      final foreground = LocalRouteStore();
      await foreground.init(overrideDirectory: tempDir);
      await foreground.save(makeRoute(id: 'r-fg'));

      final background = LocalRouteStore();
      await background.init(overrideDirectory: tempDir);
      await background.markRouteSynced('r-fg');

      // The foreground's snapshot predates the drain; its own write must not
      // drop r-fg back to unsynced and re-push the whole route.
      await foreground.save(makeRoute(id: 'r-other'), markSynced: true);

      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: tempDir);
      expect(reloaded.unsyncedRoutes, isEmpty);
    });

    test('a background tagRoutesOwner is not reverted to untagged', () async {
      // The unrecoverable direction: an untagged route is visible to — and
      // drainable by — every account on a shared device, so reverting B's
      // adoption tag copies B's route into A's cloud account.
      final foreground = LocalRouteStore();
      await foreground.init(overrideDirectory: tempDir);
      await foreground.save(makeRoute(id: 'r-shared'));

      final background = LocalRouteStore();
      await background.init(overrideDirectory: tempDir);
      await background.tagRoutesOwner(['r-shared'], 'user-b');

      await foreground.save(makeRoute(id: 'r-other'));

      final reloaded = LocalRouteStore();
      reloaded.currentUserIdProvider = () => 'user-a';
      await reloaded.init(overrideDirectory: tempDir);
      expect(reloaded.routes.map((r) => r.id), isNot(contains('r-shared')));
    });

    test('this store\'s own un-sync still sticks through the merge', () async {
      // The merge must not make removal impossible — an edited route has to
      // stay queued for the next drain.
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-1'), markSynced: true);
      await store.save(makeRoute(id: 'r-1', name: 'edited'));

      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: tempDir);
      expect(reloaded.unsyncedRoutes.map((r) => r.id), ['r-1']);
    });

    test('a stale .tmp sibling is swept on cold load, a fresh one is kept',
        () async {
      final stale = File('${tempDir.path}/abc.json.0.tmp')
        ..writeAsStringSync('{}');
      stale.setLastModifiedSync(
          DateTime.now().subtract(const Duration(hours: 3)));
      final fresh = File('${tempDir.path}/def.json.1.tmp')
        ..writeAsStringSync('{}');

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      expect(stale.existsSync(), isFalse);
      expect(fresh.existsSync(), isTrue);
    });

    // Issue #674 added this sidecar after H2 shipped; it started as an
    // unlocked whole-file replace like the other three used to be. Mirrors
    // `LocalRunStore`'s "a background drain cannot wipe a remote-delete
    // queued in the foreground" coverage.
    test('a background drain cannot wipe a route delete queued in the '
        'foreground', () async {
      final foreground = LocalRouteStore();
      await foreground.init(overrideDirectory: tempDir);
      final background = LocalRouteStore();
      await background.init(overrideDirectory: tempDir);

      await foreground.markPendingRemoteDelete('orphan-fg', ownerUserId: 'u1');
      // The background store queues and drains its own delete. Its map is
      // now empty — and an empty map used to delete the whole file.
      await background.markPendingRemoteDelete('orphan-bg', ownerUserId: 'u1');
      await background.clearPendingRemoteDelete('orphan-bg');

      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: tempDir);
      expect(reloaded.pendingRemoteDeleteIds, contains('orphan-fg'),
          reason: 'a queued remote delete is unrecoverable if it is lost');
      expect(reloaded.pendingRemoteDeleteIds, isNot(contains('orphan-bg')),
          reason: 'the background drain\'s own clear must still stick');
    });
  });

  group('lazy init resilience — _ensureDir', () {
    // Reason: an earlier version held `_dir` as a `late Directory`; a
    // save that raced ahead of `init()` (or hit an environment where
    // `init()` had failed silently) threw a confusing
    // `LateInitializationError` and the route stayed unsaved until
    // app relaunch. Field report at the time:
    //   "saved failed error when trying to save my route
    //    'LateInitializationError'"
    // The fix nullable-d `_dir` + added a private `_ensureDir()` that
    // lazily resolves the platform path. These tests pin that
    // contract end-to-end.

    test('save() called BEFORE init() does not throw LateInitializationError',
        () async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      final store = LocalRouteStore();
      // No init() call! save() must auto-init via _ensureDir().
      await store.save(makeRoute(id: 'r-no-init'));

      final routesDir = Directory('${tempDir.path}/routes');
      expect(routesDir.existsSync(), isTrue,
          reason: '_ensureDir should have created the routes subdirectory');
      expect(File('${routesDir.path}/r-no-init.json').existsSync(), isTrue);
      expect(store.routes, hasLength(1));
      expect(store.routes.single.id, 'r-no-init');
    });

    test('saveBatch() called BEFORE init() also auto-initializes', () async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      final store = LocalRouteStore();
      await store.saveBatch([
        makeRoute(id: 'r-1'),
        makeRoute(id: 'r-2'),
      ]);

      final routesDir = Directory('${tempDir.path}/routes');
      expect(routesDir.existsSync(), isTrue);
      expect(File('${routesDir.path}/r-1.json').existsSync(), isTrue);
      expect(File('${routesDir.path}/r-2.json').existsSync(), isTrue);
      expect(store.routes, hasLength(2));
    });

    test('delete() called BEFORE init() does not throw — no-op when file absent',
        () async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      final store = LocalRouteStore();
      await store.delete('nonexistent-id'); // must not throw.
      expect(store.routes, isEmpty);
    });

    test('init() after a lazy save still picks up the on-disk file', () async {
      PathProviderPlatform.instance = _FakePathProvider(tempDir);
      final store = LocalRouteStore();
      await store.save(makeRoute(id: 'r-lazy', name: 'Pre-init save'));

      // Fresh store re-init from the same temp root — proves the lazy
      // save landed in the same directory init() resolves to.
      final routesDir = Directory('${tempDir.path}/routes');
      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: routesDir);
      expect(s2.routes, hasLength(1));
      expect(s2.routes.single.id, 'r-lazy');
      expect(s2.routes.single.name, 'Pre-init save');
    });
  });

  group('owner tags (issue #229 — cross-account leak)', () {
    // The store survives sign-out (like LocalRunStore, §67), so a
    // device-local owner tag is what keeps user A's local library from
    // rendering for — or sync-pushing under — user B.
    test('a route saved under A is invisible (and undrainable) under B',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      String? uid = 'user-a';
      store.currentUserIdProvider = () => uid;

      await store.save(makeRoute(id: 'r-a', name: 'A home loop'));
      expect(store.routes, hasLength(1));
      expect(store.unsyncedRoutes, hasLength(1));

      uid = 'user-b';
      expect(store.routes, isEmpty,
          reason: "user B must not see A's local route library");
      expect(store.unsyncedRoutes, isEmpty,
          reason: "A's unsynced route must not drain into B's account");
      expect(store.offlinePinnedRoutes, isEmpty);

      uid = 'user-a';
      expect(store.routes, hasLength(1),
          reason: 'A signing back in sees their library again');
    });

    test('untagged (pre-upgrade) and signed-out-saved routes stay visible '
        'to any account', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);

      // No provider wired: a signed-out save gets the '' tag.
      await store.save(makeRoute(id: 'r-anon', name: 'Signed-out build'));

      String? uid = 'user-b';
      store.currentUserIdProvider = () => uid;
      expect(store.routes.map((r) => r.id), contains('r-anon'),
          reason: 'the §67 null-owner policy: unowned rows are visible and '
              'adoptable by whoever signs in');
    });

    test('tagRoutesOwner adopts a signed-out route on push and hides it '
        'from other accounts', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.save(makeRoute(id: 'r-adopt'));

      String? uid = 'user-a';
      store.currentUserIdProvider = () => uid;
      await store.tagRoutesOwner(['r-adopt'], 'user-a');
      expect(store.routes, hasLength(1));

      uid = 'user-b';
      expect(store.routes, isEmpty,
          reason: 'once adopted by A the route must stop rendering for B');
    });

    test('owner tags survive a store reload from disk', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRoute(id: 'r-persist'));

      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: tempDir);
      String? uid = 'user-b';
      reloaded.currentUserIdProvider = () => uid;
      expect(reloaded.routes, isEmpty,
          reason: 'the tag sidecar must round-trip through disk');
      uid = 'user-a';
      expect(reloaded.routes, hasLength(1));
    });

    test('the tag sidecar is not loaded as a route', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      store.currentUserIdProvider = () => 'user-a';
      await store.save(makeRoute(id: 'r-1'));

      final reloaded = LocalRouteStore();
      await reloaded.init(overrideDirectory: tempDir);
      reloaded.currentUserIdProvider = () => 'user-a';
      expect(reloaded.routes, hasLength(1));
    });

    test('delete drops the tag so a reused id starts clean', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      String? uid = 'user-a';
      store.currentUserIdProvider = () => uid;
      await store.save(makeRoute(id: 'r-del'));
      await store.delete('r-del');

      uid = null;
      await store.save(makeRoute(id: 'r-del', name: 'Rebuilt signed out'));
      uid = 'user-b';
      expect(store.routes.map((r) => r.id), contains('r-del'),
          reason: "the stale tag must not hide a re-created unowned route");
    });
  });

  // Issue #674: LocalRouteStore previously had no delete-retry queue at
  // all — a failed api.deleteRoute left the route intact locally with
  // no way to ever retry. This group mirrors LocalRunStore's pending
  // remote-delete coverage (local_run_store_test.dart).
  group('pending remote deletes', () {
    test('markPendingRemoteDelete persists across reload and is idempotent',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('route-a');
      await store.markPendingRemoteDelete('route-b');
      await store.markPendingRemoteDelete('route-a');
      expect(store.pendingRemoteDeleteIds, {'route-a', 'route-b'});

      final store2 = LocalRouteStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.pendingRemoteDeleteIds, {'route-a', 'route-b'});
    });

    test('markManyPendingRemoteDelete folds N adds into one notify',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      var notifyCount = 0;
      store.addListener(() => notifyCount++);
      await store.markManyPendingRemoteDelete(['a', 'b', 'c']);
      expect(notifyCount, 1);
      expect(store.pendingRemoteDeleteIds, {'a', 'b', 'c'});
    });

    test(
        'markManyPendingRemoteDelete with no new ids is a no-op '
        '(no notify, no write)', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('a');
      var notifyCount = 0;
      store.addListener(() => notifyCount++);
      await store.markManyPendingRemoteDelete(['a']);
      expect(notifyCount, 0);
    });

    test('clearPendingRemoteDelete removes a single id and persists',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markManyPendingRemoteDelete(['a', 'b']);
      await store.clearPendingRemoteDelete('a');
      expect(store.pendingRemoteDeleteIds, {'b'});

      final store2 = LocalRouteStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.pendingRemoteDeleteIds, {'b'});
    });

    test('clearing the last pending id deletes the sidecar', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('only');
      expect(
          File('${tempDir.path}/pending_remote_route_deletes.json')
              .existsSync(),
          true);
      await store.clearPendingRemoteDelete('only');
      expect(
          File('${tempDir.path}/pending_remote_route_deletes.json')
              .existsSync(),
          false);
    });

    test('pending-delete owner tag persists across cold start', () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('route-a', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('route-b', ownerUserId: 'user-b');
      await store.markPendingRemoteDelete('route-legacy'); // no owner

      expect(store.debugPendingRemoteDeleteOwner('route-a'), 'user-a');
      expect(store.debugPendingRemoteDeleteOwner('route-b'), 'user-b');
      expect(store.debugPendingRemoteDeleteOwner('route-legacy'), isNull);

      final store2 = LocalRouteStore();
      await store2.init(overrideDirectory: tempDir);
      expect(store2.debugPendingRemoteDeleteOwner('route-a'), 'user-a');
      expect(store2.debugPendingRemoteDeleteOwner('route-b'), 'user-b');
      expect(store2.debugPendingRemoteDeleteOwner('route-legacy'), isNull);
    });

    test('pendingRemoteDeletesForUser filters by owner + accepts untagged',
        () async {
      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      await store.markPendingRemoteDelete('a-1', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('a-2', ownerUserId: 'user-a');
      await store.markPendingRemoteDelete('b-1', ownerUserId: 'user-b');
      await store.markPendingRemoteDelete('legacy'); // untagged

      expect(store.pendingRemoteDeletesForUser('user-a'),
          {'a-1', 'a-2', 'legacy'});
      expect(store.pendingRemoteDeletesForUser('user-b'), {'b-1', 'legacy'});
      expect(store.pendingRemoteDeletesForUser(null), isEmpty);
      expect(
          store.pendingRemoteDeleteIds, {'a-1', 'a-2', 'b-1', 'legacy'});
    });

    test('pending_remote_route_deletes.json is excluded from the route-file '
        'glob', () async {
      File('${tempDir.path}/pending_remote_route_deletes.json')
          .writeAsStringSync('{"deletes":{"queued-1":null}}');
      final realRoute = makeRoute(id: 'real');
      File('${tempDir.path}/${realRoute.id}.json')
          .writeAsStringSync(jsonEncode(realRoute.toJson()));

      final store = LocalRouteStore();
      await store.init(overrideDirectory: tempDir);
      expect(store.routes.map((r) => r.id).toList(), ['real']);
      expect(store.pendingRemoteDeleteIds, {'queued-1'});
    });
  });

}
