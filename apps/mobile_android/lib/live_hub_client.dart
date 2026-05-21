import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// HTTP client for the Go live-hub's push endpoint
/// (`POST /v1/live/{run_id}/push`). When the deploy sets
/// `LIVE_HUB_URL` in `dotenv.env`, [LiveBroadcaster] swaps from the
/// Supabase `live_run_pings` insert path to this — keeping live
/// spectator updates off Postgres + Realtime.
///
/// Test seam: pass a [HubFetcher] callback to inject canned responses
/// in unit tests. The default fetcher uses dart:io's [HttpClient] —
/// no new package dependency, matches the pattern used by
/// `routing.dart` / `elevation.dart` / `geocoding.dart`.
typedef HubFetcher = Future<int> Function(
  Uri url,
  Map<String, dynamic> body,
);

Future<int> _defaultFetcher(Uri url, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode(body));
    final res = await req.close();
    // Drain so the connection can be reused.
    await res.drain<void>(null);
    return res.statusCode;
  } finally {
    client.close(force: true);
  }
}

class LiveHubClient {
  /// Base URL of the Go live hub — e.g. `https://live.threkir.com`.
  /// Pings POST to `{baseUrl}/v1/live/{run_id}/push`.
  final String baseUrl;

  /// Optional fetcher override for tests.
  final HubFetcher? fetcher;

  const LiveHubClient({required this.baseUrl, this.fetcher});

  /// True when `baseUrl` is non-empty. The broadcaster gates on this:
  /// an unconfigured build (no `LIVE_HUB_URL` in dotenv) falls back
  /// to the Supabase insert path. Mirrors the
  /// `isRevenueCatConfigured` / `isStravaConfigured` patterns.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// POST one ping to the hub. Returns the HTTP status code. Errors
  /// bubble — the caller (`LiveBroadcaster.pushPing`) swallows them
  /// per the L4-best-effort layering contract.
  Future<int> pushPing({
    required String runId,
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
    double? ele,
  }) async {
    final trimmed = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final url = Uri.parse(
      '$trimmed/v1/live/${Uri.encodeComponent(runId)}/push',
    );
    final body = <String, dynamic>{
      'lat': lat,
      'lng': lng,
      if (distanceM != null) 'distance_m': distanceM,
      if (elapsedS != null) 'elapsed_s': elapsedS,
      if (bpm != null) 'bpm': bpm,
      if (ele != null) 'ele': ele,
      'sent_at_ms': DateTime.now().millisecondsSinceEpoch,
    };
    return (fetcher ?? _defaultFetcher)(url, body);
  }
}
