import 'dart:async';
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
    // Default to immediate-fire for the existing test suite — the
    // debounce-specific group restores production behavior + uses
    // FakeAsync to drive time deterministically.
    WearRoutesBridge.kPushDebounceWindow = Duration.zero;
  });

  tearDown(() {
    channel.uninstall();
    // Restore the production default so a test that intentionally
    // sets a non-zero window can rely on it for its lifetime.
    WearRoutesBridge.kPushDebounceWindow = const Duration(milliseconds: 250);
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

  group('pickRoutesForWatchPush', () {
    test('returns only starred routes', () {
      final routes = [
        _makeRoute(id: 'a', isStarred: true),
        _makeRoute(id: 'b'),
        _makeRoute(id: 'c', isStarred: true),
        _makeRoute(id: 'd'),
      ];
      final picked = WearRoutesBridge.pickRoutesForWatchPush(routes);
      expect(picked.map((r) => r.id), ['a', 'c']);
    });

    test('preserves caller order (LocalRouteStore is newest-first)', () {
      // The LocalRouteStore always insert(0, route)s so the first
      // element is the most recently touched. The watch picker
      // wants the newest first too — the helper must NOT re-sort.
      final routes = [
        _makeRoute(id: 'newest', isStarred: true),
        _makeRoute(id: 'middle', isStarred: true),
        _makeRoute(id: 'oldest', isStarred: true),
      ];
      final picked = WearRoutesBridge.pickRoutesForWatchPush(routes);
      expect(picked.map((r) => r.id), ['newest', 'middle', 'oldest']);
    });

    test('returns empty when no routes are starred', () {
      final routes = [
        _makeRoute(id: 'a'),
        _makeRoute(id: 'b'),
      ];
      expect(WearRoutesBridge.pickRoutesForWatchPush(routes), isEmpty);
    });

    test('returns empty for empty input', () {
      expect(WearRoutesBridge.pickRoutesForWatchPush(const []), isEmpty);
    });

    test('caps at maxRoutes when more than maxRoutes are starred', () {
      final routes = [
        for (var i = 0; i < 100; i++) _makeRoute(id: 'r-$i', isStarred: true),
      ];
      final picked =
          WearRoutesBridge.pickRoutesForWatchPush(routes, maxRoutes: 10);
      expect(picked, hasLength(10));
      // Confirms the cap keeps the FIRST N (most-recent), not a random slice.
      expect(picked.map((r) => r.id),
          ['r-0', 'r-1', 'r-2', 'r-3', 'r-4', 'r-5', 'r-6', 'r-7', 'r-8', 'r-9']);
    });

    test('returns all starred when fewer than maxRoutes', () {
      final routes = [
        _makeRoute(id: 'a', isStarred: true),
        _makeRoute(id: 'b', isStarred: true),
      ];
      final picked =
          WearRoutesBridge.pickRoutesForWatchPush(routes, maxRoutes: 50);
      expect(picked.map((r) => r.id), ['a', 'b']);
    });

    test('default maxRoutes is the published constant', () {
      expect(WearRoutesBridge.kMaxRoutesPerPush, 50,
          reason: 'changing the cap is a wire-format-adjacent decision; '
              'update the watch DataLayer 100 KB budget calc if you change it');
      final routes = [
        for (var i = 0; i < 60; i++) _makeRoute(id: 'r-$i', isStarred: true),
      ];
      final picked = WearRoutesBridge.pickRoutesForWatchPush(routes);
      expect(picked, hasLength(50));
    });

    test('mixed starred + plain over the cap honours both filters', () {
      // 100 routes total: 80 starred, 20 plain. With cap 30, the
      // first 30 starred (in input order) make it through.
      final routes = [
        for (var i = 0; i < 100; i++)
          _makeRoute(id: 'r-$i', isStarred: i % 5 != 0),
      ];
      final picked =
          WearRoutesBridge.pickRoutesForWatchPush(routes, maxRoutes: 30);
      expect(picked, hasLength(30));
      for (final r in picked) {
        expect(r.isStarred, isTrue);
      }
    });
  });

  group('encodeRoutesForWatch', () {
    test('emits the wire-format shape: id + name + distance_m + waypoints',
        () {
      final encoded = WearRoutesBridge.encodeRoutesForWatch([
        _makeRoute(
          id: 'rt-1',
          name: 'Park loop',
          distance: 5000,
          waypoints: const [
            Waypoint(lat: 47.37, lng: 8.54),
            Waypoint(lat: 47.371, lng: 8.541),
          ],
        ),
      ]);
      expect(encoded, hasLength(1));
      final row = encoded.single;
      expect(row['id'], 'rt-1');
      expect(row['name'], 'Park loop');
      expect(row['distance_m'], 5000);
      final wps = row['waypoints'] as List;
      expect(wps, hasLength(2));
      expect((wps.first as Map)['lat'], 47.37);
      expect((wps.first as Map)['lng'], 8.54);
    });

    test('omits everything that isnt id / name / distance / waypoints', () {
      // Surface and tags etc. stay on the phone — the watch only
      // needs enough to render a picker row + feed RouteMath.
      final encoded = WearRoutesBridge.encodeRoutesForWatch([
        _makeRoute(id: 'rt-1', name: 'X', distance: 1000),
      ]);
      final row = encoded.single;
      expect(row.keys.toSet(), {'id', 'name', 'distance_m', 'waypoints'});
    });

    test('empty input produces empty output', () {
      expect(WearRoutesBridge.encodeRoutesForWatch(const []), isEmpty);
    });

    test('waypoint shape is exactly {lat, lng} — no elevation or timestamp',
        () {
      // The watch's RouteMath only consumes lat/lng. Leaking
      // elevation or timestamp would bloat the payload and risk
      // approaching the DataLayer cap.
      final encoded = WearRoutesBridge.encodeRoutesForWatch([
        _makeRoute(
          id: 'rt-1',
          waypoints: const [
            Waypoint(lat: 1, lng: 2, elevationMetres: 100, timestamp: null),
            Waypoint(lat: 3, lng: 4),
          ],
        ),
      ]);
      final wps = encoded.single['waypoints'] as List;
      for (final w in wps) {
        expect((w as Map).keys.toSet(), {'lat', 'lng'});
      }
    });

    test('round-trips through jsonEncode + jsonDecode without loss', () {
      final input = [
        _makeRoute(
          id: 'rt-1',
          name: 'Round-trip',
          distance: 5432.1,
          waypoints: const [
            Waypoint(lat: 47.37, lng: 8.54),
            Waypoint(lat: 47.371, lng: 8.541),
          ],
        ),
      ];
      final encoded = WearRoutesBridge.encodeRoutesForWatch(input);
      final wire = jsonEncode(encoded);
      final decoded = jsonDecode(wire) as List;
      expect(decoded, hasLength(1));
      final row = decoded.single as Map<String, dynamic>;
      expect(row['id'], 'rt-1');
      expect(row['distance_m'], 5432.1);
      expect((row['waypoints'] as List).length, 2);
    });
  });

  group('cap enforcement at the channel boundary', () {
    test('pushing 100 starred routes truncates to kMaxRoutesPerPush at the wire',
        () async {
      // Save 100 starred routes. The bridge must invoke the channel
      // with at most kMaxRoutesPerPush entries; the full set stays
      // on the phone's local store.
      for (var i = 0; i < 100; i++) {
        await store.save(_makeRoute(id: 'r-$i', isStarred: true));
      }
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(WearRoutesBridge.kMaxRoutesPerPush));
      // The 100 routes were all saved — the cap is a push-side
      // limit, not a store-side one.
      expect(store.routes, hasLength(100));
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

  group('payload-diff cache', () {
    // Reason: LocalRouteStore.save() fires for every route mutation,
    // not just `is_starred` changes. Editing description, toggling
    // is_public, adding a tag — none of those change the watch-
    // visible subset (id + name + distance + waypoints of starred
    // routes). Without the diff cache the bridge wakes the watch's
    // DataClient listener on every such edit. The cache turns
    // those into local-only operations.

    test('re-saving an identical row does not fire a second push', () async {
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      // attach() fires the initial push.
      expect(channel.pushCalls, hasLength(1));

      // Same row, same starred state — payload is byte-equivalent.
      // Diff gate must swallow.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'identical payload must NOT fire a redundant push');
    });

    test('saving an UNSTARRED route does not fire a push when no other '
        'starred change happened', () async {
      // Only starred routes ride the wire; an unstarred save() can't
      // change the wire payload. Diff gate catches this.
      await store.save(_makeRoute(id: 'starred', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Add an unstarred route — starred subset is still [starred].
      await store.save(_makeRoute(id: 'plain-1'));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, isEmpty,
          reason: 'unstarred save() must not cause a push when the '
              'starred subset is byte-identical');

      // Another unstarred — still no push.
      await store.save(_makeRoute(id: 'plain-2'));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, isEmpty);
    });

    test('mutation that does not affect the wire fields is a no-op push',
        () async {
      // Editing description, toggling is_public, etc. fires
      // LocalRouteStore.save() but doesn't change id / name /
      // distance / waypoints. The wire payload is identical;
      // diff must skip.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Same id + name + distance + waypoints + isStarred — only
      // non-wire fields would have changed (in a real edit). The
      // _makeRoute helper doesn't take those args, so this is
      // effectively a "re-save unchanged" — same byte result.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, isEmpty);
    });

    test('starring a NEW route invalidates the cache and fires a push',
        () async {
      await store.save(_makeRoute(id: 'old-starred', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // New starred route → payload changes → push.
      await store.save(_makeRoute(id: 'new-starred', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      // Payload contains both routes (newest-first by store ordering).
      expect(payload, hasLength(2));
    });

    test('unstarring an existing starred route fires a push', () async {
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Unstar r-1 → starred subset becomes [r-2] — different payload.
      await store.save(_makeRoute(id: 'r-1'));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload.map((r) => (r as Map)['id']), ['r-2']);
    });

    test('star-then-unstar-then-restar produces THREE pushes (not deduped)',
        () async {
      // Each toggle changes the wire payload. Diff cache only
      // catches IDENTICAL bytes; A → B → A produces three pushes
      // (each different from its predecessor) even though the
      // first and third payloads match.
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Star — payload: [r-1]
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));

      // Unstar — payload: []
      await store.save(_makeRoute(id: 'r-1'));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(2));

      // Re-star — payload: [r-1] (same as push 1, but diff cache's
      // last-sent is [] so this is a change).
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(3),
          reason: 'A→B→A produces 3 pushes, not 1 — the diff cache '
              'tracks last-sent only, not historical state');
    });

    test('a swallowed PlatformException does NOT update the diff cache',
        () async {
      // The next legitimate change should still fire the push,
      // since the previous attempt never actually shipped.
      channel.throwPlatform = true;
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // The exception-throwing channel was hit but didn't record
      // the call (handler throws before pushCalls.add). Diff
      // cache stays empty so the next attempt fires.

      channel.throwPlatform = false;
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'a failed push must NOT poison the diff cache; '
              'the next save should still ship');
    });

    test('a swallowed MissingPluginException also leaves the cache alone',
        () async {
      channel.throwMissingPlugin = true;
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);

      channel.throwMissingPlugin = false;
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));
    });

    test('detach resets the cache — fresh attach pushes even if subset '
        'matches', () async {
      // The bridge has no insight into whether the watch is still
      // in sync after a detach (process restart / hot reload).
      // Best-effort: re-fire on attach so the watch gets at least
      // one push for the new bridge lifecycle.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // Initial push fired.
      expect(channel.pushCalls, hasLength(1));

      bridge.detach();
      // Re-attach with the same store — same starred subset.
      // Without the cache-reset on detach, the next attach() would
      // diff-match and skip. We want it to fire so a new
      // subscriber's process is guaranteed at least one push.
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(2),
          reason: 'detach must reset the diff cache so the next attach '
              "fires unconditionally — otherwise a hot-restart in dev "
              "or a re-init in prod wouldn't push the new subscriber");
    });

    test('re-attach within the same bridge instance also resets the cache',
        () async {
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));

      // Re-attach without explicit detach — the bridge's idempotent
      // attach() calls detach() internally which resets the cache.
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(2));
    });
  });

  group('burst + lifecycle characterization', () {
    test('5 starred saves of DIFFERENT routes fire 5 pushes', () async {
      // No throttling today — each distinct save fires a push.
      // Pin this so a future debounce/throttle PR has explicit
      // test acknowledgement.
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      for (var i = 0; i < 5; i++) {
        await store.save(_makeRoute(id: 'r-$i', isStarred: true));
      }
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(5),
          reason: 'no throttling — 5 distinct saves produce 5 pushes; '
              'a future debounce would update this expectation');
    });

    test('100 rapid IDENTICAL re-saves fire ONE push (diff catches '
        'the rest)', () async {
      // The diff cache turns this into O(1) work.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      for (var i = 0; i < 100; i++) {
        await store.save(_makeRoute(id: 'r-1', isStarred: true));
      }
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, isEmpty,
          reason: '100 identical re-saves must produce zero pushes; '
              'the watch sees the original push and that is it');
    });

    test('burst of 100 alternating star-then-unstar fires 100 pushes',
        () async {
      // A→B→A→B pattern: every save differs from the previous,
      // so every save fires.
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      for (var i = 0; i < 100; i++) {
        await store.save(_makeRoute(id: 'r-1', isStarred: i % 2 == 0));
      }
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(100));
    });

    test('mixed burst: starred + plain interleaved fires once per '
        'starred-set change', () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Plain saves don't fire pushes (diff catches them).
      await store.save(_makeRoute(id: 'plain-1'));
      await store.save(_makeRoute(id: 'plain-2'));
      expect(channel.pushCalls, isEmpty);

      // Star one — fires.
      await store.save(_makeRoute(id: 'starred-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));

      // More plains — no push.
      await store.save(_makeRoute(id: 'plain-3'));
      await store.save(_makeRoute(id: 'plain-4'));
      expect(channel.pushCalls, hasLength(1));

      // Star another — fires.
      await store.save(_makeRoute(id: 'starred-2', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(2));
    });

    test('saveBatch with 50 starred + 50 plain fires ONE push '
        '(notify-once contract)', () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      final routes = [
        for (var i = 0; i < 50; i++)
          _makeRoute(id: 's-$i', isStarred: true),
        for (var i = 0; i < 50; i++) _makeRoute(id: 'p-$i'),
      ];
      await store.saveBatch(routes);
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(1),
          reason: 'saveBatch notifies listeners exactly once');
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(50));
    });

    test('detach mid-burst stops further pushes', () async {
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1));

      bridge.detach();

      // After detach, further saves don't fire.
      for (var i = 0; i < 10; i++) {
        await store.save(_makeRoute(id: 'r-burst-$i', isStarred: true));
      }
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'detach must immediately stop all subsequent pushes');
    });

    test('detach during an in-flight push completes the in-flight + stops '
        'subsequent', () async {
      // The race-condition shape: a save fires the listener, _push
      // schedules + awaits the channel.invoke. Before that
      // completes, detach() runs. The in-flight invocation should
      // resolve normally; no new pushes fire after.
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Trigger a save WITHOUT awaiting the microtask.
      final saveFuture = store.save(_makeRoute(id: 'r-1', isStarred: true));
      // Detach immediately — the listener has already been invoked
      // (LocalRouteStore notifies synchronously after the file
      // write), so the in-flight _push call is already mid-await.
      bridge.detach();
      // Let everything settle.
      await saveFuture;
      await Future<void>.delayed(Duration.zero);

      // Either: the in-flight push completed (1 call) OR detach()
      // got in before invokeMethod (0 calls). The contract is
      // "no crash, no leak" — pin that subsequent saves fire NO
      // pushes either way.
      final beforeBurst = channel.pushCalls.length;
      for (var i = 0; i < 5; i++) {
        await store.save(_makeRoute(id: 'late-$i', isStarred: true));
      }
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls.length, beforeBurst,
          reason: 'after detach, NO subsequent saves should fire pushes');
    });

    test('attach + immediate detach + new attach (hot-restart pattern)',
        () async {
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final b1 = WearRoutesBridge();
      b1.attach(store);
      await Future<void>.delayed(Duration.zero);
      b1.detach();
      channel.pushCalls.clear();

      // Hot-restart pattern: new bridge instance, fresh attach.
      final b2 = WearRoutesBridge();
      b2.attach(store);
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'a new bridge instance pushes once on attach');
    });

    test('two bridge instances pointed at the same store push '
        'independently', () async {
      // This shouldn't happen in production (main.dart attaches a
      // single bridge) but pin the behavior — each bridge has its
      // own diff cache + lifecycle.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final b1 = WearRoutesBridge();
      final b2 = WearRoutesBridge();
      b1.attach(store);
      b2.attach(store);
      await Future<void>.delayed(Duration.zero);
      // Both bridges share the same channel mock, so two attaches
      // = two pushes.
      expect(channel.pushCalls.length, greaterThanOrEqualTo(2),
          reason: 'separate bridge instances both push on attach');

      channel.pushCalls.clear();
      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls.length, greaterThanOrEqualTo(2),
          reason: 'separate bridges each fire on each save');
    });
  });

  group('end-to-end wire round-trip', () {
    // Tests that exercise the full Dart-side pipeline: store mutation
    // → bridge listener → encode → diff gate → channel.invokeMethod
    // → captured payload. The captured payload bytes are exactly
    // what the Wear OS RoutesBridge's parseRoutesJson reads.

    test('captured channel payload is structurally identical to '
        'encodeRoutesForWatch direct output', () async {
      final routes = [
        _makeRoute(id: 'a', isStarred: true, distance: 5000),
        _makeRoute(id: 'b', isStarred: true, distance: 10000),
      ];
      for (final r in routes) {
        await store.save(r);
      }
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      final captured = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      // Apply the same filter the bridge applies internally.
      final direct = WearRoutesBridge.encodeRoutesForWatch(
        WearRoutesBridge.pickRoutesForWatchPush(store.routes),
      );
      final directJson = jsonDecode(jsonEncode(direct));
      expect(captured, directJson,
          reason: 'the bridge must ship exactly what the public '
              'encodeRoutesForWatch helper produces — drift here means '
              'the helpers tests are no longer pinning production behavior');
    });

    test('captured payload round-trips through jsonDecode without losing '
        'route shape', () async {
      await store.save(_makeRoute(
        id: 'rt-1',
        name: 'A & B "test" route',
        isStarred: true,
        waypoints: const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.371, lng: 8.541),
        ],
      ));
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      final raw = channel.pushCalls.single['routes_json'] as String;
      final decoded = jsonDecode(raw) as List;
      final row = decoded.single as Map<String, dynamic>;
      expect(row['id'], 'rt-1');
      // The XML/JSON-special characters round-trip via jsonEncode's
      // built-in escaping — this is what the Kotlin parser receives.
      expect(row['name'], 'A & B "test" route');
      expect((row['waypoints'] as List).length, 2);
    });

    test('updated_at_ms is a monotonic-increasing integer across '
        'consecutive pushes', () async {
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      // Force three distinct pushes by alternating starred state.
      for (var i = 0; i < 3; i++) {
        await store.save(_makeRoute(id: 'r-$i', isStarred: true));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      final stamps = channel.pushCalls
          .map((c) => c['updated_at_ms'] as int)
          .toList();
      expect(stamps, hasLength(4));
      // Each subsequent stamp >= the previous — DateTime.now() is
      // monotonic-millis-best-effort on the timeline.
      for (var i = 1; i < stamps.length; i++) {
        expect(stamps[i], greaterThanOrEqualTo(stamps[i - 1]),
            reason: 'updated_at_ms must be non-decreasing — the '
                "watch's stale-push gate relies on this");
      }
    });

    test('every captured payload satisfies the wire-format contract: '
        'JSON-array of objects with the four canonical keys', () async {
      // Walk the bridge through a multi-step user flow and assert
      // every push that lands on the channel still meets the
      // contract.
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);

      await store.save(_makeRoute(id: 'a', isStarred: true));
      await store.save(_makeRoute(id: 'b', isStarred: true));
      await store.save(_makeRoute(id: 'c')); // plain — no push, just bookkeeping
      await store.delete('a');
      await Future<void>.delayed(Duration.zero);

      for (final call in channel.pushCalls) {
        final raw = call['routes_json'] as String;
        final decoded = jsonDecode(raw);
        expect(decoded, isA<List>(),
            reason: 'every payload must be a JSON array');
        for (final el in decoded as List) {
          final row = el as Map<String, dynamic>;
          expect(row.keys.toSet(), {'id', 'name', 'distance_m', 'waypoints'},
              reason: 'every row must carry exactly the four wire keys');
          expect(row['id'], isA<String>());
          expect(row['name'], isA<String>());
          expect(row['distance_m'], isA<num>());
          expect(row['waypoints'], isA<List>());
          for (final wp in row['waypoints'] as List) {
            final wpMap = wp as Map;
            expect(wpMap.keys.toSet(), {'lat', 'lng'});
            expect(wpMap['lat'], isA<num>());
            expect(wpMap['lng'], isA<num>());
          }
        }
      }
    });
  });

  group('debounce window — production coalescing', () {
    // The production default is a 250ms window: rapid bursts of
    // LocalRouteStore notifications (star-storm, bulk sync drop)
    // coalesce into ONE push per quarter-second instead of N
    // independent pushes. The previous group used Duration.zero
    // for the existing test surface; this group restores the
    // production value and drives Timer via FakeAsync so we don't
    // need real wall-clock waits.

    test('initial push on attach fires immediately, NOT debounced',
        () async {
      // The first push needs to land right away so a newly-paired
      // watch gets its data without a quarter-second delay.
      WearRoutesBridge.kPushDebounceWindow = const Duration(milliseconds: 250);
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      WearRoutesBridge().attach(store);
      // Microtask drain — no FakeAsync needed for the initial push.
      await Future<void>.delayed(Duration.zero);
      expect(channel.pushCalls, hasLength(1),
          reason: 'attach() must fire its initial push without '
              'waiting for the debounce window');
    });

    test('5 rapid notifications within 50ms coalesce into ONE push', () async {
      // Real-time wait approach: short window (60ms) so the
      // tests run fast (~250ms total) and reliable — FakeAsync
      // doesn't pump platform-channel mocks.
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 60);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Fire 5 saves spaced 5ms apart. Total span: ~25ms, well
      // under the 60ms window. Each save restarts the timer.
      for (var i = 0; i < 5; i++) {
        await store.save(_makeRoute(id: 'r-$i', isStarred: true));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // The bursts kept the timer reset; no push has fired yet.
      expect(channel.pushCalls, isEmpty,
          reason: 'saves within the window must NOT have fired '
              'a push yet — timer keeps resetting');

      // Wait past the window.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channel.pushCalls, hasLength(1),
          reason: 'after the window expires with no new '
              'notifications, exactly ONE coalesced push fires');
      bridge.detach();
    });

    test('10 rapid notifications + quiescence fires once after window',
        () async {
      // 250ms window (not 60ms): on a slow CI runner each
      // `await store.save(...)` writes to disk and can take
      // 5-15ms, so 10 zero-spaced saves span 50-150ms — comfortably
      // outside a 60ms window. CI run 26523370163 split the burst
      // into 2 pushes when the 9th save crossed the 60ms boundary.
      // The 5-save sibling test stays at 60ms because its explicit
      // 5ms `Future.delayed` between saves keeps the total span
      // <= 25ms regardless of disk latency.
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 250);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      for (var i = 0; i < 10; i++) {
        await store.save(_makeRoute(id: 'r-$i', isStarred: true));
      }
      // No spacing — but each save still resets the timer.
      // After the burst, wait past the window.
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(channel.pushCalls, hasLength(1));
      // Single push reflects the FINAL state — all 10 starred.
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(10));
      bridge.detach();
    });

    test('notifications spaced longer than the window each fire separately',
        () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 40);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.save(_makeRoute(id: 'r-a', isStarred: true));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(channel.pushCalls, hasLength(1));

      await store.save(_makeRoute(id: 'r-b', isStarred: true));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(channel.pushCalls, hasLength(2));
      bridge.detach();
    });

    test('detach cancels the pending debounced push', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 100);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // Schedule a debounced push, then detach BEFORE it fires.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      bridge.detach();

      // Wait well past the window.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(channel.pushCalls, isEmpty,
          reason: 'detach must cancel the pending debounce timer; '
              'a push after detach would race the new bridge '
              'instance (hot-restart scenario)');
    });

    test('detach + re-attach mid-debounce: only the re-attach initial '
        'push fires', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 100);
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final b1 = WearRoutesBridge();
      b1.attach(store);
      await Future<void>.delayed(Duration.zero);
      // Initial push from b1.
      expect(channel.pushCalls, hasLength(1));
      channel.pushCalls.clear();

      // Stage a debounced push on b1.
      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      // Within the window: detach b1, attach b2.
      b1.detach();
      final b2 = WearRoutesBridge();
      b2.attach(store);
      await Future<void>.delayed(Duration.zero);
      // b2's initial push: now starred set = [r-1, r-2] which is
      // different from b1's initial push set [r-1] (b2 saw the
      // store AFTER r-2 was saved). So b2 fires once.
      expect(channel.pushCalls, hasLength(1));

      // Wait past where b1's pending debounce WOULD have fired —
      // nothing extra.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(channel.pushCalls, hasLength(1),
          reason: 'only b2 initial push fires; b1 pending was '
              'cancelled cleanly by detach');
      b2.detach();
    });

    test('debounce + diff cache: rapid identical re-saves still '
        'result in ZERO post-debounce pushes', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 60);
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      // Initial push captured.
      expect(channel.pushCalls, hasLength(1));
      channel.pushCalls.clear();

      // 20 identical re-saves. notifyListeners fires each; bridge
      // schedules a debounced push each. After the window expires
      // exactly once, _push runs — diff cache short-circuits
      // because the payload matches the initial push's bytes.
      for (var i = 0; i < 20; i++) {
        await store.save(_makeRoute(id: 'r-1', isStarred: true));
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channel.pushCalls, isEmpty,
          reason: '20 identical re-saves through the debounce '
              'still hit the diff cache — zero channel hits');
      bridge.detach();
    });

    test('debounce + diff cache: rapid TOGGLES collapse to ONE push '
        'reflecting the final state', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 60);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // 5 toggles within the window. Final state determines what
      // the watch sees.
      for (var i = 0; i < 5; i++) {
        await store.save(_makeRoute(id: 'r-1', isStarred: i % 2 == 0));
      }
      // Index 4 → isStarred=true → final state has [r-1] starred.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channel.pushCalls, hasLength(1));
      final payload = jsonDecode(
        channel.pushCalls.single['routes_json'] as String,
      ) as List;
      expect(payload, hasLength(1));
      expect((payload.single as Map)['id'], 'r-1');
      bridge.detach();
    });

    test('saveBatch (single notify) fires after the window', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 60);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.saveBatch([
        _makeRoute(id: 'a', isStarred: true),
        _makeRoute(id: 'b', isStarred: true),
      ]);
      // Immediately after: not yet fired.
      expect(channel.pushCalls, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channel.pushCalls, hasLength(1));
      bridge.detach();
    });

    test('zero-duration window restores immediate-fire semantics', () async {
      WearRoutesBridge.kPushDebounceWindow = Duration.zero;
      WearRoutesBridge().attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      // No window → every save fires synchronously through the
      // listener. This is the test-only path that the existing
      // suite relies on.
      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(Duration.zero);
      await store.save(_makeRoute(id: 'r-2', isStarred: true));
      await Future<void>.delayed(Duration.zero);

      expect(channel.pushCalls, hasLength(2),
          reason: 'zero window = no coalescing — each save fires '
              'inline');
    });

    test('debounce window can be reconfigured per-test via the '
        'static @visibleForTesting setter', () async {
      WearRoutesBridge.kPushDebounceWindow =
          const Duration(milliseconds: 100);
      final bridge = WearRoutesBridge();
      bridge.attach(store);
      await Future<void>.delayed(Duration.zero);
      channel.pushCalls.clear();

      await store.save(_makeRoute(id: 'r-1', isStarred: true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(channel.pushCalls, isEmpty,
          reason: '50ms < 100ms window — no push yet');

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(channel.pushCalls, hasLength(1),
          reason: '150ms > 100ms window — push fired');
      bridge.detach();
    });
  });
}
