import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/apple_watch_route_bridge.dart';

/// Records what the bridge sends over the `run_app/watch_route` channel and
/// can play the native side's failures back at it.
class _MockChannel {
  static const _channel = MethodChannel(AppleWatchRouteBridge.channelName);

  final List<MethodCall> calls = [];
  bool available = true;
  Object? throwOnPush;
  Object? throwOnAvailable;

  void install() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, _handle);
  }

  void uninstall() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  }

  Future<dynamic> _handle(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'available':
        if (throwOnAvailable != null) throw throwOnAvailable!;
        return available;
      case 'push':
        if (throwOnPush != null) throw throwOnPush!;
        return null;
    }
    return null;
  }
}

List<Waypoint> _line(int count) => [
      for (var i = 0; i < count; i++)
        // A gentle arc rather than a straight line, so priority
        // Douglas-Peucker has real geometry to spend its budget on.
        Waypoint(lat: 51.5 + i * 0.0001, lng: -0.12 + (i % 7) * 0.00002),
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockChannel channel;

  setUp(() {
    channel = _MockChannel()..install();
  });

  tearDown(() {
    channel.uninstall();
    debugDefaultTargetPlatformOverride = null;
  });

  group('appleWatchRouteFromWaypoints', () {
    test('refuses a route with fewer than two positions', () {
      for (final points in [<Waypoint>[], _line(1)]) {
        final shaped = appleWatchRouteFromWaypoints(points);
        expect(shaped.points, isNull);
        expect(shaped.refusal, AppleWatchRouteRefusal.tooFewPoints);
        expect(shaped.sourcePointCount, points.length);
        expect(shaped.simplified, isFalse);
      }
    });

    test('passes a route already inside the budget through untouched', () {
      final points = _line(120);
      final shaped = appleWatchRouteFromWaypoints(points);
      expect(shaped.refusal, isNull);
      expect(shaped.points, points);
      expect(shaped.sourcePointCount, 120);
      expect(shaped.simplified, isFalse);
    });

    test('accepts exactly the budget without thinning', () {
      final shaped =
          appleWatchRouteFromWaypoints(_line(kMaxAppleWatchRoutePoints));
      expect(shaped.points, hasLength(kMaxAppleWatchRoutePoints));
      expect(shaped.simplified, isFalse);
    });

    test('thins an over-budget route to fit instead of cutting it short', () {
      final points = _line(kMaxAppleWatchRoutePoints * 3);
      final shaped = appleWatchRouteFromWaypoints(points);
      expect(shaped.points, hasLength(kMaxAppleWatchRoutePoints));
      expect(shaped.sourcePointCount, points.length);
      expect(shaped.simplified, isTrue);
      // Both endpoints survive: a course that stopped early would put the
      // watch off route against geometry the route does not have.
      expect(shaped.points!.first, points.first);
      expect(shaped.points!.last, points.last);
    });
  });

  group('isAvailable', () {
    test('false off iOS without ever reaching the channel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
      expect(channel.calls, isEmpty);
    });

    test('true on iOS when the native side reports a usable watch', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.available = true;
      expect(await AppleWatchRouteBridge.isAvailable(), isTrue);
      expect(channel.calls.single.method, 'available');
    });

    test('false on iOS when no watch can take a push', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.available = false;
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
    });

    test('false when the native side is missing or errors', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.throwOnAvailable = MissingPluginException('test: no plugin');
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);

      channel.throwOnAvailable =
          PlatformException(code: 'boom', message: 'test failure');
      expect(await AppleWatchRouteBridge.isAvailable(), isFalse);
    });
  });

  group('push', () {
    Future<void> pushLine(List<Waypoint> points) => AppleWatchRouteBridge.push(
          id: 'route-1',
          name: 'Riverside loop',
          distanceMetres: 5120.5,
          points: points,
        );

    test('sends the id, name, distance and parallel coordinate arrays',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final points = _line(4);
      await pushLine(points);

      final call = channel.calls.single;
      expect(call.method, 'push');
      final args = Map<String, dynamic>.from(call.arguments as Map);
      expect(args['route_id'], 'route-1');
      expect(args['route_name'], 'Riverside loop');
      expect(args['route_distance_m'], 5120.5);
      expect(args['route_lat'], [for (final p in points) p.lat]);
      expect(args['route_lng'], [for (final p in points) p.lng]);
      expect((args['route_lat'] as List).length,
          (args['route_lng'] as List).length);
      expect(args.keys.toSet(), {
        'route_id',
        'route_name',
        'route_distance_m',
        'route_lat',
        'route_lng',
      });
    });

    test('throws off iOS rather than reporting a push that cannot happen',
        () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await expectLater(pushLine(_line(4)), throwsA(isA<PlatformException>()));
      expect(channel.calls, isEmpty);
    });

    test('surfaces a native rejection instead of swallowing it', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      channel.throwOnPush =
          PlatformException(code: 'watch_unavailable', message: 'no watch');
      await expectLater(pushLine(_line(4)), throwsA(isA<PlatformException>()));
    });
  });

  // ---- Cross-language wiring guards -----------------------------------
  //
  // The route push crosses three languages and nothing else compiles the
  // three together:
  //
  //   apps/mobile_android/lib/apple_watch_route_bridge.dart   (Dart writer)
  //   apps/mobile_ios/ios/Runner/WatchIngestBridge.swift      (phone bridge)
  //   apps/watch_ios/WatchApp/ArmedRoute.swift                (watch decoder)
  //
  // A renamed key or a drifting point cap fails silently at runtime — the
  // watch simply never arms a route — so pin them here. A missing file is a
  // hard failure, not a skip: both sibling apps are in this monorepo, so the
  // only way a path stops resolving is a rename or a move, which is precisely
  // the drift these guards exist to catch (decisions § 793).
  group('Apple Watch route-push cross-language wiring guards', () {
    String read(String path) {
      final file = File(path);
      if (!file.existsSync()) {
        fail('$path is gone. If it moved, move this guard with it — a guard '
            'that skips on a missing file certifies nothing.');
      }
      return file.readAsStringSync();
    }

    const payloadKeys = [
      'route_id',
      'route_name',
      'route_distance_m',
      'route_lat',
      'route_lng',
    ];

    test('the phone bridge serves the same channel and payload keys', () {
      final swift = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      expect(swift, contains('"${AppleWatchRouteBridge.channelName}"'),
          reason: 'WatchIngestBridge.swift must register the same '
              'MethodChannel name the Dart bridge invokes.');
      expect(swift, contains('transferUserInfo'),
          reason: 'A route push must ride the queued, durable transport — '
              'sendMessage needs a reachable watch, which is exactly what '
              'the runner does not have when picking a route.');
      for (final key in payloadKeys) {
        expect(swift, contains('"$key"'),
            reason: 'WatchIngestBridge.swift must forward "$key".');
      }
    });

    test('the watch decoder reads the same payload keys', () {
      final swift = read('../watch_ios/WatchApp/ArmedRoute.swift');
      for (final key in payloadKeys) {
        expect(swift, contains('"$key"'),
            reason: 'ArmedRoute.decode must read "$key".');
      }
    });

    test('the point cap is the same number in all three languages', () {
      final phone = read('../mobile_ios/ios/Runner/WatchIngestBridge.swift');
      final watch = read('../watch_ios/WatchApp/ArmedRoute.swift');
      expect(phone, contains('maxRoutePoints = $kMaxAppleWatchRoutePoints'),
          reason: 'A phone cap above the watch cap queues a durable transfer '
              'the watch will reject on every retry.');
      expect(watch, contains('maxPoints = $kMaxAppleWatchRoutePoints'),
          reason: 'ArmedRoute.maxPoints must match '
              'kMaxAppleWatchRoutePoints.');
    });

    test('route detail offers the push and shapes the route first', () {
      final screen = read('lib/screens/route_detail_screen.dart');
      expect(screen, contains('appleWatchRouteFromWaypoints(_displayWaypoints)'),
          reason: 'The push must read the privacy-clipped polyline '
              '(decisions §33) and go through the shaping helper, so an '
              'over-cap route is thinned rather than rejected by the '
              'native bridge.');
      expect(screen, contains('AppleWatchRouteBridge.push('),
          reason: 'route_detail_screen must reach the bridge.');
      expect(screen, contains("value: 'apple_watch'"),
          reason: 'The share menu must carry the Send-to-Apple-Watch row.');
      expect(screen, contains('routeDetailAppleWatchRouteTooShort'),
          reason: 'A refused route must tell the runner why, not fail '
              'silently.');
    });

    test('the watch consumes the navigator during a run', () {
      final content = read('../watch_ios/WatchApp/ContentView.swift');
      final workout = read('../watch_ios/WatchApp/WorkoutManager.swift');
      expect(content, contains('RouteGuidanceView(navigator:'),
          reason: 'The running screen must render the RouteNavigator '
              'outputs — an engine with no surface is unreachable.');
      expect(workout, contains('ArmedRouteStore.load()'),
          reason: 'WorkoutManager.start() must pick up the armed route.');
      expect(workout, contains('navigator.update(currentLocation:'),
          reason: 'The navigator must be fed from the GPS stream.');
    });
  });
}
