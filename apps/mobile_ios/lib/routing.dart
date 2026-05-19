import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show Waypoint;

/// Dart port of `apps/web/src/lib/routing.ts` — OSRM client for the
/// in-app route builder. Two helpers: [snapToRoad] for the
/// nearest-road service, and [fetchRouteThrough] for a full route
/// through N waypoints.
///
/// All callers can pass a [fetcher] (a `Future<String> Function(Uri)`)
/// to inject a mock for unit tests. The default fetcher uses
/// `dart:io`'s [HttpClient] (no new package dependency).

const _kOsrmBase = 'https://router.project-osrm.org';

/// Per-call ceilings mirroring the web side
/// (`apps/web/src/lib/components/RouteBuilder.svelte`): 5s on the
/// /nearest snap helper, 8s on the /route polyline build. Without
/// these the public OSRM demo's occasional 30s+ stalls pin the
/// route-builder's "Calculating route…" spinner indefinitely.
/// TimeoutException falls into [snapToRoad]'s catch-all (returning
/// the input unchanged) or propagates out of [fetchRouteThrough] for
/// the caller's existing banner path.
const Duration kOsrmSnapTimeout = Duration(seconds: 5);
const Duration kOsrmRouteTimeout = Duration(seconds: 8);

/// HTTP profile passed to OSRM. `foot` mirrors the web's trail mode;
/// `car` mirrors the road mode. We don't expose a bicycle profile.
enum OsrmProfile { foot, car }

extension OsrmProfileX on OsrmProfile {
  String get path => switch (this) {
        OsrmProfile.foot => 'foot',
        OsrmProfile.car => 'car',
      };
}

/// Pluggable fetcher so tests can replay canned bodies without
/// touching the network. Returns the response body as a UTF-8 string
/// and throws on HTTP error.
typedef OsrmFetcher = Future<String> Function(Uri url);

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException('OSRM ${res.statusCode}: $body', uri: url);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

/// Snap a point to the nearest road. Returns the snapped lat/lng or
/// the input unchanged on any error (network failure, OSRM `code !=
/// 'Ok'`). Mirrors the web's `snapToRoad`.
Future<Waypoint> snapToRoad(
  Waypoint point, {
  OsrmProfile profile = OsrmProfile.foot,
  OsrmFetcher? fetcher,
}) async {
  final url = Uri.parse(
    '$_kOsrmBase/nearest/v1/${profile.path}/${point.lng},${point.lat}',
  );
  try {
    final body = await (fetcher ?? _defaultFetcher)(url).timeout(kOsrmSnapTimeout);
    final data = jsonDecode(body) as Map<String, dynamic>;
    if (data['code'] != 'Ok') return point;
    final waypoints = data['waypoints'] as List?;
    if (waypoints == null || waypoints.isEmpty) return point;
    final location = (waypoints.first as Map)['location'] as List;
    // OSRM returns [lng, lat].
    return Waypoint(
      lat: (location[1] as num).toDouble(),
      lng: (location[0] as num).toDouble(),
    );
  } catch (_) {
    return point;
  }
}

/// Result of [fetchRouteThrough]: the snapped polyline coordinates +
/// the total distance OSRM reported.
class OsrmRouteResult {
  final List<Waypoint> coordinates;
  final double distanceMetres;
  const OsrmRouteResult({
    required this.coordinates,
    required this.distanceMetres,
  });
}

/// Fetch a road-snapped polyline through every waypoint in [points].
/// Throws on HTTP / parse errors so the caller can surface a banner.
/// Returns an empty result when fewer than two points are passed.
Future<OsrmRouteResult> fetchRouteThrough(
  List<Waypoint> points, {
  OsrmProfile profile = OsrmProfile.foot,
  OsrmFetcher? fetcher,
}) async {
  if (points.length < 2) {
    return const OsrmRouteResult(coordinates: [], distanceMetres: 0);
  }
  final coords = points.map((p) => '${p.lng},${p.lat}').join(';');
  final url = Uri.parse(
    '$_kOsrmBase/route/v1/${profile.path}/$coords'
    '?overview=full&geometries=geojson',
  );
  final body = await (fetcher ?? _defaultFetcher)(url).timeout(kOsrmRouteTimeout);
  final data = jsonDecode(body) as Map<String, dynamic>;
  if (data['code'] != 'Ok') {
    throw StateError('OSRM code=${data['code']}');
  }
  final routes = data['routes'] as List?;
  if (routes == null || routes.isEmpty) {
    throw StateError('OSRM no routes returned');
  }
  final route = routes.first as Map<String, dynamic>;
  final geometry = route['geometry'] as Map<String, dynamic>;
  final rawCoords = geometry['coordinates'] as List;
  final out = <Waypoint>[
    for (final pair in rawCoords)
      Waypoint(
        lat: ((pair as List)[1] as num).toDouble(),
        lng: (pair[0] as num).toDouble(),
      ),
  ];
  return OsrmRouteResult(
    coordinates: out,
    distanceMetres: (route['distance'] as num).toDouble(),
  );
}
