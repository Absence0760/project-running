import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/csv_run_importer.dart';

void main() {
  // Helper — build the 5-column CSV the mobile + web Settings screens
  // produce. Same shape as `_exportRunsCsv` in settings_screen.dart.
  String mobileCsv(List<Map<String, Object>> rows) {
    final buf = StringBuffer('date,distance_m,duration_s,pace_s_per_km,source\n');
    for (final r in rows) {
      buf.writeln(
        '${r['date']},${r['distance_m']},${r['duration_s']},${r['pace_s_per_km']},${r['source']}',
      );
    }
    return buf.toString();
  }

  group('5-column mobile/web export', () {
    test('round-trips a single row to a Run with empty track', () {
      final csv = mobileCsv([
        {
          'date': '2026-05-20T08:15:30.000Z',
          'distance_m': 5000,
          'duration_s': 1500,
          'pace_s_per_km': 300,
          'source': 'app',
        }
      ]);
      final result = CsvRunImporter.parse(csv);
      expect(result.errors, isEmpty);
      expect(result.runs, hasLength(1));
      final run = result.runs.single;
      expect(run.startedAt.toUtc().toIso8601String(), '2026-05-20T08:15:30.000Z');
      expect(run.distanceMetres, 5000);
      expect(run.duration.inSeconds, 1500);
      expect(run.source, RunSource.app);
      expect(run.track, isEmpty);
      expect(run.metadata, isNotNull);
      expect(run.metadata!['imported_from'], 'csv');
      expect(run.metadata!['imported_at'], isA<String>());
      expect(run.metadata!['activity_type'], 'run');
      // Synthetic external_id for the 5-column form — see
      // CsvRunImporter.syntheticExternalId.
      expect(run.externalId, startsWith('csv:'));
    });

    test('parses multiple rows in order', () {
      final csv = mobileCsv([
        {
          'date': '2026-05-20T08:00:00.000Z',
          'distance_m': 5000,
          'duration_s': 1500,
          'pace_s_per_km': 300,
          'source': 'app',
        },
        {
          'date': '2026-05-21T08:00:00.000Z',
          'distance_m': 10000,
          'duration_s': 3000,
          'pace_s_per_km': 300,
          'source': 'strava',
        },
      ]);
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(2));
      expect(result.runs.first.distanceMetres, 5000);
      expect(result.runs.last.distanceMetres, 10000);
      expect(result.runs.last.source, RunSource.strava);
    });

    test('unknown source falls back to RunSource.app', () {
      final csv = mobileCsv([
        {
          'date': '2026-05-20T08:00:00.000Z',
          'distance_m': 5000,
          'duration_s': 1500,
          'pace_s_per_km': 300,
          'source': 'mystery-app',
        }
      ]);
      final result = CsvRunImporter.parse(csv);
      expect(result.runs.single.source, RunSource.app);
    });

    test('synthetic external_id is deterministic', () {
      final id1 = CsvRunImporter.syntheticExternalId(
        startedAt: DateTime.parse('2026-05-20T08:00:00.000Z'),
        distanceM: 5000,
        durationS: 1500,
      );
      final id2 = CsvRunImporter.syntheticExternalId(
        startedAt: DateTime.parse('2026-05-20T08:00:00.000Z'),
        distanceM: 5000,
        durationS: 1500,
      );
      expect(id1, id2);
      expect(id1, 'csv:2026-05-20T08:00:00Z-5000-1500');
    });

    test('synthetic external_id differs by start time', () {
      final id1 = CsvRunImporter.syntheticExternalId(
        startedAt: DateTime.parse('2026-05-20T08:00:00.000Z'),
        distanceM: 5000,
        durationS: 1500,
      );
      final id2 = CsvRunImporter.syntheticExternalId(
        startedAt: DateTime.parse('2026-05-20T08:00:01.000Z'),
        distanceM: 5000,
        durationS: 1500,
      );
      expect(id1, isNot(id2));
    });

    test('two parses of the same input yield matching external_ids', () {
      final csv = mobileCsv([
        {
          'date': '2026-05-20T08:00:00.000Z',
          'distance_m': 5000,
          'duration_s': 1500,
          'pace_s_per_km': 300,
          'source': 'app',
        }
      ]);
      final a = CsvRunImporter.parse(csv);
      final b = CsvRunImporter.parse(csv);
      // Fresh uuid IDs each pass, but external_id is stable so DB +
      // local store dedupe at re-import time.
      expect(a.runs.single.externalId, b.runs.single.externalId);
    });
  });

  group('17-column backend /export-data form', () {
    String backendCsv(List<Map<String, Object?>> rows) {
      final cols = [
        'id', 'started_at', 'distance_m', 'duration_s', 'source',
        'activity_type', 'title', 'avg_bpm', 'steps', 'elevation_m',
        'route_id', 'event_id', 'external_id', 'is_public', 'metadata',
        'created_at', 'updated_at',
      ];
      final buf = StringBuffer(cols.join(','))..write('\n');
      for (final r in rows) {
        final cells = [
          r['id'] ?? '',
          r['started_at'] ?? '',
          r['distance_m'] ?? '',
          r['duration_s'] ?? '',
          r['source'] ?? '',
          r['activity_type'] ?? '',
          r['title'] ?? '',
          r['avg_bpm'] ?? '',
          r['steps'] ?? '',
          r['elevation_m'] ?? '',
          r['route_id'] ?? '',
          r['event_id'] ?? '',
          r['external_id'] ?? '',
          r['is_public'] ?? 'false',
          // metadata column is JSON — quote it.
          '"${(r['metadata'] as String? ?? '{}').replaceAll('"', '""')}"',
          r['created_at'] ?? '',
          r['updated_at'] ?? '',
        ];
        buf.writeln(cells.join(','));
      }
      return buf.toString();
    }

    test('preserves original id + external_id + metadata', () {
      final metaJson = jsonEncode({
        'activity_type': 'hike',
        'title': 'My hike',
        'avg_bpm': 132,
      });
      final csv = backendCsv([
        {
          'id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'started_at': '2026-05-20T08:00:00Z',
          'distance_m': '5000',
          'duration_s': '1500',
          'source': 'strava',
          'activity_type': 'hike',
          'title': 'My hike',
          'external_id': 'strava:1234567890',
          'metadata': metaJson,
        }
      ]);
      final result = CsvRunImporter.parse(csv);
      expect(result.errors, isEmpty);
      final run = result.runs.single;
      expect(run.id, 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee');
      expect(run.externalId, 'strava:1234567890');
      expect(run.source, RunSource.strava);
      expect(run.metadata!['activity_type'], 'hike');
      expect(run.metadata!['title'], 'My hike');
      expect(run.metadata!['avg_bpm'], 132);
      // Always stamps the audit keys, even on a 17-column form.
      expect(run.metadata!['imported_from'], 'csv');
    });

    test('tolerates quoted commas + escaped quotes inside metadata', () {
      final metaJson = jsonEncode({
        'activity_type': 'run',
        'title': 'Hello, world "quoted"',
        'notes': 'comma, inside',
      });
      final csv = backendCsv([
        {
          'id': 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
          'started_at': '2026-05-20T08:00:00Z',
          'distance_m': '5000',
          'duration_s': '1500',
          'source': 'app',
          'metadata': metaJson,
        }
      ]);
      final result = CsvRunImporter.parse(csv);
      expect(result.errors, isEmpty);
      final run = result.runs.single;
      expect(run.metadata!['title'], 'Hello, world "quoted"');
      expect(run.metadata!['notes'], 'comma, inside');
    });

    test('malformed metadata JSON is dropped without sinking the row', () {
      // Header omits the quoted metadata wrapper our backendCsv helper
      // would add, so we hand-build a row with a broken metadata cell.
      final csv = 'id,started_at,distance_m,duration_s,source,metadata\n'
          'r-1,2026-05-20T08:00:00Z,5000,1500,app,"{not json"\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
      expect(result.errors, hasLength(1));
      expect(result.errors.single.message, contains('metadata'));
      // activity_type default still lands so the DB CHECK passes.
      expect(result.runs.single.metadata!['activity_type'], 'run');
    });
  });

  group('error handling', () {
    test('missing required columns surfaces a single header error', () {
      final csv = 'foo,bar\n1,2\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.message, contains('missing required columns'));
    });

    test('invalid date is skipped and reported', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          'not-a-date,5000,1500,300,app\n'
          '2026-05-21T08:00:00Z,10000,3000,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
      expect(result.runs.single.distanceMetres, 10000);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.row, 2);
      expect(result.errors.single.message, contains('Invalid date'));
    });

    test('invalid numeric is skipped and reported', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,not-a-number,1500,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, isEmpty);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.message, contains('Invalid distance'));
    });

    test('empty input returns empty result', () {
      final result = CsvRunImporter.parse('');
      expect(result.runs, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('header-only input returns empty result', () {
      final result = CsvRunImporter.parse(
        'date,distance_m,duration_s,pace_s_per_km,source\n',
      );
      expect(result.runs, isEmpty);
      expect(result.errors, isEmpty);
    });

    test('skips blank lines between rows', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,5000,1500,300,app\n'
          '\n'
          '2026-05-21T08:00:00Z,10000,3000,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(2));
      expect(result.errors, isEmpty);
    });

    test('row shorter than header is reported, not parsed', () {
      // Header has 5 columns; a row with only 1 cell can't supply
      // the required start time at column 0 — but here the source
      // column at index 4 is what's missing.
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.errors, hasLength(1));
      expect(result.errors.single.message, contains('fewer columns'));
    });
  });

  group('header tolerance', () {
    test('accepts started_at as an alias for date', () {
      final csv = 'started_at,distance_m,duration_s\n'
          '2026-05-20T08:00:00Z,5000,1500\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
      expect(result.runs.single.distanceMetres, 5000);
      // No source column → default to app.
      expect(result.runs.single.source, RunSource.app);
    });

    test('case-insensitive column names', () {
      final csv = 'DATE,DISTANCE_M,DURATION_S\n'
          '2026-05-20T08:00:00Z,5000,1500\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
    });
  });
}
