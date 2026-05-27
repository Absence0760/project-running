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
      await store.save(makeRoute(id: 'r-1', name: 'v1'));
      await store.saveBatch([
        makeRoute(id: 'r-1', name: 'v2'),
        makeRoute(id: 'r-2'),
      ]);

      expect(store.routes, hasLength(2));
      expect(store.routes.firstWhere((r) => r.id == 'r-1').name, 'v2');
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
      await store.save(makeRoute(id: 'r-1', name: 'v1'));
      await store.pinOffline('r-1');

      // Fresh server pull overwrites the same id with a newer name.
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
      final sw = Stopwatch()..start();
      for (var i = 0; i < 100; i++) {
        await store.pinOffline('r-$i');
      }
      sw.stop();
      expect(store.offlinePinnedIds, hasLength(100));
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: '100 sequential pin writes took ${sw.elapsedMilliseconds}ms');

      // Survives cold start with the full set intact.
      final s2 = LocalRouteStore();
      await s2.init(overrideDirectory: tempDir);
      expect(s2.offlinePinnedIds, hasLength(100));
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
}
