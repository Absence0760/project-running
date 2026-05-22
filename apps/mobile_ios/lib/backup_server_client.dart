import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// HTTP client for the Go service's `POST /v1/export?format=backup`
/// endpoint. Returns a signed-URL response that the caller streams
/// straight to disk — the device never buffers the whole archive.
///
/// Same Go service hosts the live spectator hub
/// (`POST /v1/live/{run_id}/push`), so the deploy reuses the
/// `LIVE_HUB_URL` env var as the shared base. Builds without that
/// env are treated as unconfigured; [BackupService] falls back to
/// the local streaming writer.
///
/// Test seam: pluggable [BackupHttpFetcher] callbacks so unit tests
/// can replay canned JSON + streamed bytes without sockets. Mirrors
/// the same pattern used by `live_hub_client.dart` and `routing.dart`.

/// Performs the `POST /v1/export` round-trip. Returns the parsed JSON
/// response body + the HTTP status code. Caller decides what's
/// success — the server returns 200 with `{url, count, format}` on
/// the happy path, JSON-encoded error bodies otherwise.
typedef BackupRequestFetcher = Future<({int statusCode, Map<String, dynamic> body})>
    Function(Uri url, String accessToken, Map<String, dynamic> requestBody);

/// Streams the signed-URL response body into [outputFile]. Returns
/// the number of bytes written. The default streams chunked from
/// dart:io's [HttpClient]; tests inject a synthetic byte source.
typedef BackupDownloadFetcher = Future<int> Function(
  Uri url,
  File outputFile,
);

Future<({int statusCode, Map<String, dynamic> body})>
    _defaultRequestFetcher(Uri url, String accessToken, Map<String, dynamic> body) async {
  final client = HttpClient();
  try {
    final req = await client.postUrl(url);
    req.headers.contentType = ContentType.json;
    req.headers.add('Authorization', 'Bearer $accessToken');
    req.write(jsonEncode(body));
    final res = await req.close();
    final raw = await res.transform(utf8.decoder).join();
    Map<String, dynamic> parsed;
    try {
      final decoded = jsonDecode(raw);
      parsed = decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'raw': raw};
    } catch (_) {
      parsed = <String, dynamic>{'raw': raw};
    }
    return (statusCode: res.statusCode, body: parsed);
  } finally {
    client.close(force: true);
  }
}

Future<int> _defaultDownloadFetcher(Uri url, File outputFile) async {
  final client = HttpClient();
  try {
    final req = await client.getUrl(url);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw HttpException('signed-url download returned ${res.statusCode}');
    }
    final sink = outputFile.openWrite();
    var bytes = 0;
    await for (final chunk in res) {
      bytes += chunk.length;
      sink.add(chunk);
    }
    await sink.flush();
    await sink.close();
    return bytes;
  } finally {
    client.close(force: true);
  }
}

/// Sentinel + thin wrapper around the Go service's `format=backup`
/// path. Production callers construct one with `baseUrl =
/// dotenv.env['LIVE_HUB_URL']` and the current Supabase access
/// token; tests inject the two fetcher callbacks.
class BackupServerClient {
  /// Base URL of the Go service (e.g. `https://live.threkir.com`).
  /// Same value as `LIVE_HUB_URL` — the service mounts both
  /// `/v1/live/*` (live hub) and `/v1/export` (data + backup
  /// export) on one mux.
  final String baseUrl;
  final BackupRequestFetcher requestFetcher;
  final BackupDownloadFetcher downloadFetcher;

  const BackupServerClient({
    required this.baseUrl,
    BackupRequestFetcher? requestFetcher,
    BackupDownloadFetcher? downloadFetcher,
  })  : requestFetcher = requestFetcher ?? _defaultRequestFetcher,
        downloadFetcher = downloadFetcher ?? _defaultDownloadFetcher;

  /// True when the Go-service base is non-empty. `BackupService`
  /// gates the server path on this — an unconfigured build falls
  /// back to the local writer.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// Run the full `POST /v1/export → GET signed URL → streamed write`
  /// pipeline. Returns the run count the server says it included
  /// (so the caller can warn "only 5 000 of your 10 000 runs were
  /// captured — use the local backup instead").
  ///
  /// Throws [BackupServerError] on any non-200 response or
  /// IO failure — the caller catches and falls back to local.
  Future<int> fetchBackupToFile({
    required String accessToken,
    required File outputFile,
  }) async {
    if (!isConfigured) {
      throw const BackupServerError('Go service base URL not configured');
    }
    if (accessToken.isEmpty) {
      throw const BackupServerError('Missing access token');
    }
    final trimmed =
        baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final exportUrl = Uri.parse('$trimmed/v1/export');
    final res = await requestFetcher(
      exportUrl,
      accessToken,
      <String, dynamic>{'format': 'backup'},
    );
    if (res.statusCode != 200) {
      throw BackupServerError(
        'export request failed (status ${res.statusCode}): ${res.body}',
      );
    }
    final signedUrl = res.body['url'];
    final count = res.body['count'];
    if (signedUrl is! String || signedUrl.isEmpty) {
      throw const BackupServerError('export response missing signed url');
    }
    await downloadFetcher(Uri.parse(signedUrl), outputFile);
    if (count is int) return count;
    if (count is num) return count.toInt();
    return 0;
  }
}

/// Thin wrapper so [BackupService.createBackup] can `catch
/// (BackupServerError)` distinctly from generic IO exceptions and
/// fall through to the local writer.
class BackupServerError implements Exception {
  final String message;
  const BackupServerError(this.message);
  @override
  String toString() => 'BackupServerError: $message';
}
