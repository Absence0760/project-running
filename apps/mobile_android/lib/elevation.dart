import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart' show Waypoint;

/// Dart port of `apps/web/src/lib/elevation.ts`. Fetches elevation
/// from the public Open-Meteo Elevation API (no API key required) and
/// derives total elevation gain.
///
/// Pluggable [ElevationFetcher] mirrors the OSRM fetcher seam in
/// `routing.dart`: production uses dart:io's HttpClient by default;
/// tests inject a stubbed Future<String> Function(Uri).

const _kOpenMeteoBase = 'https://api.open-meteo.com/v1/elevation';

/// Max points per API request — matches the web side's 100-point
/// batch (Open-Meteo's documented limit).
const int kElevationBatchSize = 100;

/// Per-batch ceiling on the elevation fetch. The route-builder
/// iteration calls `fetchElevations` once per successful generation;
/// without a client-side timeout an Open-Meteo outage pins the whole
/// iteration's Future and the "Calculating route…" spinner never
/// resolves. Mirrors the 8s `AbortSignal.timeout` on the web port
/// (`apps/web/src/lib/elevation.ts`).
const Duration kElevationFetchTimeout = Duration(seconds: 8);

typedef ElevationFetcher = Future<String> Function(Uri url);

Future<String> _defaultFetcher(Uri url) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode >= 400) {
      throw HttpException('Elevation ${res.statusCode}: $body', uri: url);
    }
    return body;
  } finally {
    client.close(force: true);
  }
}

/// Fetch elevation in metres for each [coordinate]. Returns a list of
/// the same length. On any error (network failure, malformed body,
/// non-200), the corresponding batch falls back to all-zero — the
/// route can still save without elevation data. Mirrors web's
/// fall-through behaviour at L4 (best-effort).
Future<List<double>> fetchElevations(
  List<Waypoint> coordinates, {
  ElevationFetcher? fetcher,
}) async {
  if (coordinates.isEmpty) return const [];
  final out = <double>[];
  for (var i = 0; i < coordinates.length; i += kElevationBatchSize) {
    final batch = coordinates.sublist(
      i,
      i + kElevationBatchSize > coordinates.length
          ? coordinates.length
          : i + kElevationBatchSize,
    );
    final lats = batch.map((w) => w.lat).join(',');
    final lngs = batch.map((w) => w.lng).join(',');
    final url = Uri.parse('$_kOpenMeteoBase?latitude=$lats&longitude=$lngs');
    try {
      // .timeout() throws TimeoutException on expiry; the catch below
      // swallows that the same way it does HTTP / parse failures, so
      // the route still saves with a zero-elevation profile rather
      // than hanging the UI on a slow / unreachable Open-Meteo.
      final body = await (fetcher ?? _defaultFetcher)(url)
          .timeout(kElevationFetchTimeout);
      final data = jsonDecode(body) as Map<String, dynamic>;
      final elevations = data['elevation'] as List?;
      if (elevations == null || elevations.length != batch.length) {
        out.addAll(List<double>.filled(batch.length, 0));
      } else {
        out.addAll(elevations.map((e) => (e as num).toDouble()));
      }
    } catch (_) {
      out.addAll(List<double>.filled(batch.length, 0));
    }
  }
  return out;
}

/// Total elevation gain in metres. Sums every positive delta between
/// consecutive samples — same definition as the web helper and the
/// `RunStats` gain pipeline.
double calculateElevationGain(List<double> elevations) {
  if (elevations.length < 2) return 0;
  var gain = 0.0;
  for (var i = 1; i < elevations.length; i++) {
    final diff = elevations[i] - elevations[i - 1];
    if (diff > 0) gain += diff;
  }
  return gain;
}

/// Down-sample a polyline so we don't burn an elevation lookup on
/// every OSRM point (a 5 km road-snap can yield 800+ points; the API
/// limit is 100 per batch and we want a single round-trip). Returns
/// at most [maxPoints] coordinates evenly spaced along the input. The
/// shape mirrors the web's `sampleCoordinates`.
List<Waypoint> sampleCoordinates(
  List<Waypoint> coordinates, {
  int maxPoints = kElevationBatchSize,
}) {
  if (coordinates.length <= maxPoints) return coordinates;
  final step = (coordinates.length - 1) / (maxPoints - 1);
  final out = <Waypoint>[];
  for (var i = 0; i < maxPoints; i++) {
    final idx = (i * step).round();
    out.add(coordinates[idx]);
  }
  return out;
}
