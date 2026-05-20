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
