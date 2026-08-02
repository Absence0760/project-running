import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, visibleForTesting;
import 'package:flutter/services.dart';

import 'route_simplify.dart' show simplifyToBudget;

/// Positions one Apple Watch route push may carry. Must match
/// `ArmedRoute.maxPoints` in `apps/watch_ios/WatchApp/ArmedRoute.swift` and
/// `WatchIngestBridge.maxRoutePoints` in
/// `apps/mobile_ios/ios/Runner/WatchIngestBridge.swift`, both of which drop
/// an over-cap payload whole.
///
/// 512 positions is ~8 KB of coordinate data, comfortably inside the
/// `WCSession` user-info ceiling, and keeps the watch's per-fix projection
/// (linear in the point count, run once per GPS sample) negligible. It is
/// deliberately looser than the custom watch's 256-point `CRS1` cap, which is
/// a flash-capacity limit this device does not have.
const int kMaxAppleWatchRoutePoints = 512;

/// Why a saved route cannot be sent to the Apple Watch.
enum AppleWatchRouteRefusal {
  /// Fewer than two positions — there is no line to follow, and both the
  /// phone bridge and the watch decoder refuse such a payload.
  tooFewPoints,
}

/// A route shaped for the Apple Watch push: the positions the payload will
/// carry, how many the route started with, or the reason it cannot be sent.
///
/// [points] and [refusal] are exclusive. A caller that gets [points] has a
/// route to push; a caller that gets a [refusal] has something to tell the
/// runner, never a silently shortened route.
class AppleWatchRouteResult {
  final List<Waypoint>? points;

  /// Positions on the route before any thinning — the denominator behind
  /// "thinned N of M points to fit".
  final int sourcePointCount;
  final AppleWatchRouteRefusal? refusal;

  const AppleWatchRouteResult({
    required this.points,
    required this.sourcePointCount,
  }) : refusal = null;

  const AppleWatchRouteResult.refused(this.refusal, this.sourcePointCount)
      : points = null;

  bool get simplified => points != null && points!.length < sourcePointCount;
}

/// Shape a saved route's polyline into the positions an Apple Watch push
/// carries.
///
/// A denser route is thinned by priority Douglas–Peucker (`simplifyToBudget`),
/// never cut at the cap: a polyline that stopped at position 512 would hand
/// the watch a line ending mid-route, and `RouteNavigator` would then report
/// the runner off route against geometry the route does not have and announce
/// the finish early. Both endpoints survive the thinning by construction.
AppleWatchRouteResult appleWatchRouteFromWaypoints(List<Waypoint> waypoints) {
  if (waypoints.length < 2) {
    return AppleWatchRouteResult.refused(
      AppleWatchRouteRefusal.tooFewPoints,
      waypoints.length,
    );
  }
  return AppleWatchRouteResult(
    points: simplifyToBudget(waypoints, maxPoints: kMaxAppleWatchRoutePoints),
    sourcePointCount: waypoints.length,
  );
}

/// Pushes a route to the paired Apple Watch so its `RouteNavigator` has a line
/// to follow during a wrist-recorded run.
///
/// The native half is `WatchIngestBridge.swift` in `apps/mobile_ios/ios/Runner`
/// (the same class that ingests finished watch runs — `WCSession.delegate` is
/// a single slot), which hands the payload to
/// `WCSession.transferUserInfo(_:)`. Queued rather than immediate: the runner
/// picks a route long before the watch app is on screen.
///
/// iOS-only, so both entry points fall closed on any other target platform
/// (decisions §39 — one Dart codebase, platform dispatch inside it). The
/// dispatch reads `defaultTargetPlatform` rather than `Platform.isIOS` so
/// host-run widget tests can drive the iOS branch, matching `apple_auth.dart`.
class AppleWatchRouteBridge {
  static const _channel = MethodChannel('run_app/watch_route');

  @visibleForTesting
  static const String channelName = 'run_app/watch_route';

  /// Whether a paired watch with the app installed is currently reachable
  /// enough to accept a queued push. False on any non-iOS platform and
  /// whenever the native side isn't registered, so a caller can hide the
  /// affordance rather than offer a button that can only fail.
  static Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _channel.invokeMethod<bool>('available') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Queue [points] as the watch's armed route. Throws
  /// [PlatformException] when the payload is rejected or no watch can take
  /// it — the caller surfaces that to the runner rather than reporting a
  /// push that never happened.
  static Future<void> push({
    required String id,
    required String name,
    required double distanceMetres,
    required List<Waypoint> points,
  }) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      throw PlatformException(
        code: 'watch_unavailable',
        message: 'Apple Watch push is iOS-only',
      );
    }
    await _channel.invokeMethod<void>('push', {
      'route_id': id,
      'route_name': name,
      'route_distance_m': distanceMetres,
      'route_lat': [for (final p in points) p.lat],
      'route_lng': [for (final p in points) p.lng],
    });
  }
}
