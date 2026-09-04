import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// MapTiler geocoding helper — mirrors the web's `handleSearch` in
/// `apps/web/src/lib/components/RouteBuilder.svelte`. Returns up to
/// [limit] best-match places for a free-form query.
///
/// Pluggable fetcher (same pattern as `routing.dart` + `elevation.dart`)
/// so unit tests replay canned bodies. Production uses dart:io's
/// HttpClient — no new package dep.

const _kMapTilerBase = 'https://api.maptiler.com/geocoding';
const _kNominatimBase = 'https://nominatim.openstreetmap.org/search';

/// Ceiling on each MapTiler lookup. Without it a flaky network can
/// pin the AppBar place-search overlay indefinitely. A timeout resolves
/// to [PlaceSearchStatus.unavailable], so the dropdown says the search
/// failed rather than spinning forever OR claiming no such place.
const Duration kGeocodingTimeout = Duration(seconds: 5);

class PlaceResult {
  final String name;
  final double lat;
  final double lng;
  const PlaceResult({
    required this.name,
    required this.lat,
    required this.lng,
  });
}

/// Whether a geocoder's answer is a latitude at all.
///
/// The same contract the GPX importer applies to a coordinate out of a file
/// (`RouteParser._isUsableLat`), for the same two reasons. A non-finite
/// coordinate is not a place: `jsonEncode` refuses it outright, so it reaches
/// `set_discoverable_area` as an unreadable failure, and `LatLng` carries no
/// assertion of its own, so it reaches a map camera as a view that silently
/// stops rendering. And the range is not a heuristic — a latitude is ±90 by
/// definition, so a value outside it is a malformed answer, not a place.
///
/// BOTH providers need it. Nominatim serialises coordinates as STRINGS and
/// `double.tryParse('NaN')` returns NaN rather than null, so a null check does
/// not see it. MapTiler sends JSON numbers, which cannot spell NaN — but
/// `jsonDecode('1e400')` is `Infinity`, measured, so `as num` does not save
/// that branch either.
bool isUsableLatitude(double? v) => v != null && v.isFinite && v.abs() <= 90;

/// Longitude half of [isUsableLatitude]. Separate bound, same contract.
bool isUsableLongitude(double? v) => v != null && v.isFinite && v.abs() <= 180;

/// Why a search reports an outcome rather than a bare list: a provider
/// that is down, rate-limited, or timing out used to collapse into an
/// empty list, which every call site renders identically to "this place
/// does not exist" — and because each dropdown only opens on a non-empty
/// result set, a failed search produced NO feedback at all.
///
/// The web twin (`geocoding_math.ts`) carries a third `aborted` state
/// because its call sites pass an AbortSignal and must stay silent when
/// they supersede their own request. Here the debounce is a cancelled
/// `Timer`, so a superseded keystroke never reaches this layer at all
/// and there is nothing for a third state to describe.
enum PlaceSearchStatus { ok, unavailable }

class PlaceSearchOutcome {
  final PlaceSearchStatus status;
  final List<PlaceResult> results;
  const PlaceSearchOutcome.ok(this.results) : status = PlaceSearchStatus.ok;
  const PlaceSearchOutcome.unavailable()
      : status = PlaceSearchStatus.unavailable,
        results = const [];

  bool get isUnavailable => status == PlaceSearchStatus.unavailable;
}

typedef GeocodingFetcher = Future<String> Function(Uri url);

/// Nominatim rejects requests carrying a stock HTTP-library User-Agent
/// (dart:io's default looks like `Dart/x.y (dart:io)`) with HTTP 403 — its
/// usage policy requires a UA identifying the application. Set one so
/// the no-MapTiler-key Nominatim fallback returns results instead of
/// silently 403ing into an empty search dropdown. MapTiler ignores the
/// header, so it is safe to send on both providers.
const kGeocodingUserAgent = 'threkir-run-app/1.0 (privacy@threkir.com)';

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  client.userAgent = kGeocodingUserAgent;
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException('MapTiler ${res.statusCode}: $body', uri: url);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

