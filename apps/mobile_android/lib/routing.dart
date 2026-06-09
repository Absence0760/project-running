import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter/foundation.dart' show kReleaseMode, visibleForTesting;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Dart port of `apps/web/src/lib/routing.ts` — OSRM client for the
/// in-app route builder. Two helpers: [snapToRoad] for the
/// nearest-road service, and [fetchRouteThrough] for a full route
/// through N waypoints.
///
/// All callers can pass a [fetcher] (a `Future<String> Function(Uri)`)
/// to inject a mock for unit tests. The default fetcher uses
/// `dart:io`'s [HttpClient] (no new package dependency).
///
/// **Dev**: falls back to `https://router.project-osrm.org`, the
/// public community demo. Convenient locally but a third-party
/// service with no DPA, no published region, and unauthenticated.
///
/// **Prod**: `OSRM_URL` MUST be set in the dotenv file (typically
/// pointing at the self-hosted `apps/job_worker/osrm/` instance on
/// Fly.io). [assertOsrmConfiguredForProd] throws on the first
/// routing call when a release-mode build still resolves to the
/// public demo — keeping the binary from silently leaking user
/// waypoints to an uncontracted third party. Mirrors the web
/// `assertOsrmConfiguredForProd` in
/// `apps/web/src/lib/routing.ts`. See audit/third-party-data-flows
/// (2026-05-25).

const _kPublicDemoOsrm = 'https://router.project-osrm.org';

/// Resolve the effective OSRM base URL. Reads `dotenv.env['OSRM_URL']`
/// if available, strips trailing slashes, and falls back to the
/// public demo URL when the env entry is missing or empty.
String _osrmBaseUrl() {
  try {
    final raw = (dotenv.env['OSRM_URL'] ?? '').trim();
    if (raw.isEmpty) return _kPublicDemoOsrm;
    return raw.replaceAll(RegExp(r'/+$'), '');
  } catch (_) {
    // dotenv may not be initialised in unit tests; that's fine —
    // the demo URL is the safe default and the prod guard below
    // covers the release-mode case.
    return _kPublicDemoOsrm;
  }
}

/// Throws when the build is in release mode AND the env override is
/// unset (so the helper would otherwise hit the community demo).
/// Callers invoke this at the top of each fetch helper so a
/// misconfigured release build fails loudly on the first routing
/// request instead of quietly forwarding user data to an
/// uncontracted third party.
///
/// `isReleaseModeOverride` is an escape hatch for unit tests that
/// need to exercise the throwing path — production callers should
/// leave it unset so [kReleaseMode] decides.
@visibleForTesting
void assertOsrmConfiguredForProd({bool? isReleaseModeOverride}) {
  final isRelease = isReleaseModeOverride ?? kReleaseMode;
  if (!isRelease) return;
  if (_osrmBaseUrl() == _kPublicDemoOsrm) {
    throw StateError(
      'OSRM not configured: set OSRM_URL in the dotenv file to a '
      'self-hosted instance. The community endpoint '
      'router.project-osrm.org is uncontracted (no DPA) and must '
      'not receive production traffic. '
      'See audit/third-party-data-flows (2026-05-25).',
    );
  }
}

/// Test-only accessor for the resolved OSRM base URL.
@visibleForTesting
String resolvedOsrmBaseUrl() => _osrmBaseUrl();

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

/// Per-waypoint OSRM snap radius (metres). OSRM's `radiuses=` query
/// caps how far the router will reach to find a road for each
/// coordinate. **Default in OSRM is unbounded** — that's how a tap
/// near a stream / parking lot / private driveway ends up snapping
/// to a road 800m+ away. Bumped from 250 → 500 m per user feedback
/// "shouldn't the waypoints stick to the road given Trail is
/// selected?" — the 250 m cap was too tight in rural / sparsely-
/// mapped regions where the nearest OSM foot edge can be 300+ m
/// from a tap. 500 m still rejects the absurd cases (>1 km detour)
/// while keeping the visible-pin-snaps-to-road contract the user
/// expects. Kept in lockstep with
/// `apps/web/src/lib/routing_quality.ts:OSRM_SNAP_RADIUS_M`.
const int kOsrmSnapRadiusM = 500;

