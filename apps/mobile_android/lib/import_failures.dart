/// Structured failure recording for the bulk importers (Strava export zip,
/// Health Connect / Apple Health, CSV summary).
///
/// Every importer used to swallow the caught error and increment a bare
/// counter, so a five-year migration reported `47 failed` and nothing
/// else — no activity name, no reason, no way to tell a transient network
/// drop (re-run the import and it lands) from a corrupt archive member
/// (it never will). Re-running an import IS the retry, because every
/// importer dedupes against what already landed; what the runner was
/// missing is the information needed to decide whether re-running is
/// worth it.
///
/// `detail` deliberately carries only the log-safe `.code` / `.message`
/// fields of a Supabase/PostgREST error, never `.details` / `.hint` —
/// those echo row fragments.
///
/// Dart twin of `apps/web/src/lib/integrations/import_failures.ts` — same
/// buckets, same precedence, same caps, same CSV. Keep the two in lockstep;
/// the mirror suite is `test/import_failures_test.dart`.
library;

enum ImportFailureReason {
  network('network'),
  auth('auth'),
  rateLimited('rate_limited'),
  tooLarge('too_large'),
  unparseable('unparseable'),
  rejected('rejected'),
  unknown('unknown');

  const ImportFailureReason(this.wire);

  /// Stable identifier shared with web: the i18n key suffix and the CSV
  /// `Reason` column. Never the localized label.
  final String wire;
}

class ImportFailure {
  final String name;
  final String? startedAt;
  final ImportFailureReason reason;
  final String detail;

  const ImportFailure({
    required this.name,
    required this.startedAt,
    required this.reason,
    required this.detail,
  });
}

class ImportFailureLog {
  final List<ImportFailure> items = <ImportFailure>[];
  int truncated = 0;

  ImportFailureLog();

  bool get isEmpty => items.isEmpty && truncated == 0;
  bool get isNotEmpty => !isEmpty;

  /// Everything that failed, including what the cap refused to retain.
  int get total => items.length + truncated;
}

/// A pathological archive can fail on every one of tens of thousands of
/// members; cap what we hold in memory and report the overflow rather
/// than letting the failure list itself become the OOM.
const int kMaxRecordedImportFailures = 200;

const int _maxDetailChars = 200;

ImportFailureLog newImportFailureLog() => ImportFailureLog();

class ImportFailureClassification {
  final ImportFailureReason reason;
  final String detail;
  const ImportFailureClassification(this.reason, this.detail);
}

T? _prop<T>(Object error, dynamic Function(dynamic) get) {
  try {
    final v = get(error as dynamic);
    return v is T ? v : null;
  } catch (_) {
    return null;
  }
}

String _errorMessage(Object? err) {
  if (err == null) return '';
  if (err is String) return err;
  if (err is num || err is bool) return err.toString();
  if (err is Map) {
    final m = err['message'];
    return m is String ? m : '';
  }
  final m = _prop<String>(err, (e) => e.message);
  if (m != null) return m;
  // A Dart `Exception('boom')` exposes no `.message` getter at all, so its
  // `toString()` is the only readable text — web's `Error` always has one.
  // An object carrying neither reports nothing rather than rendering
  // `Instance of 'Foo'` at the runner.
  final s = err.toString();
  return s.startsWith("Instance of '") ? '' : s;
}

String _errorCode(Object? err) {
  if (err is Map) {
    final c = err['code'];
    if (c is String) return c;
    if (c is num) return c.toString();
    return '';
  }
  if (err == null || err is String || err is num || err is bool) return '';
  final c = _prop<Object>(err, (e) => e.code);
  if (c is String) return c;
  if (c is num) return c.toString();
  return '';
}

int? _errorStatus(Object? err) {
  if (err is Map) {
    final s = err['status'];
    return s is int ? s : null;
  }
  if (err == null || err is String || err is num || err is bool) return null;
  return _prop<int>(err, (e) => e.status);
}

String _tidyDetail(String code, String message) {
  final collapsed = message.replaceAll(RegExp(r'\s+'), ' ').trim();
  final prefixed = code.isNotEmpty && collapsed.isNotEmpty
      ? '$code: $collapsed'
      : (code.isNotEmpty ? code : collapsed);
  return prefixed.length > _maxDetailChars
      ? '${prefixed.substring(0, _maxDetailChars - 1)}…'
      : prefixed;
}

final _networkRe = RegExp(
    r'failed to fetch|networkerror|network error|load failed|fetch failed|err_internet',
    caseSensitive: false);
final _authRe = RegExp(
    r'not signed in|unauthoriz|unauthentic|jwt|invalid token|session (has )?expired',
    caseSensitive: false);
