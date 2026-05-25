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
/// pin the AppBar place-search overlay indefinitely; the empty-list
/// fallback below already returns nothing on the timeout so the
/// search dropdown clears rather than spinning forever.
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

typedef GeocodingFetcher = Future<String> Function(Uri url);

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
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
/// Returns an empty list when:
/// - the query is shorter than 2 characters (the web matches this)
/// - the HTTP call fails for any reason
///
/// Provider precedence (mirrors `searchPlacesWithKey` on web):
///   1. MapTiler when [apiKey] is non-empty
///   2. Nominatim (OSM\'s free public geocoder) as fallback so a
///      Protomaps-only dev stack with no MAPTILER_KEY still has a
///      working search box. See `decisions.md § 68`.
///
/// The empty-on-error contract keeps the search box graceful: if
/// every provider fails the user sees no results rather than an
/// error toast on every keystroke.
Future<List<PlaceResult>> searchPlaces(
  String query, {
  required String apiKey,
  int limit = 5,
  GeocodingFetcher? fetcher,
}) async {
  final trimmed = query.trim();
  if (trimmed.length < 2) return const [];
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

Future<List<PlaceResult>> _searchViaMapTiler(
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
    if (features == null) return const [];
    return [
      for (final f in features)
        if (f is Map &&
            f['center'] is List &&
            (f['center'] as List).length >= 2)
          PlaceResult(
            name: (f['place_name'] ?? f['text'] ?? '').toString(),
            lng: ((f['center'] as List)[0] as num).toDouble(),
            lat: ((f['center'] as List)[1] as num).toDouble(),
          ),
    ];
  } catch (_) {
    return const [];
  }
}

Future<List<PlaceResult>> _searchViaNominatim(
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
    if (data is! List) return const [];
    final out = <PlaceResult>[];
    for (final f in data) {
      if (f is! Map) continue;
      final latRaw = f['lat'];
      final lngRaw = f['lon'];
      final lat = latRaw is String ? double.tryParse(latRaw) : null;
      final lng = lngRaw is String ? double.tryParse(lngRaw) : null;
      if (lat == null || lng == null) continue;
      out.add(PlaceResult(
        name: (f['display_name'] ??
                '${lat.toStringAsFixed(3)}, ${lng.toStringAsFixed(3)}')
            .toString(),
        lat: lat,
        lng: lng,
      ));
    }
    return out;
  } catch (_) {
    return const [];
  }
}

/// A geocoded place — the centroid the query resolved to, plus a
/// radius in metres derived from the bounding box. Mirrors web's
/// `GeocodedPlace` in `apps/web/src/lib/geocoding.ts`. Used by the
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
    final lng = (centerRaw[0] as num).toDouble();
    final lat = (centerRaw[1] as num).toDouble();
    final bboxRaw = top['bbox'];
    final radiusM = (bboxRaw is List && bboxRaw.length == 4)
        ? bboxRadius(
            [
              (bboxRaw[0] as num).toDouble(),
              (bboxRaw[1] as num).toDouble(),
              (bboxRaw[2] as num).toDouble(),
              (bboxRaw[3] as num).toDouble(),
            ],
            lng,
            lat,
          )
        // MapTiler occasionally returns features without a bbox (rare
        // — usually address-level POIs). Default to a small radius so
        // the centroid is still useful but doesn't sweep a continent.
        : 5000.0;
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