/// Search for places matching [query]. Returns at most [limit] results.
///
/// Provider precedence (mirrors `searchPlacesWithKey` on web):
///   1. MapTiler when [apiKey] is non-empty
///   2. Nominatim (OSM\'s free public geocoder) as fallback so a
///      Protomaps-only dev stack with no MAPTILER_KEY still has a
///      working search box. See `decisions.md § 68`.
///
/// Never throws. A provider failure comes back as
/// [PlaceSearchStatus.unavailable], which the dropdown must render
/// differently from an `ok` with no results — the point is to stay off
/// an error toast on every keystroke WITHOUT telling the runner that a
/// reachable place does not exist.
Future<PlaceSearchOutcome> searchPlaces(
  String query, {
  required String apiKey,
  int limit = 5,
  GeocodingFetcher? fetcher,
}) async {
  final trimmed = query.trim();
  // Too short to search is an EMPTY result, not a failed one.
  if (trimmed.length < 2) return const PlaceSearchOutcome.ok([]);
  if (apiKey.isNotEmpty) {
    return _searchViaMapTiler(
      trimmed,
      apiKey: apiKey,
      limit: limit,
      fetcher: fetcher,
    );
  }
  return _searchViaNominatim(trimmed, limit: limit, fetcher: fetcher);
}

Future<PlaceSearchOutcome> _searchViaMapTiler(
  String trimmed, {
  required String apiKey,
  required int limit,
  GeocodingFetcher? fetcher,
}) async {
  final encoded = Uri.encodeComponent(trimmed);
  final url = Uri.parse(
    '$_kMapTilerBase/$encoded.json?key=$apiKey&limit=$limit',
  );
  try {
    final body = await (fetcher ?? _defaultFetcher)(url).timeout(kGeocodingTimeout);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final features = data['features'] as List?;
    // A 200 whose body carries no `features` array is a malformed
    // answer, not an answer of "no matches".
    if (features == null) return const PlaceSearchOutcome.unavailable();
    return PlaceSearchOutcome.ok([
      for (final f in features)
        if (f is Map &&
            f['center'] is List &&
            (f['center'] as List).length >= 2 &&
            (f['center'] as List)[0] is num &&
            (f['center'] as List)[1] is num &&
            isUsableLongitude(((f['center'] as List)[0] as num).toDouble()) &&
            isUsableLatitude(((f['center'] as List)[1] as num).toDouble()))
          PlaceResult(
            name: (f['place_name'] ?? f['text'] ?? '').toString(),
            lng: ((f['center'] as List)[0] as num).toDouble(),
            lat: ((f['center'] as List)[1] as num).toDouble(),
          ),
    ]);
  } catch (_) {
    // Covers the transport throw, the >=400 HttpException the default
    // fetcher raises, the timeout, and an unparseable body.
    return const PlaceSearchOutcome.unavailable();
  }
}

Future<PlaceSearchOutcome> _searchViaNominatim(
  String trimmed, {
  required int limit,
  GeocodingFetcher? fetcher,
}) async {
  // The `email` param signals to Nominatim that we read their usage
  // policy. Plain UA without it has been known to get denied. See
  // https://operations.osmfoundation.org/policies/nominatim/.
  // The address must be reachable so OSM can contact the operator on
  // abuse / takedown — see audit/third-party-data-flows (2026-05-25).
  final url = Uri.parse(
    '$_kNominatimBase?q=${Uri.encodeQueryComponent(trimmed)}'
    '&format=json&limit=$limit&addressdetails=0'
    '&email=privacy@threkir.com',
  );
  try {
    final body = await (fetcher ?? _defaultFetcher)(url).timeout(kGeocodingTimeout);
    final data = jsonDecode(body);
    // Nominatim answers a search with a JSON array; anything else is a
    // malformed answer, not an answer of "no matches".
    if (data is! List) return const PlaceSearchOutcome.unavailable();
    final out = <PlaceResult>[];
    for (final f in data) {
      if (f is! Map) continue;
      final latRaw = f['lat'];
      final lngRaw = f['lon'];
      final lat = latRaw is String ? double.tryParse(latRaw) : null;
      final lng = lngRaw is String ? double.tryParse(lngRaw) : null;
      if (lat == null ||
          lng == null ||
          !isUsableLatitude(lat) ||
          !isUsableLongitude(lng)) {
        continue;
      }
      out.add(PlaceResult(
        name: (f['display_name'] ??
                '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}')
            .toString(),
        lat: lat,
        lng: lng,
      ));
    }
    return PlaceSearchOutcome.ok(out);
  } catch (_) {
    // Covers the transport throw, the >=400 HttpException the default
    // fetcher raises (Nominatim answers an over-rate request with 429 —
    // exactly the case that must read as "search unavailable", never as
    // "no such place"), the timeout, and an unparseable body.
    return const PlaceSearchOutcome.unavailable();
  }
}

/// A geocoded place — the centroid the query resolved to, plus a
/// radius in metres derived from the bounding box. Mirrors web's
/// `GeocodedPlace` in `apps/web/src/lib/routes/geocoding.ts`. Used by the
/// region-aware club search so "Virginia" expands to a centroid +
/// ~470 km radius rather than just an ILIKE on the location label.
class GeocodedPlace {
  final String name;
  final double lng;
  final double lat;
  final double radiusM;
  final String? placeType;
  const GeocodedPlace({
    required this.name,
    required this.lng,
    required this.lat,
    required this.radiusM,
    required this.placeType,
  });
}

