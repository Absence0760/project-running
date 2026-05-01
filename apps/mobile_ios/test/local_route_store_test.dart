import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_route_store.dart';

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
}
