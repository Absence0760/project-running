import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter/foundation.dart';

import 'import_failures.dart';
import 'imported_run_id.dart';

/// One-shot bulk-import path for CSV exports. Accepts both shapes the
/// app produces today:
///
/// * **5-column mobile/web export** — `date,distance_m,duration_s,
///   pace_s_per_km,source`. Settings → "Export runs as CSV" on either
///   platform. Lossy summary (no track, no metadata).
/// * **17-column backend `/export-data` GDPR export** — see
///   `apps/backend/supabase/functions/export-data/index.ts`. Carries
///   `id`, `started_at`, `external_id`, full `metadata` JSON, etc.
///
/// Output is a list of `Run` objects with empty tracks, ready to feed
/// straight into `LocalRunStore.save` — same shape `add_run_screen`
/// produces for a manual entry. Re-importing the same CSV is
/// idempotent: each row gets a stable `external_id` of
/// `csv:<iso>-<distance>-<duration>` (or the original `external_id`
/// column when present in the 17-column form), so a re-import collides
/// on the `runs.external_id` unique index server-side and on
/// `LocalRunStore.save`'s id-replace semantics locally.
///
/// **Lossy by design** — CSV is a summary format, the GPS track is
/// not recoverable. To round-trip runs with their tracks intact, use
/// the Full backup ZIP path (`BackupService`). See
/// [decisions.md § 65](../../docs/architecture/decisions.md#65-csv-import-is-a-summary-path-not-a-replacement-for-the-backup-zip).
class CsvRunImporter {
  static CsvImportResult parse(String content) {
    final lines = const LineSplitter().convert(content);
    if (lines.isEmpty) {
      return CsvImportResult.empty();
    }
    final headerCells = _parseRow(lines.first);
    if (headerCells.isEmpty) return CsvImportResult.empty();

    final byName = <String, int>{};
    for (var i = 0; i < headerCells.length; i++) {
      byName[headerCells[i].toLowerCase().trim()] = i;
    }

    int? col(List<String> names) {
      for (final n in names) {
        final idx = byName[n];
        if (idx != null) return idx;
      }
      return null;
    }

    final startedAtIdx = col(const ['started_at', 'date', 'start_time']);
    final distanceIdx = col(const ['distance_m', 'distance']);
    final durationIdx = col(const ['duration_s', 'duration']);
    if (startedAtIdx == null || distanceIdx == null || durationIdx == null) {
      final headerFailure = newImportFailureLog();
      recordImportFailure(
        headerFailure,
        name: 'CSV header',
        error: 'Malformed CSV header: missing required columns '
            '(need started_at / date, distance_m, duration_s).',
      );
      return CsvImportResult(runs: const [], failures: headerFailure);
    }
    final sourceIdx = col(const ['source']);
    final activityIdx = col(const ['activity_type']);
    final titleIdx = col(const ['title']);
    final externalIdx = col(const ['external_id']);
    final idIdx = col(const ['id']);
    final routeIdx = col(const ['route_id']);
    final metadataIdx = col(const ['metadata']);

    final runs = <Run>[];
    final failures = newImportFailureLog();
    for (var i = 1; i < lines.length; i++) {
      final raw = lines[i].trim();
      if (raw.isEmpty) continue;
      try {
        final cells = _parseRow(lines[i]);
        // Every required-column index must be in-range; otherwise the
        // row is shorter than the header expects.
        final minLen = [startedAtIdx, distanceIdx, durationIdx]
            .reduce((a, b) => a > b ? a : b);
        if (cells.length <= minLen) {
          recordImportFailure(failures,
              name: 'Row ${i + 1}',
              error: 'Malformed row: fewer columns than the header.');
          continue;
        }
        final startedAt = DateTime.tryParse(cells[startedAtIdx]);
        if (startedAt == null) {
          recordImportFailure(failures,
              name: 'Row ${i + 1}',
              error: 'Could not parse the date "${cells[startedAtIdx]}".');
          continue;
        }
        final distance = double.tryParse(cells[distanceIdx]);
        final durationSeconds = int.tryParse(cells[durationIdx]);
        if (distance == null || durationSeconds == null) {
          recordImportFailure(failures,
              name: 'Row ${i + 1}',
              startedAt: startedAt.toUtc().toIso8601String(),
              error: 'Could not parse the distance / duration.');
          continue;
        }

        final source = sourceIdx != null && sourceIdx < cells.length
            ? _parseSource(cells[sourceIdx])
            : RunSource.app;

        Map<String, dynamic> metadata = <String, dynamic>{};
        // 17-column form may carry the full metadata JSON in one column.
        if (metadataIdx != null && metadataIdx < cells.length) {
          final raw = cells[metadataIdx];
          if (raw.isNotEmpty) {
            try {
              final decoded = jsonDecode(raw);
              if (decoded is Map) {
                metadata = Map<String, dynamic>.from(decoded);
              }
            } catch (e) {
              // Bad metadata JSON shouldn't sink the row — report the
              // parse error itself and fall through to whatever the
              // per-column fields give us.
              debugPrint('CSV row ${i + 1}: metadata column not valid JSON: $e');
              recordImportFailure(failures,
                  name: 'Row ${i + 1}',
                  startedAt: startedAt.toUtc().toIso8601String(),
                  // The decoder's own message ("Unexpected character") does
                  // not say what was being decoded, and reaches the runner
                  // as an unknown error rather than an unreadable file.
                  error: 'Malformed metadata JSON, ignored: $e');
            }
          }
        }
        if (activityIdx != null && activityIdx < cells.length) {
          final v = cells[activityIdx].trim();
          if (v.isNotEmpty) metadata[MetadataKeys.activityType] = v;
        }
        if (titleIdx != null && titleIdx < cells.length) {
          final v = cells[titleIdx].trim();
          if (v.isNotEmpty) metadata.putIfAbsent(MetadataKeys.title, () => v);
        }
        // CHECK constraint on the runs table requires activity_type —
        // see runs_metadata_activity_type_check. Default to 'run' so
        // a 5-column CSV (no activity_type) inserts cleanly.
        metadata.putIfAbsent(MetadataKeys.activityType, () => 'run');
        metadata[MetadataKeys.importedFrom] = 'csv';
        metadata[MetadataKeys.importedAt] = DateTime.now().toUtc().toIso8601String();

        // External id: prefer whatever the 17-column form carries
        // (server-assigned `csv:` or `strava:` etc.) so a re-import
        // dedupes against the original row. Fall back to a stable
        // synthetic for the 5-column form.
        String externalId;
        if (externalIdx != null &&
            externalIdx < cells.length &&
            cells[externalIdx].trim().isNotEmpty) {
          externalId = cells[externalIdx].trim();
        } else {
          externalId = _syntheticExternalId(
            startedAt: startedAt,
            distanceM: distance,
            durationS: durationSeconds,
          );
        }

        // Stable id from the 17-column form is welcome (round-trip
        // preserves run-detail links); otherwise derive a deterministic id
        // from the stable external_id so a re-import maps to the same local
        // run and the server upsert never rewrites the primary key (#361).
        String runId;
        if (idIdx != null &&
            idIdx < cells.length &&
            cells[idIdx].trim().isNotEmpty) {
          runId = cells[idIdx].trim();
        } else {
          runId = stableRunIdFromExternalId(externalId);
        }

        String? routeId;
        if (routeIdx != null && routeIdx < cells.length) {
          final raw = cells[routeIdx].trim();
          routeId = raw.isEmpty ? null : raw;
        }

        runs.add(Run(
          id: runId,
          startedAt: startedAt,
          duration: Duration(seconds: durationSeconds),
          distanceMetres: distance,
          track: const [],
          source: source,
          externalId: externalId,
          routeId: routeId,
          metadata: metadata,
        ));
      } catch (e) {
        recordImportFailure(failures, name: 'Row ${i + 1}', error: e);
      }
    }
    return CsvImportResult(runs: runs, failures: failures);
  }