/// Per-segment retry count for transient OSRM failures (5xx,
/// network blip, AbortError on timeout). Web's `fetchSegment` uses
/// the same 2 — total of 3 attempts per segment. With exponential-
/// ish backoff (500ms × attempt+1) the worst-case latency is
/// `8s + 500ms + 8s + 1000ms + 8s ≈ 25.5s` for a single segment
/// before falling through to straight-line; in practice transient
/// failures recover on the first retry.
const int kOsrmRetries = 2;

/// Segments routed in parallel per "batch". Three is the web's
/// `BATCH_SIZE` — high enough that a 10-waypoint route renders in
/// ~3 OSRM round-trips instead of 9, low enough that the public
/// demo server doesn't 429 on a power-user route. The 200 ms
/// inter-batch delay (see [kOsrmInterBatchDelay]) gives the rate
/// limiter time to refill between waves.
const int kOsrmBatchSize = 3;

/// Cooldown between successive parallel batches. Web uses the same
/// 200 ms; lower values cause occasional 429s on the public demo
/// server when routing a complex polyline.
const Duration kOsrmInterBatchDelay = Duration(milliseconds: 200);

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

/// Cancellation gate. The caller (typically `route_builder_screen`'s
/// `_rerouteThrough`) increments a generation counter before each
/// new route attempt and passes `() => _gen != snapshotGen` into
/// [fetchRouteThrough]. When the gate returns true, in-flight OSRM
/// calls abort early instead of completing 25 s of retries on a
/// route the user has already replaced with new pin placements.
///
/// Mirrors `apps/web/src/lib/components/RouteBuilder.svelte`'s
/// `currentVersion !== routeVersion` check.
typedef OsrmCancellation = bool Function();

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
  assertOsrmConfiguredForProd();
  // `number=1` requests just the single nearest match; `radiuses=`
  // bounds how far OSRM can reach (250m) so a tap nowhere near a
  // road falls back to the input rather than snapping to an
  // unrelated road kilometres away. Both params mirror the web
  // call shape in RouteBuilder.svelte.
  final url = Uri.parse(
    '${_osrmBaseUrl()}/nearest/v1/${profile.path}/${point.lng},${point.lat}'
    '?number=1&radiuses=$kOsrmSnapRadiusM',
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
/// the total distance OSRM reported. `okSegments` / `totalSegments`
/// surface how many segments routed cleanly vs fell back to
/// straight-line — callers can use the ratio to surface a soft
/// warning ("some segments didn't snap, drag the markers to
/// adjust").
class OsrmRouteResult {
  final List<Waypoint> coordinates;
  final double distanceMetres;
  final int okSegments;
  final int totalSegments;
  /// True iff the run was cancelled mid-way via the
  /// [OsrmCancellation] callback. Coordinates / distance reflect
  /// whatever was computed before the cancel — callers should
  /// ignore the result and NOT update UI when this is true.
  final bool wasCancelled;
  const OsrmRouteResult({
    required this.coordinates,
    required this.distanceMetres,
    this.okSegments = 0,
    this.totalSegments = 0,
    this.wasCancelled = false,
  });

  /// True iff at least one segment had to fall back to straight-
  /// line because OSRM couldn't route it within the snap radius.
  bool get hadFallbacks => okSegments < totalSegments;
}

/// Fetch a road-snapped polyline through every waypoint in [points].
///
/// **Per-segment routing with straight-line fallback** — mirrors the
/// web `RouteBuilder.svelte` behaviour. Each consecutive pair of
/// waypoints is routed independently with `radiuses=250;250` so:
///
///   - one unreachable waypoint (tap on water, parking lot, private
///     drive) doesn't poison the entire polyline; only that segment
///     falls back to a straight line
///   - the rest of the route stays road-accurate
///   - the user can drag the bad waypoint without losing the rest
///
/// Previously this was one big OSRM call through every waypoint,
/// which OSRM was free to detour kilometres on to reach any single
/// unreachable point — producing the "line takes weird shortcuts"
/// symptom that didn't match the web builder's accuracy.
///
/// Throws only when EVERY segment failed (`okSegments == 0` AND
/// `totalSegments > 0`); a partial-success run returns the stitched
/// polyline with `hadFallbacks == true`.
///
/// Pass a [cache] (held by the route builder across re-routes) so that
/// re-routing after adding one waypoint fetches only the new segment.
Future<OsrmRouteResult> fetchRouteThrough(
  List<Waypoint> points, {
  OsrmProfile profile = OsrmProfile.foot,
  OsrmFetcher? fetcher,
  OsrmCancellation? cancelled,
  RouteSegmentCache? cache,
}) async {
  if (points.length < 2) {
    return const OsrmRouteResult(coordinates: [], distanceMetres: 0);
  }
  assertOsrmConfiguredForProd();
  final f = fetcher ?? _defaultFetcher;
  final isCancelled = cancelled ?? () => false;
  final segmentPairs = <List<Waypoint>>[
    for (var i = 0; i < points.length - 1; i++) [points[i], points[i + 1]],
  ];
  final keys = [
    for (final pair in segmentPairs) segmentCacheKey(pair[0], pair[1], profile),
  ];
  // Per-segment cache: a re-route after adding one waypoint reuses
  // every prior segment and fetches only the new one, so placement
  // stays O(1) instead of O(n) as the route grows. Mirrors the web
  // `RouteBuilder` SegmentCache. Only the cache misses below hit OSRM.
  final slots = List<_RoutedSegment?>.filled(segmentPairs.length, null);
  final missIdx = <int>[];
  for (var i = 0; i < segmentPairs.length; i++) {
    final hit = cache?._get(keys[i]);
    if (hit != null) {
      slots[i] = hit;
    } else {
      missIdx.add(i);
    }
  }
  // Batch parallelism — the cache misses into batches of
  // [kOsrmBatchSize]. Web's `RouteBuilder.svelte` uses the same shape
  // so a complex route hits OSRM in a few round-trips instead of one
  // per segment. 200 ms cooldown between batches prevents the public
  // demo server from 429'ing on a complex polyline.
  for (var start = 0; start < missIdx.length; start += kOsrmBatchSize) {
    // Cancellation check between batches — the previous wave may
    // have run for several seconds (parallel × retries × timeout),
    // so a user who replaced the route mid-flight is waiting.
    if (isCancelled()) {
      return _cancelledResult(slots.whereType<_RoutedSegment>().toList());
    }
    final batchIdx = missIdx.skip(start).take(kOsrmBatchSize).toList();
    final results = await Future.wait(
      batchIdx.map(
        (i) => _routeOneSegment(
          segmentPairs[i][0], segmentPairs[i][1], profile, f, isCancelled),
      ),
    );
    for (var j = 0; j < batchIdx.length; j++) {
      final i = batchIdx[j];
      final seg = results[j];
      slots[i] = seg;
      // Cache successes only — a straight-line fallback from a
      // transient hiccup must re-try next pass, never stick.
      if (seg.ok) cache?._set(keys[i], seg);
    }
    if (isCancelled()) {
      return _cancelledResult(slots.whereType<_RoutedSegment>().toList());
    }
    if (start + kOsrmBatchSize < missIdx.length) {
      await Future<void>.delayed(kOsrmInterBatchDelay);
    }
  }

  final segments = [for (final s in slots) s!];
  final okSegments = segments.where((s) => s.ok).length;
  // No throw here even when every segment failed — the caller
  // (route_builder_screen) decides whether to surface a banner by
  // inspecting `okSegments` / `hadFallbacks`. Returning the
  // straight-line stitched polyline lets the user see + drag the
  // failing pins; throwing would leave them staring at an empty
  // map after a routing outage.

  // Stitch — drop the first point of each segment after the first
  // to avoid duplicating the shared waypoint between consecutive
  // segments.
  final out = <Waypoint>[];
  var totalDist = 0.0;
  for (var i = 0; i < segments.length; i++) {
    final seg = segments[i];
    if (i == 0) {
      out.addAll(seg.coordinates);
    } else if (seg.coordinates.isNotEmpty) {
      out.addAll(seg.coordinates.skip(1));
    }
    totalDist += seg.distanceMetres;
  }

  return OsrmRouteResult(
    coordinates: out,
    distanceMetres: totalDist,
    okSegments: okSegments,
    totalSegments: segments.length,
  );
}

/// Internal — one routed segment. `ok=false` means the segment fell
/// back to a straight line because OSRM couldn't route it within
/// the snap radius (or threw / timed out).
class _RoutedSegment {
  final List<Waypoint> coordinates;
  final double distanceMetres;
  final bool ok;
  const _RoutedSegment({
    required this.coordinates,
    required this.distanceMetres,
    required this.ok,
  });
}

/// Stable cache key for a routed segment. Order-sensitive (A→B is not
/// the same as B→A — OSRM can return asymmetric geometry on a one-way
/// street) and profile-scoped. Exact-coord match: a dragged waypoint
/// yields a different key → a re-fetch of just the adjacent segment.
/// Mirrors the web `segmentCacheKey` in `routes/segment_cache.ts`.
String segmentCacheKey(Waypoint from, Waypoint to, OsrmProfile profile) {
  return '${profile.path}|${from.lng},${from.lat}|${to.lng},${to.lat}';
}

/// Bounded, recency-ordered cache of successfully-routed segments. The
/// route builder holds one instance across the editing session so a
/// re-route after adding one waypoint fetches only the new segment
/// instead of re-running every prior one — keeping a long route
/// responsive on every pin placement. Mirrors the web `SegmentCache`.
///
/// Only *successful* segments are cached: a straight-line fallback from
/// a transient OSRM hiccup must re-try on the next pass, never stick.
class RouteSegmentCache {
  RouteSegmentCache({this.maxEntries = 2000});

  final int maxEntries;
  final _entries = <String, _RoutedSegment>{};

  _RoutedSegment? _get(String key) {
    final hit = _entries.remove(key);
    // Re-insert to mark most-recently-used (LinkedHashMap preserves
    // insertion order, so the first key is the oldest — see _set).
    if (hit != null) _entries[key] = hit;
    return hit;
  }

  void _set(String key, _RoutedSegment seg) {
    _entries
      ..remove(key)
      ..[key] = seg;
    if (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void clear() => _entries.clear();

  int get length => _entries.length;
}

/// Route a single segment from [from] → [to] with up to
/// [kOsrmRetries] retries on transient failure (timeout, network
/// blip, HTTP 5xx). Mirrors `apps/web/src/lib/components/
/// RouteBuilder.svelte:fetchSegment`. On final failure returns the
/// straight-line two-point segment with `ok=false` so the caller
/// can stitch it into the polyline + count the fallback.
///
/// **Permanent OSRM verdicts** (non-Ok code like `NoRoute` /
/// `NoSegment`, malformed routes payload) short-circuit on the
/// first attempt — retrying a "no road in range" response would
/// just keep returning the same answer. Only transient errors
/// (timeout, parse failure, fetcher throw) trigger the retry loop.
/// Build the "cancelled" sentinel result from however many segments
/// completed before the cancel landed. Caller checks `wasCancelled`
/// and ignores the rest — coordinates / distance are kept for
/// debugging only.
OsrmRouteResult _cancelledResult(List<_RoutedSegment> completed) {
  return OsrmRouteResult(
    coordinates: const [],
    distanceMetres: 0,
    okSegments: completed.where((s) => s.ok).length,
    totalSegments: completed.length,
    wasCancelled: true,
  );
}

Future<_RoutedSegment> _routeOneSegment(
  Waypoint from,
  Waypoint to,
  OsrmProfile profile,
  OsrmFetcher fetcher,
  OsrmCancellation isCancelled,
) async {
  final coords = '${from.lng},${from.lat};${to.lng},${to.lat}';
  final url = Uri.parse(
    '${_osrmBaseUrl()}/route/v1/${profile.path}/$coords'
    '?overview=full&geometries=geojson'
    '&radiuses=$kOsrmSnapRadiusM;$kOsrmSnapRadiusM',
  );
  for (var attempt = 0; attempt <= kOsrmRetries; attempt++) {
    // Cancellation check before each attempt — without this, a
    // hung retry loop holds the user's "Calculating route…"
    // spinner for ~25 s after they've already moved on to new pin
    // placements. Returning a straight-line fallback here is fine
    // because the caller will inspect `OsrmRouteResult.wasCancelled`
    // upstream and discard the whole result.
    if (isCancelled()) {
      return _straightSegment(from, to);
    }
    try {
      final body = await fetcher(url).timeout(kOsrmRouteTimeout);
      // The fetch can complete after the user moved on; bail
      // before bothering to parse.
      if (isCancelled()) {
        return _straightSegment(from, to);
      }
      final data = jsonDecode(body) as Map<String, dynamic>;
      if (data['code'] != 'Ok') {
        // Permanent — OSRM has already evaluated the request and
        // returned a definitive "no" (NoRoute / NoSegment / etc.).
        // Don't burn retries on a request that will keep saying no.
        return _straightSegment(from, to);
      }
      final routes = data['routes'] as List?;
      if (routes == null || routes.isEmpty) {
        return _straightSegment(from, to);
      }
      final route = routes.first as Map<String, dynamic>;
      final geometry = route['geometry'] as Map<String, dynamic>;
      final rawCoords = geometry['coordinates'] as List;
      if (rawCoords.length < 2) {
        return _straightSegment(from, to);
      }
      return _RoutedSegment(
        coordinates: [
          for (final pair in rawCoords)
            Waypoint(
              lat: ((pair as List)[1] as num).toDouble(),
              lng: (pair[0] as num).toDouble(),
            ),
        ],
        distanceMetres: (route['distance'] as num).toDouble(),
        ok: true,
      );
    } catch (_) {
      // Transient — timeout, network drop, parse failure. Worth a
      // retry with an exponential-ish backoff (500ms × attempt+1)
      // so a single hung request doesn't poison the rest of the
      // batch's parallel calls.
      if (attempt < kOsrmRetries) {
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (attempt + 1)),
        );
        continue;
      }
      return _straightSegment(from, to);
    }
  }
  // Unreachable — the loop always returns or throws inside the
  // attempt window. Defensive fallback in case the upper bound
  // ever changes.
  return _straightSegment(from, to);
}

/// Straight-line fallback for a failed segment. Distance is haversine
/// — same approximation the rest of the recorder + stats use.
_RoutedSegment _straightSegment(Waypoint from, Waypoint to) {
  return _RoutedSegment(
    coordinates: [from, to],
    distanceMetres: _haversineM(from, to),
    ok: false,
  );
}

/// Haversine great-circle distance in metres for the straight-line
/// fallback segment. 6,371,000 m mean Earth radius.
double _haversineM(Waypoint a, Waypoint b) {
  const r = 6_371_000.0;
  const deg = math.pi / 180;
  final dLat = (b.lat - a.lat) * deg;
  final dLng = (b.lng - a.lng) * deg;
  final lat1 = a.lat * deg;
  final lat2 = b.lat * deg;
  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) *
          math.sin(dLng / 2) * math.sin(dLng / 2);
  return r * 2 * math.asin(math.min(1, math.sqrt(h)));
}
