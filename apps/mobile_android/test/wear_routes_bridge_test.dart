import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/local_route_store.dart';
import '../lib/wear_routes_bridge.dart';

/// Records every `push` invocation the bridge makes via the
/// `run_app/wear_routes` method channel. The test binding's mock
/// handler captures the args, lets us assert ordering + payload,
/// and can simulate the native plugin throwing.
class _MockChannel {
  final List<Map<String, dynamic>> pushCalls = [];
  bool throwPlatform = false;
  bool throwMissingPlugin = false;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('run_app/wear_routes'),
      _handle,
    );
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('run_app/wear_routes'),
      null,
    );
  }

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'push') {
      if (throwMissingPlugin) {
        throw MissingPluginException('test: no plugin');
      }
      if (throwPlatform) {
        throw PlatformException(code: 'put_failed', message: 'test failure');
      }
      pushCalls.add(Map<String, dynamic>.from(call.arguments as Map));
    }
    return null;
  }
}

Route _makeRoute({
  required String id,
  String name = 'Route',
  double distance = 5000,
  bool isStarred = false,
  List<Waypoint> waypoints = const [
    Waypoint(lat: 47.37, lng: 8.54),
    Waypoint(lat: 47.371, lng: 8.541),
  ],
}) {
  return Route(
    id: id,
    userId: 'uid',
    name: name,
    waypoints: waypoints,
    distanceMetres: distance,
    isStarred: isStarred,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late LocalRouteStore store;
  late _MockChannel channel;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('wear_routes_bridge_test_');
    store = LocalRouteStore();
    await store.init(overrideDirectory: tempDir);
    channel = _MockChannel()..install();
  });

  tearDown(() {
    channel.uninstall();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('attach', () {
    test('immediately pushes the current starred subset', () async {
      await store.save(_makeRoute(id: 'r-starred', isStarred: true));
      await store.save(_makeRoute(id: 'r-plain'));

      WearRoutesBridge().attach(store);
      // Push is async; let the microtask queue drain.
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(1));
      expect((payload.single as Map)['id'], 'r-starred');
    });

    test('pushes on every save() to the store', () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      // Initial push fires from attach() even with an empty store.
      expect(channel.pushCalls, hasLength(1));

      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(2));

      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(3));
    });

    test('payload contains id + name + distance_m + waypoints with lat/lng',
        () async {
      await store.save(
        _makeRoute(
          id: 'r-1',
          name: 'Park loop',
          distance: 7500,
          isStarred: true,
          waypoints: const [
            Waypoint(lat: 1.1, lng: 2.2),
            Waypoint(lat: 3.3, lng: 4.4),
          ],
        ),
      );
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      final route = payload.single as Map<String, dynamic>;
      expect(route['id'], 'r-1');
      expect(route['name'], 'Park loop');
      expect(route['distance_m'], 7500);
      final wps = route['waypoints'] as List;
      expect(wps, hasLength(2));
      expect((wps.first as Map)['lat'], 1.1);
      expect((wps.first as Map)['lng'], 2.2);
      expect((wps.last as Map)['lat'], 3.3);
      expect((wps.last as Map)['lng'], 4.4);
    });

    test('payload includes only starred routes, filters out plain', () async {
      await store.save(_makeRoute(id: 'starred-1', isStarred: true));
      await store.save(_makeRoute(id: 'plain-1'));
      await store.save(_makeRoute(id: 'starred-2', isStarred: true));
      await store.save(_makeRoute(id: 'plain-2'));

      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      final ids = payload.map((r) => (r as Map)['id']).toSet();
      expect(ids, {'starred-1', 'starred-2'});
    });

    test('empty starred list still pushes — lets the watch clear its cache',
        () async {
      // No starred routes; only a plain one.
      await store.save(_makeRoute(id: 'plain'));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1),
          reason: 'attach must always push at least once, even with 0 starred');
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, isEmpty);
    });

    test('updated_at_ms stamps roughly current epoch millis', () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      final stamp = channel.pushCalls.single['updated_at_ms'] as int;
      final now = DateTime.now().millisecondsSinceEpoch;
      // Within 5 s of "now" — generous tolerance for slow CI.
      expect((now - stamp).abs(), lessThan(5000));
    });
  });

  group('detach', () {
    test('removes the listener — subsequent store changes do not push',
        () async {
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // initial push from attach.
      expect(channel.pushCalls, hasLength(1));

      bridge.detach();
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'detach must remove the listener; no new push should fire');
    });

    test('detach without prior attach is a no-op', () {
      // Smoke: must not throw.
      WearRoutesBridge().detach();
    });

    test('double-detach is a no-op', () async {
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      bridge.detach();
      bridge.detach(); // second detach with no listener attached
      // No throw means success.
    });
  });

  group('re-attach', () {
    test('second attach replaces the first listener — no leak', () async {
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // The first attach fires its initial push.
      expect(channel.pushCalls, hasLength(1));

      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // The second attach also fires its initial push — that's 2 total.
      expect(channel.pushCalls, hasLength(2));

      // A single save() should now fire ONE listener — not two.
      // Pre-fix: a second attach without detach would leave the
      // first listener attached, so this save() would push twice.
      channel.pushCalls.clear();
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 're-attach must remove the prior listener — '
              'otherwise every save triggers two pushes');
    });

    test('attach after detach also fires fresh — both detach + re-attach safe',
        () async {
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      bridge.detach();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);

      // Initial push fired from the re-attach, prior attach was
      // detached cleanly.
      expect(channel.pushCalls, isNotEmpty);

      channel.pushCalls.clear();
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));
    });
  });

  group('platform error handling', () {
    test('MissingPluginException is silently swallowed', () async {
      // iOS / unregistered-plugin path — bridge must not crash
      // the phone-side app just because the watch isn't there.
      channel.throwMissingPlugin = true;
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      // No throw; the (empty) push attempt fired but was caught.
      // The handler still records the call so we know we tried.
      // (Push happened but landed on the throwing native side.)
    });

    test('PlatformException is silently swallowed', () async {
      // Wearable Data Layer unavailable (no Google Play Services)
      // — same swallow semantics so the phone app keeps working.
      channel.throwPlatform = true;
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      // No throw.
    });

    test(
        'subsequent saves keep firing even after a transient platform error',
        () async {
      // First push fails; bridge must not give up — the listener
      // stays installed so the NEXT store change still fires.
      channel.throwPlatform = true;
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);

      channel.throwPlatform = false;
      channel.pushCalls.clear();
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1),
          reason: 'a swallowed exception must not detach the listener');
    });
  });

  group('integration with LocalRouteStore.saveBatch + delete', () {
    test('saveBatch triggers exactly one push (single listener notification)',
        () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.saveBatch([
        _makeRoute(id: 'a', isStarred: true),
        _makeRoute(id: 'b', isStarred: true),
        _makeRoute(id: 'c'),
      ]);
      await Future<void>.delayed(Duration.zero);

      // saveBatch notifies listeners exactly once — bridge pushes
      // exactly once. Batched saves are the common server-pull case.
      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      final ids = payload.map((r) => (r as Map)['id']).toSet();
      expect(ids, {'a', 'b'},
          reason: 'only starred routes from the batch land in the payload');
    });

    test('delete of a starred route triggers a fresh push', () async {
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.delete('r-1');
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      final ids = payload.map((r) => (r as Map)['id']).toList();
      expect(ids, ['r-2'], reason: 'r-1 must be absent from the new push');
    });

    test('starring an existing route triggers a push that includes it',
        () async {
      // Save a plain route first (no push because not starred — wait,
      // the bridge always pushes on save, but the payload is filtered
      // to starred; so the payload is empty).
      await store.save(_makeRoute(id: 'r-1'));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // User stars r-1 on the route-detail screen — save() flows
      // through with the updated row.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(1));
      expect((payload.single as Map)['id'], 'r-1');
    });
  });
}
