import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core_models/core_models.dart';
import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:gpx_parser/gpx_parser.dart';
import 'package:uuid/uuid.dart';

import 'embedded_bests.dart';
import 'import_failures.dart';
import 'imported_run_id.dart';

/// Parse a Strava-formatted activity date string into a [DateTime].
///
/// Strava CSVs use `"Apr 9, 2026, 7:30:00 AM"` (with optional comma after
/// the year and optional 12-hour AM/PM marker), or sometimes ISO 8601.
/// Returns null when the input matches neither shape — callers fall back
/// to the per-track-file timestamp.
///
/// Strava emits the no-zone wall-clock form in UTC but WITHOUT a zone
/// designator, so we build the parsed-components result as a UTC [DateTime]
/// (`DateTime.utc`) rather than a local one — a local parse would shift every
/// imported run by the device offset, rolling a midnight run onto the wrong
/// day/week/heatmap cell. An already-zoned / ISO value is left to
/// `DateTime.tryParse` so we never corrupt a value that already carries an
/// offset.
DateTime? parseStravaDate(String raw) {
  // ISO first — honours any embedded zone.
  final iso = DateTime.tryParse(raw);
  if (iso != null) return iso;

  // Try a few common formats by hand. We don't bring in intl just for this.
  const months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  final m = RegExp(
          r'(\w+)\s+(\d{1,2}),?\s+(\d{4}),?\s+(\d{1,2}):(\d{2}):(\d{2})\s*([AP]M)?',
          caseSensitive: false)
      .firstMatch(raw);
  if (m == null) return null;
  final month = months[m.group(1)!.toLowerCase().substring(0, 3)];
  if (month == null) return null;
  final day = int.parse(m.group(2)!);
  final year = int.parse(m.group(3)!);
  var hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = int.parse(m.group(6)!);
  final ampm = m.group(7)?.toUpperCase();
  if (ampm == 'PM' && hour < 12) hour += 12;
  if (ampm == 'AM' && hour == 12) hour = 0;
  return DateTime.utc(year, month, day, hour, minute, second);
}

/// Resolve a Strava export row's distance to metres.
///
/// Strava's `activities.csv` carries two "Distance" columns: a summary-block
/// one in the athlete's DISPLAY unit (km OR miles at export time — a documented
/// Strava quirk) and a raw-block one (~col 18) that is always metres. Prefer
/// the raw metric column so an imperial athlete's export imports the true
/// distance instead of a ~1.6x-short one; fall back to the display column
/// (explicit miles→metres, or the legacy km-assumption) only when the raw
/// column is absent. [lowerHeader] must be lower-cased (as the importer keeps
/// it). Mirrors web `stravaDistanceMetres` in strava-zip-header.ts.
double stravaCsvDistanceMetres(List<String> lowerHeader, List<dynamic> row) {
  // `?? 0` catches an UNPARSEABLE cell, which is not the same question as an
  // unusable one: `double.tryParse` returns a value for the literals `NaN`,
  // `Infinity` and `-Infinity`, so those three fell through to the imported
  // run's `distance_m` — a `numeric(10, 2)` column with no CHECK, whose
  // aggregates then read NaN. The web twin this function's doc names has
  // guarded on `Number.isFinite` since it was written; this half only tested
  // for null, which is the drift.
  double parse(int i) {
    if (i < 0 || i >= row.length) return 0;
    final v = double.tryParse(row[i].toString().replaceAll(',', ''));
    return v != null && v.isFinite ? v : 0;
  }
  int findAny(List<String> names) {
    for (final n in names) {
      final i = lowerHeader.indexWhere((h) => h.trim() == n);
      if (i >= 0) return i;
    }
    return -1;
  }

  final plain = <int>[];
  for (var i = 0; i < lowerHeader.length; i++) {
    if (lowerHeader[i].trim() == 'distance') plain.add(i);
  }
  if (plain.length >= 2) return parse(plain[1]);

  final metresIdx =
      findAny(['distance (m)', 'distance in meters', 'distance in metres']);
  if (metresIdx >= 0) return parse(metresIdx);
  if (plain.length == 1) return parse(plain.first) * 1000;
  final kmIdx = findAny(
      ['distance (km)', 'distance in kilometers', 'distance in kilometres']);
  if (kmIdx >= 0) return parse(kmIdx) * 1000;
  final miIdx = findAny(['distance (mi)', 'distance in miles']);
  if (miIdx >= 0) return parse(miIdx) * 1609.344;
  return 0;
}

/// Imports a Strava data export ZIP into [Run] objects.
///
/// Strava exports look like:
///
///   activities.csv               (metadata: id, date, name, type, distance, filename)
///   activities/12345.gpx         (or .gpx.gz, .tcx.gz, .fit.gz)
///   activities/12346.tcx.gz
///   ...
///
/// We parse the CSV for activity metadata, then walk each referenced track
/// file under `activities/` and convert it to a Run. FIT files are skipped
/// (binary format, would need a separate parser); users with mostly FIT
/// activities should re-export from Strava as GPX or TCX.
class StravaImporter {
  static const _uuid = Uuid();

