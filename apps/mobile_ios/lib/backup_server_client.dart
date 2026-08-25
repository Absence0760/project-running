import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'export_job.dart';

/// HTTP transport for the Go service's QUEUED Art 20 export rail
/// (decisions.md § 717 / § 724): `POST /v1/export/jobs` enqueues and
/// answers at once with a job id, `GET /v1/export/jobs/latest` reports
/// the outcome and mints the signed URL at read time.
///
/// The synchronous `POST /v1/export` this client used to call is gone.
/// It held the connection open for the whole build, which on a phone is
/// the normal case for failure rather than the edge case — the screen
/// goes off, the OS suspends the app, the socket dies, and an export
/// that would have finished is lost. Nothing is held open now, so the
/// phone may be locked or killed between asking and finishing.
///
/// Same Go service hosts the live spectator hub
/// (`POST /v1/live/{run_id}/push`), so the deploy reuses the
/// `LIVE_HUB_URL` env var as the shared base. Builds without that env
/// are treated as unconfigured, and the export surface says so rather
/// than silently handing over the narrower on-device archive.
///
/// Test seam: pluggable fetcher callbacks so unit tests can replay
/// canned JSON + streamed bytes without sockets. Mirrors the same
/// pattern used by `live_hub_client.dart` and `routing.dart`.

/// One JSON round-trip against the export endpoints. `retryAfter` is
/// the header verbatim — the caller decides whether it is worth
/// showing, because a 429 is the one failure the subject can act on.
class ExportHttpResponse {
  final int statusCode;
  final Map<String, dynamic> body;
  final String? retryAfter;
  const ExportHttpResponse({
    required this.statusCode,
    required this.body,
    this.retryAfter,
  });
}

/// Performs one request against an export endpoint. `requestBody` is
/// null for the GET.
typedef BackupRequestFetcher = Future<ExportHttpResponse> Function(
  Uri url,
  String method,
  String accessToken,
  Map<String, dynamic>? requestBody,
);

/// Streams the signed-URL response body into [outputFile]. Returns
/// the number of bytes written. The default streams chunked from
/// dart:io's [HttpClient]; tests inject a synthetic byte source.
typedef BackupDownloadFetcher = Future<int> Function(
  Uri url,
  File outputFile,
);

Future<ExportHttpResponse> _defaultRequestFetcher(
  Uri url,
  String method,
  String accessToken,
  Map<String, dynamic>? body,
) async {
  final client = HttpClient();
  try {
    final req = await client.openUrl(method, url);
    req.headers.add('Authorization', 'Bearer $accessToken');
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
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
    return ExportHttpResponse(
      statusCode: res.statusCode,
      body: parsed,
      retryAfter: res.headers.value('retry-after'),
    );
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

/// Thin wrapper around the Go service's queued export rail. Production
/// callers construct one with `baseUrl = dotenv.env['LIVE_HUB_URL']`
/// and hand it the current Supabase access token per call; tests inject
/// the two fetcher callbacks.
class BackupServerClient {
  /// Base URL of the Go service (e.g. `https://live.threkir.com`).
  /// Same value as `LIVE_HUB_URL` — the service mounts both
  /// `/v1/live/*` (live hub) and `/v1/export/jobs*` (Art 20 export) on
  /// one mux.
  final String baseUrl;
  final BackupRequestFetcher requestFetcher;
  final BackupDownloadFetcher downloadFetcher;

  const BackupServerClient({
    required this.baseUrl,
    BackupRequestFetcher? requestFetcher,
    BackupDownloadFetcher? downloadFetcher,
  })  : requestFetcher = requestFetcher ?? _defaultRequestFetcher,
        downloadFetcher = downloadFetcher ?? _defaultDownloadFetcher;

  /// True when the Go-service base is non-empty. The export surface
  /// gates the server rail on this and DISCLOSES when it is false — an
  /// unconfigured build cannot quietly hand over the on-device archive
  /// as if it were the complete one.
  bool get isConfigured => baseUrl.isNotEmpty;

  /// Ask the server to build an archive. Returns as soon as the job is
  /// queued: nothing here waits for the build, which is the entire
  /// point of the rail.
  ///
  /// Throws [BackupServerError] on any non-2xx — the caller surfaces it
  /// rather than swallowing it, because a failure the subject is never
  /// told about is a data-rights request that silently did not happen.
  Future<ExportJob> enqueueExport({
    required String accessToken,
    String format = 'backup',
  }) async {
    _requireConfigured(accessToken);
    final res = await requestFetcher(
      Uri.parse(buildExportJobsUrl(baseUrl)),
      'POST',
      accessToken,
      <String, dynamic>{'format': format},
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFor('export request failed', res);
    }
    return exportJobFromResponse(res.body);
  }

  /// Read the state of the subject's most recent export, minting a
  /// fresh signed URL when one is ready.
  ///
  /// Answers for the LATEST export rather than by id, so an app that
  /// was killed mid-build finds its way back with nothing stored on the
  /// device — which is what makes the resume path real rather than a
  /// promise about a job id a reinstall would have lost.
  Future<ExportJob> fetchLatestExportJob({required String accessToken}) async {
    _requireConfigured(accessToken);
    final res = await requestFetcher(
      Uri.parse(buildExportJobStatusUrl(baseUrl)),
      'GET',
      accessToken,
      null,
    );
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw _errorFor('export status read failed', res);
    }
    return exportJobFromResponse(res.body);
  }

  /// Stream a ready export's signed URL straight to disk. The device
  /// never buffers the whole archive.
  Future<int> downloadToFile({
    required Uri url,
    required File outputFile,
  }) =>
      downloadFetcher(url, outputFile);

  void _requireConfigured(String accessToken) {
    if (!isConfigured) {
      throw const BackupServerError('Go service base URL not configured');
    }
    if (accessToken.isEmpty) {
      throw const BackupServerError('Missing access token');
    }
  }

  BackupServerError _errorFor(String what, ExportHttpResponse res) {
    return BackupServerError(
      '$what (status ${res.statusCode}): ${res.body}',
      statusCode: res.statusCode,
      retryAfterSeconds: _retryAfterSeconds(res.retryAfter),
    );
  }
}

/// The `Retry-After` header as whole seconds, or null when it is absent
/// or is the HTTP-date form. The date form is legal and the server does
/// not send it; guessing at a parse we would then show to a subject is
/// worse than saying nothing about how long to wait.
int? _retryAfterSeconds(String? header) {
  if (header == null) return null;
  final n = int.tryParse(header.trim());
  if (n == null || n < 0) return null;
  return n;
}

/// Thin wrapper so callers can `catch (BackupServerError)` distinctly
/// from generic IO exceptions. Carries the status so the one failure a
/// subject can act on — a 429 — can be named as such.
class BackupServerError implements Exception {
  final String message;
  final int? statusCode;
  final int? retryAfterSeconds;
  const BackupServerError(
    this.message, {
    this.statusCode,
    this.retryAfterSeconds,
  });

  /// The export was refused by the per-hour quota, not by an outage.
  bool get isRateLimited => statusCode == 429;

  @override
  String toString() => 'BackupServerError: $message';
}
