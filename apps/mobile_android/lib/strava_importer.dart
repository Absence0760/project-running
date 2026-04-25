import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:core_models/core_models.dart';
import 'package:csv/csv.dart';
import 'package:gpx_parser/gpx_parser.dart';
import 'package:uuid/uuid.dart';

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
  /// Returns the runs that could be successfully extracted, plus a list of
  /// any per-file errors so the UI can show "imported X of Y" messaging.
  static Future<StravaImportResult> importFromZip(File zipFile) async {
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Find activities.csv
    final csvFile = archive.files
        .where((f) => f.name.endsWith('activities.csv'))
        .firstOrNull;
    if (csvFile == null) {
      throw const FormatException('Not a Strava export — no activities.csv found');
    }

    final csvText = utf8.decode(csvFile.content);
    final rows = const CsvDecoder().convert(csvText);
    if (rows.isEmpty) return StravaImportResult([], []);

    // First row is the header — find column indices.
    final header = rows.first.map((c) => c.toString().toLowerCase()).toList();
    final idIdx = header.indexOf('activity id');
    final dateIdx = header.indexOf('activity date');
    final nameIdx = header.indexOf('activity name');
    final typeIdx = header.indexOf('activity type');
    final distanceIdx = header.indexOf('distance (km)') != -1
        ? header.indexOf('distance (km)')
        : header.indexOf('distance');
    final elapsedIdx = header.indexOf('elapsed time');
    final filenameIdx = header.indexOf('filename');

    if (filenameIdx < 0 || dateIdx < 0) {
      throw const FormatException('Strava CSV missing expected columns');
    }

    // Build a lookup from filename → archive file for fast access.
    final byPath = {for (final f in archive.files) f.name: f};

    final runs = <Run>[];
    final errors = <StravaImportError>[];

    for (var i = 1; i < rows.length; i++) {
      final row = rows[i];
      if (row.length <= filenameIdx) continue;
      final filename = row[filenameIdx].toString();
      if (filename.isEmpty) continue;

      try {
        final activityId = idIdx >= 0 ? row[idIdx].toString() : _uuid.v4();
        final dateStr = row[dateIdx].toString();
        final name = nameIdx >= 0 ? row[nameIdx].toString() : 'Strava activity';
        final typeStr = typeIdx >= 0 ? row[typeIdx].toString() : 'Run';
        final csvDistance = distanceIdx >= 0
            ? double.tryParse(row[distanceIdx].toString()) ?? 0
            : 0.0;
        final csvElapsed = elapsedIdx >= 0
            ? int.tryParse(row[elapsedIdx].toString()) ?? 0
            : 0;

        final run = await _parseTrackFile(
          archive: byPath,
          path: filename,
          stravaId: activityId,
          name: name,
          stravaType: typeStr,
          startedAtRaw: dateStr,
          fallbackDistanceMetres: csvDistance * 1000,
          fallbackDurationSeconds: csvElapsed,
        );
        runs.add(run);
      } catch (e) {
        errors.add(StravaImportError(filename, e.toString()));
      }
    }

    return StravaImportResult(runs, errors);
  }

  static Future<Run> _parseTrackFile({
    required Map<String, ArchiveFile> archive,
    required String path,
    required String stravaId,
    required String name,
    required String stravaType,
    required String startedAtRaw,
    required double fallbackDistanceMetres,
    required int fallbackDurationSeconds,
  }) async {
    final file = archive[path];
    if (file == null) {
      throw FormatException('Track file not found in zip: $path');
    }

    // Decompress if .gz
    List<int> content = file.content as List<int>;
    if (path.endsWith('.gz')) {
      content = GZipDecoder().decodeBytes(content);
    }

    final lower = path.toLowerCase();
    Route parsedRoute;
    if (lower.contains('.gpx')) {
      parsedRoute = RouteParser.fromGpx(utf8.decode(content));
    } else if (lower.contains('.tcx')) {
      parsedRoute = RouteParser.fromTcx(utf8.decode(content));
    } else if (lower.contains('.fit')) {
      parsedRoute = FitParser.parse(Uint8List.fromList(content));
    } else {
      throw FormatException('Unknown track format: $path');
    }

    // Use the parsed track. Fall back to CSV-supplied numbers if the file
    // somehow has no waypoints.
    final track = parsedRoute.waypoints
        .map((w) => Waypoint(
              lat: w.lat,
              lng: w.lng,
              elevationMetres: w.elevationMetres,
              timestamp: w.timestamp,
            ))
        .toList();

    final distance = parsedRoute.distanceMetres > 0
        ? parsedRoute.distanceMetres
        : fallbackDistanceMetres;

    // Strava CSV date format: "Apr 9, 2026, 7:30:00 AM"
    final startedAt = _parseStravaDate(startedAtRaw) ?? DateTime.now();

    final duration = fallbackDurationSeconds > 0
        ? Duration(seconds: fallbackDurationSeconds)
        : (track.length >= 2 &&
                track.first.timestamp != null &&
                track.last.timestamp != null
            ? track.last.timestamp!.difference(track.first.timestamp!)
            : Duration.zero);

    return Run(
      id: _uuid.v4(),
      startedAt: startedAt,
      duration: duration,
      distanceMetres: distance,
      track: track,
      source: RunSource.strava,
      externalId: 'strava:$stravaId',
      metadata: {
        'title': name.isEmpty ? 'Strava import' : name,
        'imported_from': 'strava',
        'strava_activity_type': stravaType,
        'imported_at': DateTime.now().toIso8601String(),
      },
    );
  }

  static DateTime? _parseStravaDate(String raw) {
    // Strava format: "Apr 9, 2026, 7:30:00 AM" or ISO. Try ISO first.
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;

    // Try a few common formats by hand. We don't bring in intl just for this.
    final months = {
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
    return DateTime(year, month, day, hour, minute, second);
  }
}

class StravaImportResult {
  final List<Run> runs;
  final List<StravaImportError> errors;
  const StravaImportResult(this.runs, this.errors);
}

class StravaImportError {
  final String filename;
  final String message;
  const StravaImportError(this.filename, this.message);
}