  /// Read and parse a Strava export zip from disk.
  /// Returns the runs that could be successfully extracted, plus a
  /// classified [ImportFailureLog] naming each activity that did not make
  /// it and why — a bare count can't tell a migrant whether re-running the
  /// import will land the missing runs or never will.
  ///
  /// Heavy lifting (ZipDecoder + per-file XML/FIT parsing) runs in a
  /// background isolate via [compute] so the UI thread stays free during
  /// large imports. A 5-year Strava export with hundreds of activities
  /// would otherwise lock the foreground for tens of seconds.
  static Future<StravaImportResult> importFromZip(File zipFile) async {
    // audit/strava May 2026 Medium #1 — cap the archive size so a
    // 5 GB export from a decade-of-multi-sport-activity power user
    // doesn't OOM the app. 500 MB matches the web side.
    const maxZipBytes = 500 * 1024 * 1024;
    final size = await zipFile.length();
    if (size > maxZipBytes) {
      final mb = (size / (1024 * 1024)).round();
      throw FormatException(
        'Strava ZIP too large ($mb MB). The 500 MB cap defends '
        'against OOM on the parser. Split into yearly exports from '
        'Strava → Settings → My Account → Download or Delete Your '
        'Account.',
      );
    }
    final bytes = await zipFile.readAsBytes();
    return compute(_parseStravaZipBytes, bytes);
  }

  /// Pure synchronous parse — runs in a background isolate so it can't
  /// block the UI. The argument and return are [Uint8List] / standard
  /// Dart objects (Run, Waypoint, Duration, DateTime are all
  /// transferable across isolates).
  static StravaImportResult _parseStravaZipBytes(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);

    final csvFile = archive.files
        .where((f) => f.name.endsWith('activities.csv'))
        .firstOrNull;
    if (csvFile == null) {
      throw const FormatException(
          'Not a Strava export — no activities.csv found');
    }

    final csvText = utf8.decode(csvFile.content);
    final rows = const CsvDecoder().convert(csvText);
    if (rows.isEmpty) {
      return StravaImportResult(const [], newImportFailureLog());
    }

    final header = rows.first.map((c) => c.toString().toLowerCase()).toList();
    final idIdx = header.indexOf('activity id');
    final dateIdx = header.indexOf('activity date');
    final nameIdx = header.indexOf('activity name');
    final typeIdx = header.indexOf('activity type');
    final elapsedIdx = header.indexOf('elapsed time');
    final filenameIdx = header.indexOf('filename');

    if (filenameIdx < 0 || dateIdx < 0) {
      throw const FormatException('Strava CSV missing expected columns');
    }

    final byPath = {for (final f in archive.files) f.name: f};

    final runs = <Run>[];
    final failures = newImportFailureLog();

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      // Strava leaves `Filename` empty for a manually-entered or indoor
      // activity — there is no track file to point at, and the row's own
      // date / distance / elapsed time is the whole activity. Skipping those
      // rows dropped every one of a migrating runner's manual activities with
      // no count and no report; web's importer keeps them, trackless.
      final filename =
          filenameIdx < row.length ? row[filenameIdx].toString() : '';

      // Read outside the try so a row that throws is still reported under
      // the name and date the runner will recognise, not under the opaque
      // archive path. Bounds-checked: a short row must record a failure,
      // never throw past the per-row catch and abort the whole import.
      final dateStr = dateIdx < row.length ? row[dateIdx].toString() : '';
      final name = (nameIdx >= 0 && nameIdx < row.length)
          ? row[nameIdx].toString()
          : 'Strava activity';