final _rateLimitRe =
    RegExp(r'too many requests|rate limit', caseSensitive: false);
final _tooLargeRe = RegExp(
    r'too large|maximum allowed size|exceeds the maximum|payload too large|quota',
    caseSensitive: false);
final _rateLimitTriggerRe =
    RegExp(r'rate limit exceeded', caseSensitive: false);
final _rejectedRe = RegExp(
    r'row-level security|violates|permission denied|forbidden',
    caseSensitive: false);
final _unparseableRe = RegExp(
    r'parse|malformed|corrupt|unsupported file format|no track|no fit file|invalid|not a valid',
    caseSensitive: false);

/// Bucket a thrown value into a reason the UI can explain and act on.
/// Order matters: an "invalid token" reads as auth, not as unparseable,
/// and a "payload too large" as too_large, not as rejected.
ImportFailureClassification classifyImportFailure(Object? err) {
  final message = _errorMessage(err);
  final code = _errorCode(err);
  final status = _errorStatus(err);
  final detail = _tidyDetail(code, message);

  if (status == 429) {
    return ImportFailureClassification(ImportFailureReason.rateLimited, detail);
  }
  if (status == 401 || status == 403) {
    return ImportFailureClassification(ImportFailureReason.auth, detail);
  }
  if (status == 413) {
    return ImportFailureClassification(ImportFailureReason.tooLarge, detail);
  }

  if (code == 'P0001' && _rateLimitTriggerRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.rateLimited, detail);
  }

  if (_networkRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.network, detail);
  }
  if (_authRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.auth, detail);
  }
  if (_rateLimitRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.rateLimited, detail);
  }
  if (_tooLargeRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.tooLarge, detail);
  }

  // Any remaining SQLSTATE / PGRST code means the server answered and
  // refused — a data-exception class like 22P02 ("invalid input syntax")
  // otherwise fell through to the `invalid` message pattern below and
  // reported a server rejection as an unreadable file. A code at all is
  // `rejected`.
  if (code.isNotEmpty) {
    return ImportFailureClassification(ImportFailureReason.rejected, detail);
  }

  if (_rejectedRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.rejected, detail);
  }
  if (_unparseableRe.hasMatch(message)) {
    return ImportFailureClassification(ImportFailureReason.unparseable, detail);
  }

  return ImportFailureClassification(ImportFailureReason.unknown, detail);
}

/// Append one failure, classifying the thrown value. Past the cap the
/// entry is counted in `truncated` instead of retained.
void recordImportFailure(
  ImportFailureLog log, {
  required String name,
  String? startedAt,
  required Object? error,
}) {
  if (log.items.length >= kMaxRecordedImportFailures) {
    log.truncated++;
    return;
  }
  final c = classifyImportFailure(error);
  log.items.add(ImportFailure(
    name: name.trim().isEmpty ? 'Unnamed activity' : name.trim(),
    startedAt: startedAt,
    reason: c.reason,
    detail: c.detail,
  ));
}

class ImportFailureGroup {
  final ImportFailureReason reason;
  final int count;
  const ImportFailureGroup(this.reason, this.count);
}

/// Reason tallies for the summary line, commonest first, then by reason
/// name so the order is stable across renders.
List<ImportFailureGroup> groupImportFailures(ImportFailureLog log) {
  final counts = <ImportFailureReason, int>{};
  for (final f in log.items) {
    counts[f.reason] = (counts[f.reason] ?? 0) + 1;
  }
  final out =
      counts.entries.map((e) => ImportFailureGroup(e.key, e.value)).toList();
  out.sort((a, b) {
    final byCount = b.count.compareTo(a.count);
    return byCount != 0 ? byCount : a.reason.wire.compareTo(b.reason.wire);
  });
  return out;
}

String _csvField(String value) => '"${value.replaceAll('"', '""')}"';

/// A downloadable report of what did not import. Column headers are
/// English identifiers, not localized copy — the file is a data artefact
/// a runner pastes into a spreadsheet or a support thread, and a locale
/// that renamed the columns would make two reports unmergeable.
String importFailureReportCsv(ImportFailureLog log) {
  final lines = <String>['Activity,Started,Reason,Detail'];
  for (final f in log.items) {
    lines.add([
      _csvField(f.name),
      _csvField(f.startedAt ?? ''),
      _csvField(f.reason.wire),
      _csvField(f.detail),
    ].join(','));
  }
  if (log.truncated > 0) {
    lines.add([
      _csvField('(${log.truncated} further failures not recorded)'),
      _csvField(''),
      _csvField('truncated'),
      _csvField('recording cap $kMaxRecordedImportFailures reached'),
    ].join(','));
  }
  return lines.join('\n');
}
