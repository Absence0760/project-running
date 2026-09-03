/// The queued GDPR Art 20 export rail, client half.
///
/// Twin of the job half of web's `lib/backup/cloud_export_helpers.ts`
/// (decisions.md § 717 / § 724). Both clients read the same two
/// endpoints on the Go service — `POST /v1/export/jobs` enqueues and
/// answers with a job id, `GET /v1/export/jobs/latest` reports the
/// outcome and mints the signed URL at read time — so the two must
/// agree about what every status token means and, more importantly,
/// about what an answer they cannot read means.
///
/// The whole point of the queued rail is that nothing is held open for
/// the build, so the phone may be locked, backgrounded or killed between
/// asking and finishing. Nothing about the job is persisted on the
/// device: the status endpoint answers for the subject's LATEST export,
/// and the one-in-flight unique index is what makes that unambiguous. A
/// job id written to disk would be a second source of truth that a
/// reinstall loses while the server still holds the archive.
library;

/// What the status endpoint can say.
///
/// `none` is a subject who has never asked. `stalled` is a row nothing
/// has touched for longer than the worker's whole retry budget — the
/// server's way of saying the worker building it is gone — and is
/// derived at read time rather than written to the row.
enum ExportJobStatus { none, queued, running, ready, failed, expired, stalled }

const Map<String, ExportJobStatus> _statusTokens = <String, ExportJobStatus>{
  'none': ExportJobStatus.none,
  'queued': ExportJobStatus.queued,
  'running': ExportJobStatus.running,
  'ready': ExportJobStatus.ready,
  'failed': ExportJobStatus.failed,
  'expired': ExportJobStatus.expired,
  'stalled': ExportJobStatus.stalled,
};

/// One export request as the client understands it.
class ExportJob {
  final ExportJobStatus status;
  final String? jobId;
  final String? format;
  final String? requestedAt;

  /// The signed download URL, present only on `ready` — and only for as
  /// long as this read. It is minted per status read, never stored, so a
  /// surface that keeps one around is holding a link that expires under
  /// the reader.
  final String? url;
  final int? expiresInS;
  final int? count;
  final int? total;
  final bool? complete;
  final String? errorCode;

  const ExportJob({
    required this.status,
    this.jobId,
    this.format,
    this.requestedAt,
    this.url,
    this.expiresInS,
    this.count,
    this.total,
    this.complete,
    this.errorCode,
  });

  static const ExportJob none = ExportJob(status: ExportJobStatus.none);
}

/// How short the finished archive is of the account, or null when it is
/// whole.
class ExportShortfall {
  final int count;
  final int total;
  const ExportShortfall(this.count, this.total);
}

/// Normalise a status- or enqueue-endpoint body into an [ExportJob].
///
/// Fail-closed in three directions, and each matters on a phone. A
/// status this build does not recognise becomes `failed` carrying the
/// raw token: a client that keeps polling a status it cannot interpret
/// polls until the battery dies, and one that guesses `ready` offers a
/// download it has no URL for. A `ready` job that arrived without a URL
/// is not offerable either, so it is reported as a failure rather than
/// rendered as a dead button. And a `format` this build does not know is
/// dropped rather than carried: the field names the archive the caller
/// asked for, and a token neither client can interpret is not a name —
/// the status is unaffected, because an unreadable label is no reason to
/// refuse an archive that built.
ExportJob exportJobFromResponse(Object? raw) {
  if (raw is! Map) {
    return const ExportJob(
      status: ExportJobStatus.failed,
      errorCode: 'unreadable_response',
    );
  }
  final rawStatus = raw['status'];
  final token = rawStatus is String ? rawStatus : '';
  final status = _statusTokens[token];
  if (status == null) {
    return ExportJob(
      status: ExportJobStatus.failed,
      errorCode: token.isEmpty ? 'unknown_status' : token,
    );
  }
  final url = _str(raw['url']);
  if (status == ExportJobStatus.ready && url == null) {
    return const ExportJob(
      status: ExportJobStatus.failed,
      errorCode: 'no_url',
    );
  }
  return ExportJob(
    status: status,
    jobId: _str(raw['job_id']),
    format: _knownFormat(raw['format']),
    requestedAt: _str(raw['requested_at']),
    url: url,
    expiresInS: _int(raw['expires_in']),
    count: _int(raw['count']),
    total: _int(raw['total']),
    complete: raw['complete'] is bool ? raw['complete'] as bool : null,
    errorCode: _str(raw['error_code']),
  );
}

/// True while the build is still in progress and the client should keep
/// asking. Every other status is terminal — including `none`, which is
/// what a subject who has never exported sees.
bool isExportJobActive(ExportJobStatus status) =>
    status == ExportJobStatus.queued || status == ExportJobStatus.running;

const int kExportPollMinMs = 2000;
const int kExportPollMaxMs = 15000;

/// How long to wait before the next status read. Doubles every two
/// attempts up to a cap: a deep-history archive can take minutes, and a
/// fixed 2-second poll would spend hundreds of requests — and a phone's
/// radio — waiting for it, while a fixed 15 would make the common small
/// export feel slow.
int exportPollDelayMs(int attempt) {
  if (attempt < 0) return kExportPollMinMs;
  final steps = attempt ~/ 2;
  // 2^steps overflows nothing in Dart, but the multiply is still capped
  // below rather than after, so a caller that never stops incrementing
  // cannot walk the delay into an absurd number before the min() sees it.
  if (steps >= 16) return kExportPollMaxMs;
  final ms = kExportPollMinMs * (1 << steps);
  return ms > kExportPollMaxMs ? kExportPollMaxMs : ms;
}

/// What the UI must disclose about a finished export, or null when the
/// archive is whole.
///
/// Only an explicit `complete: false` claims a shortfall: a body without
/// the field (an older deployment) is not evidence of truncation, and
/// warning on every export would be its own dishonesty. `total` is
/// floored at `count` so a malformed pair can never read "12 of 3".
ExportShortfall? exportJobShortfall(ExportJob job) {
  if (job.complete != false) return null;
  final count = job.count ?? 0;
  final total = job.total ?? count;
  return ExportShortfall(count, total > count ? total : count);
}

/// Absolute URL of the queued rail's enqueue endpoint. Strips trailing
/// slashes so a paste-in `https://live.threkir.com/` still joins with a
/// single slash.
String buildExportJobsUrl(String base) => '${_trimEnd(base)}/v1/export/jobs';

/// Absolute URL of the queued rail's status endpoint. It answers for the
/// subject's LATEST export rather than by id, so a client that was
/// killed mid-build finds its way back with nothing stored locally.
String buildExportJobStatusUrl(String base) =>
    '${_trimEnd(base)}/v1/export/jobs/latest';

String _trimEnd(String base) {
  var end = base.length;
  while (end > 0 && base[end - 1] == '/') {
    end--;
  }
  return base.substring(0, end);
}

const List<String> _knownFormats = <String>['csv', 'gpx', 'backup'];

String? _knownFormat(Object? value) {
  final token = _str(value);
  return token != null && _knownFormats.contains(token) ? token : null;
}

String? _str(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

int? _int(Object? value) {
  if (value is int) return value;
  if (value is num) {
    if (value.isNaN || value.isInfinite) return null;
    return value.toInt();
  }
  return null;
}