      try {
        final activityId = idIdx >= 0 ? row[idIdx].toString() : _uuid.v4();
        final typeStr = typeIdx >= 0 ? row[typeIdx].toString() : 'Run';
        final csvElapsed = elapsedIdx >= 0
            ? int.tryParse(row[elapsedIdx].toString()) ?? 0
            : 0;

        final run = _parseTrackFile(
          archive: byPath,
          path: filename,
          stravaId: activityId,
          name: name,
          stravaType: typeStr,
          startedAtRaw: dateStr,
          fallbackDistanceMetres: stravaCsvDistanceMetres(header, row),
          fallbackDurationSeconds: csvElapsed,
        );
        runs.add(run);
      } catch (e) {
        recordImportFailure(
          failures,
          name: name,
          startedAt: parseStravaDate(dateStr)?.toIso8601String(),
          error: e,
        );
      }
    }

    return StravaImportResult(runs, failures);
  }

  static Run _parseTrackFile({
    required Map<String, ArchiveFile> archive,
    required String path,
    required String stravaId,
    required String name,
    required String stravaType,
    required String startedAtRaw,
    required double fallbackDistanceMetres,
    required int fallbackDurationSeconds,
  }) {
    // An empty path is not a broken export: the row simply has no track file.
    // A path that names one and is missing it, or names a format we can't
    // read, still throws so the caller reports it — the export promised
    // something it did not deliver.
    Route? parsedRoute;
    if (path.isNotEmpty) {
      final file = archive[path];
      if (file == null) {
        // The wording is load-bearing, not decoration: classifyImportFailure
        // buckets on the message, and neither the bare "not found" nor the
        // bare "unknown format" matched any pattern — so the two refusals
        // reached the report as `unknown`, which tells a migrating runner
        // nothing about whether re-running the import can land the run. It
        // cannot; the member is not in the file. Web throws the identical
        // strings (decisions.md § 676).
        throw FormatException(
            'Malformed export: track file not found in zip: $path');
      }

      // Decompress if .gz
      List<int> content = file.content as List<int>;
      if (path.endsWith('.gz')) {
        content = GZipDecoder().decodeBytes(content);
      }

      final lower = path.toLowerCase();
      if (lower.contains('.gpx')) {
        parsedRoute = RouteParser.fromGpx(utf8.decode(content));
      } else if (lower.contains('.tcx')) {
        parsedRoute = RouteParser.fromTcx(utf8.decode(content));
      } else if (lower.contains('.fit')) {
        parsedRoute = FitParser.parse(Uint8List.fromList(content));
      } else {
        throw FormatException('Unsupported file format: $path');
      }
    }

    // Use the parsed track. Fall back to CSV-supplied numbers if the file
    // somehow has no waypoints.
    final track = (parsedRoute?.waypoints ?? const [])
        .map((w) => Waypoint(
              lat: w.lat,
              lng: w.lng,
              elevationMetres: w.elevationMetres,
              timestamp: w.timestamp,
            ))
        .toList();

    final distance = (parsedRoute?.distanceMetres ?? 0) > 0
        ? parsedRoute!.distanceMetres
        : fallbackDistanceMetres;

    // Strava CSV date format: "Apr 9, 2026, 7:30:00 AM"
    // audit/strava May 2026 Low #5 — a malformed date row used to
    // silently fall back to DateTime.now() (importing the activity
    // as "just happened"). That's a worse outcome than "drop the
    // row + report it failed". Throw a FormatException so the
    // caller's existing per-row try/catch buckets it into the
    // failed count + the operator sees what went wrong.
    final parsedDate = _parseStravaDate(startedAtRaw);
    if (parsedDate == null) {
      throw FormatException('Unparseable Strava CSV date: "$startedAtRaw"');
    }
    final startedAt = parsedDate;

    final duration = fallbackDurationSeconds > 0
        ? Duration(seconds: fallbackDurationSeconds)
        : (track.length >= 2 &&
                track.first.timestamp != null &&
                track.last.timestamp != null
            ? track.last.timestamp!.difference(track.first.timestamp!)
            : Duration.zero);

    // Embedded best efforts (fastest_{5k,10k,half_marathon,marathon}_s) so a
    // fast sub-distance inside a long imported run reaches personal_records
    // (the refresher reads the promoted runs columns, 20270325_001; the
    // api_client save path lifts these bag keys onto them) — matching what
    // the live recorder writes and what the web/EF Strava importers compute.
    // Returns the map unchanged when the track has < 3 points or no per-point
    // timestamps, so no fake bests are written.
    final metadata = enrichMetadataWithEmbeddedBests(
      track: track,
      metadata: {
        MetadataKeys.title: name.isEmpty ? 'Strava import' : name,
        // Match the web importer's derivation in apps/web/src/lib/
        // strava-zip.ts so a Strava ZIP imported on either platform
        // produces the same activity_type. Fallback is 'run'.
        MetadataKeys.activityType: _activityTypeFromStrava(stravaType),
        MetadataKeys.importedFrom: 'strava',
        MetadataKeys.stravaActivityType: stravaType,
        MetadataKeys.importedAt: DateTime.now().toUtc().toIso8601String(),
      },
    );

    final externalId = 'strava:$stravaId';
    return Run(
      // Stable id derived from external_id so a re-import of the same ZIP maps
      // to the same local run (no duplicate) and the server upsert never
      // rewrites the primary key — see imported_run_id.dart (#361).
      id: stableRunIdFromExternalId(externalId),
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distance,
      track: track,
      source: RunSource.strava,
      externalId: externalId,
      metadata: metadata,
    );
  }

  static DateTime? _parseStravaDate(String raw) => parseStravaDate(raw);

  static String _activityTypeFromStrava(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('walk')) return 'walk';
    if (lower.contains('hike')) return 'hike';
    return 'run';
  }
}

class StravaImportResult {
  final List<Run> runs;
  final ImportFailureLog failures;
  const StravaImportResult(this.runs, this.failures);
}