double haversineM(double lng1, double lat1, double lng2, double lat2) {
  const r = 6371000.0;
  double toRad(double d) => d * 3.141592653589793 / 180;
  final dLat = toRad(lat2 - lat1);
  final dLng = toRad(lng2 - lng1);
  final sinLat = sin(dLat / 2);
  final sinLng = sin(dLng / 2);
  final h = sinLat * sinLat +
      cos(toRad(lat1)) * cos(toRad(lat2)) * sinLng * sinLng;
  return r * 2 * atan2(sqrt(h), sqrt(1 - h));
}

/// Max distance from the bbox centroid to one of its four corners.
/// Mirrors web `bboxRadius`. For a country bbox this is hundreds of
/// km; for a street address it collapses to a few hundred metres.
double bboxRadius(List<double> bbox, double centerLng, double centerLat) {
  final w = bbox[0];
  final s = bbox[1];
  final e = bbox[2];
  final n = bbox[3];
  final corners = <List<double>>[
    [w, s],
    [w, n],
    [e, s],
    [e, n],
  ];
  var maxD = 0.0;
  for (final c in corners) {
    final d = haversineM(centerLng, centerLat, c[0], c[1]);
    if (d > maxD) maxD = d;
  }
  return maxD;
}

/// A bbox is usable whole or not at all. One unusable corner makes
/// [bboxRadius] a NaN, which compares false against every bound a caller
/// might check it with; and reading a corner through `as num` threw a
/// `TypeError` out into [geocodePlace]'s catch-all, which discarded a
/// perfectly usable centroid rather than falling back to the documented
/// default radius.
List<double>? _usableBbox(Object? raw) {
  if (raw is! List || raw.length != 4) return null;
  final w = raw[0];
  final s = raw[1];
  final e = raw[2];
  final n = raw[3];
  if (w is! num || s is! num || e is! num || n is! num) return null;
  final west = w.toDouble();
  final south = s.toDouble();
  final east = e.toDouble();
  final north = n.toDouble();
  if (!isUsableLongitude(west) ||
      !isUsableLatitude(south) ||
      !isUsableLongitude(east) ||
      !isUsableLatitude(north)) {
    return null;
  }
  return [west, south, east, north];
}

/// Geocode a free-text place query via MapTiler. Returns null when
/// the query is too short, MapTiler returns no features, or the key
/// isn't configured. Callers treat null as "fall back to the
/// text-only path", never as an error. Mirrors web's `geocodePlace`.
Future<GeocodedPlace?> geocodePlace(
  String query, {
  required String apiKey,
  GeocodingFetcher? fetcher,
}) async {
  final trimmed = query.trim();
  if (trimmed.length < 2) return null;
  if (apiKey.isEmpty) return null;
  final encoded = Uri.encodeComponent(trimmed);
  final url = Uri.parse('$_kMapTilerBase/$encoded.json?key=$apiKey&limit=1');
  try {
    final body = await (fetcher ?? _defaultFetcher)(url).timeout(kGeocodingTimeout);
    final data = jsonDecode(body) as Map<String, dynamic>;
    final features = data['features'] as List?;
    if (features == null || features.isEmpty) return null;
    final top = features.first;
    if (top is! Map) return null;
    final centerRaw = top['center'];
    if (centerRaw is! List || centerRaw.length < 2) return null;
    final lngRaw = centerRaw[0];
    final latRaw = centerRaw[1];
    if (lngRaw is! num || latRaw is! num) return null;
    final lng = lngRaw.toDouble();
    final lat = latRaw.toDouble();
    if (!isUsableLongitude(lng) || !isUsableLatitude(lat)) return null;
    final bbox = _usableBbox(top['bbox']);
    // MapTiler occasionally returns features without a bbox (rare —
    // usually address-level POIs), and an unusable one is treated the
    // same way: default to a small radius so the centroid is still
    // useful but doesn't sweep a continent.
    final radiusM = bbox == null ? 5000.0 : bboxRadius(bbox, lng, lat);
    final placeTypeRaw = top['place_type'];
    final placeType = (placeTypeRaw is List && placeTypeRaw.isNotEmpty)
        ? placeTypeRaw.first.toString()
        : null;
    return GeocodedPlace(
      name: (top['place_name'] ?? top['text'] ?? trimmed).toString(),
      lng: lng,
      lat: lat,
      radiusM: radiusM,
      placeType: placeType,
    );
  } catch (_) {
    return null;
  }
}
