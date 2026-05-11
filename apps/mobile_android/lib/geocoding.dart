import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// MapTiler geocoding helper — mirrors the web's `handleSearch` in
/// `apps/web/src/lib/components/RouteBuilder.svelte`. Returns up to
/// [limit] best-match places for a free-form query.
///
/// Pluggable fetcher (same pattern as `routing.dart` + `elevation.dart`)
/// so unit tests replay canned bodies. Production uses dart:io's
/// HttpClient — no new package dep.

const _kMapTilerBase = 'https://api.maptiler.com/geocoding';

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
/// - the API key is missing
/// - the HTTP call fails for any reason
///
/// The empty-on-error contract keeps the search box graceful: if
/// MapTiler is down or unconfigured, the user sees no results rather
/// than an error toast on every keystroke.
Future<List<PlaceResult>> searchPlaces(
  String query, {
  required String apiKey,
  int limit = 5,
  GeocodingFetcher? fetcher,
}) async {
  if (query.trim().length < 2) return const [];
  if (apiKey.isEmpty) return const [];
  final encoded = Uri.encodeComponent(query.trim());
  final url = Uri.parse(
    '$_kMapTilerBase/$encoded.json?key=$apiKey&limit=$limit',
  );
  try {
    final body = await (fetcher ?? _defaultFetcher)(url);
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