  static RunSource _parseSource(String raw) {
    final v = raw.trim().toLowerCase();
    for (final s in RunSource.values) {
      if (s.name == v) return s;
    }
    return RunSource.app;
  }

  /// Deterministic synthetic id for the lossy 5-column CSV. Two
  /// imports of the exact same row produce the same id; the
  /// `runs.external_id` unique index dedupes at the DB and
  /// `LocalRunStore.save` replaces by `Run.id` locally, so the
  /// pairing keeps re-imports idempotent on both sides.
  ///
  /// Format: `csv:<iso-z>-<distance-m>-<duration-s>`. Includes the
  /// ISO-Z start time (millisecond-truncated to keep the id stable
  /// across formatter quirks) + rounded distance + duration. Two
  /// different runners with the same exact start time would collide,
  /// but the start time is already a near-unique key per user, and
  /// distance + duration make the collision space vanishingly small.
  @visibleForTesting
  static String syntheticExternalId({
    required DateTime startedAt,
    required double distanceM,
    required int durationS,
  }) =>
      _syntheticExternalId(
        startedAt: startedAt,
        distanceM: distanceM,
        durationS: durationS,
      );

  static String _syntheticExternalId({
    required DateTime startedAt,
    required double distanceM,
    required int durationS,
  }) {
    // toIso8601String() includes microseconds — strip to seconds so a
    // round-trip through different formatters lands on the same id.
    final utc = startedAt.toUtc();
    final iso =
        '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}T'
        '${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}:${utc.second.toString().padLeft(2, '0')}Z';
    return 'csv:$iso-${distanceM.round()}-$durationS';
  }

  /// Minimal RFC 4180 row splitter — handles quoted fields, escaped
  /// quotes (`""`), and embedded commas. Doesn't handle newlines
  /// inside quoted fields; the importer reads by `LineSplitter()`
  /// upstream which would split such fields, but the formats we
  /// produce never embed newlines.
  static List<String> _parseRow(String line) {
    final out = <String>[];
    final buf = StringBuffer();
    var i = 0;
    var inQuotes = false;
    while (i < line.length) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            buf.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        buf.write(ch);
        i++;
        continue;
      }
      if (ch == ',') {
        out.add(buf.toString());
        buf.clear();
        i++;
        continue;
      }
      if (ch == '"' && buf.isEmpty) {
        inQuotes = true;
        i++;
        continue;
      }
      buf.write(ch);
      i++;
    }
    out.add(buf.toString());
    return out;
  }
}

class CsvImportResult {
  final List<Run> runs;

  /// Every row that did not import, each classified so the runner can tell
  /// a fixable file from an unfixable one. `name` is the 1-based CSV row
  /// (header is row 1, first data row is row 2) — for a CSV the row IS the
  /// identity, and a summary row need not carry a title.
  final ImportFailureLog failures;

  const CsvImportResult({required this.runs, required this.failures});
  factory CsvImportResult.empty() =>
      CsvImportResult(runs: const [], failures: newImportFailureLog());
}
