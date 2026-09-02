import 'dart:convert';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/csv_run_importer.dart';
import '../lib/import_failures.dart';
import '../lib/preferences.dart' show ActivityType;

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
      expect(result.failures.items, isEmpty);
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
      // Both external_id AND id are derived deterministically from the row, so
      // a re-import dedupes on the DB `external_id` unique index and on
      // `LocalRunStore.save`'s id-replace semantics locally (#361).
      expect(a.runs.single.externalId, b.runs.single.externalId);
      expect(a.runs.single.id, b.runs.single.id);
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
      expect(result.failures.items, isEmpty);
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
      expect(result.failures.items, isEmpty);
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
      expect(result.failures.items, hasLength(1));
      expect(result.failures.items.single.name, 'Row 2');
      expect(result.failures.items.single.reason,
          ImportFailureReason.unparseable);
      // activity_type default still lands so the DB CHECK passes.
      expect(result.runs.single.metadata!['activity_type'], 'run');
    });
  });

  group('error handling', () {
    test('missing required columns surfaces a single header error', () {
      final csv = 'foo,bar\n1,2\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, isEmpty);
      expect(result.failures.items, hasLength(1));
      expect(result.failures.items.single.detail,
          contains('missing required columns'));
      expect(result.failures.items.single.reason,
          ImportFailureReason.unparseable);
    });

    test('invalid date is skipped and reported', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          'not-a-date,5000,1500,300,app\n'
          '2026-05-21T08:00:00Z,10000,3000,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
      expect(result.runs.single.distanceMetres, 10000);
      expect(result.failures.items, hasLength(1));
      expect(result.failures.items.single.name, 'Row 2');
      expect(result.failures.items.single.detail, contains('parse the date'));
    });

    test('invalid numeric is skipped and reported', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,not-a-number,1500,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, isEmpty);
      expect(result.failures.items, hasLength(1));
      expect(result.failures.items.single.detail,
          contains('parse the distance'));
    });

    test('empty input returns empty result', () {
      final result = CsvRunImporter.parse('');
      expect(result.runs, isEmpty);
      expect(result.failures.items, isEmpty);
    });

    test('header-only input returns empty result', () {
      final result = CsvRunImporter.parse(
        'date,distance_m,duration_s,pace_s_per_km,source\n',
      );
      expect(result.runs, isEmpty);
      expect(result.failures.items, isEmpty);
    });

    test('skips blank lines between rows', () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,5000,1500,300,app\n'
          '\n'
          '2026-05-21T08:00:00Z,10000,3000,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(2));
      expect(result.failures.items, isEmpty);
    });

    test('row shorter than header is reported, not parsed', () {
      // Header has 5 columns; a row with only 1 cell can't supply
      // the required start time at column 0 — but here the source
      // column at index 4 is what's missing.
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.failures.items, hasLength(1));
      expect(result.failures.items.single.detail, contains('fewer columns'));
    });
  });

  group('large + Unicode + adversarial input', () {
    test('1000-row CSV parses in well under a second', () {
      // Regression guard against O(n²) parser. Each row is the
      // exact shape Settings → CSV export produces.
      final buf = StringBuffer('date,distance_m,duration_s,pace_s_per_km,source\n');
      for (var i = 0; i < 1000; i++) {
        buf.writeln(
          '2026-05-${(i % 28 + 1).toString().padLeft(2, '0')}T08:00:00Z,'
          '${5000 + i},${1500 + i},300,app',
        );
      }
      final sw = Stopwatch()..start();
      final result = CsvRunImporter.parse(buf.toString());
      sw.stop();
      expect(result.runs, hasLength(1000));
      expect(result.failures.items, isEmpty);
      expect(sw.elapsedMilliseconds, lessThan(1000),
          reason: '1000-row parse took ${sw.elapsedMilliseconds}ms — '
              'check for an O(n²) regression in the parser');
    });

    test('Unicode in source / activity / title cells round-trips intact', () {
      final csv = 'started_at,distance_m,duration_s,source,activity_type,title\n'
          // The title cell embeds CJK + an emoji + a German umlaut to
          // catch any UTF-8 truncation in the row splitter.
          '"2026-05-20T08:00:00Z","5000","1500","app","run","早朝ラン 🏃‍♂️ Müller"\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.failures.items, isEmpty);
      final r = result.runs.single;
      expect(r.metadata!['title'], '早朝ラン 🏃‍♂️ Müller');
    });

    test('quoted cells survive embedded commas + escaped quotes', () {
      final csv = 'started_at,distance_m,duration_s,source,title\n'
          '"2026-05-20T08:00:00Z","5000","1500","app","Run, then ""sprint""!"\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.failures.items, isEmpty);
      expect(result.runs.single.metadata!['title'], 'Run, then "sprint"!');
    });

    test('mixed valid + invalid rows produce a partial result, not all-or-nothing',
        () {
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,5000,1500,300,app\n'
          'BROKEN-DATE,5000,1500,300,app\n'
          '2026-05-21T08:00:00Z,not-a-number,1500,300,app\n'
          '2026-05-22T08:00:00Z,10000,3000,300,strava\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(2));
      expect(result.runs.first.distanceMetres, 5000);
      expect(result.runs.last.distanceMetres, 10000);
      expect(result.failures.items, hasLength(2));
      expect(result.failures.items.first.name, 'Row 3');
      expect(result.failures.items.last.name, 'Row 4');
    });

    test('CRLF line endings are accepted', () {
      // Excel + many Windows tools save with CRLF. The parser
      // splits via LineSplitter which handles both '\n' and '\r\n'.
      final csv =
          'date,distance_m,duration_s,pace_s_per_km,source\r\n'
          '2026-05-20T08:00:00Z,5000,1500,300,app\r\n'
          '2026-05-21T08:00:00Z,7500,2250,300,app\r\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(2));
      expect(result.failures.items, isEmpty);
    });

    test('negative distance / duration are refused by the parser', () {
      // This case previously asserted the opposite, on the stated grounds
      // that "the DB CHECK (distance_m >= 0, duration_s >= 0) is the source
      // of truth". `public.runs` has neither CHECK — those live on
      // `event_results` and `gym_workouts` — so the parser was passing a
      // -100 m run through to a column (`numeric(10, 2)`, not null, no
      // constraint) that stores it happily, and to every aggregate that
      // sums it. The value has to be graded where it is read.
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,-100,-50,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, isEmpty);
      expect(result.failures.total, 1);
    });

    test('row with trailing whitespace + extra commas parses leniently', () {
      // Dart's int.tryParse/double.tryParse both tolerate trailing
      // whitespace + tabs, so a CSV with stray padding still hands back a
      // valid row — the parser stays permissive on WHITESPACE so a
      // hand-edited CSV that survived a spreadsheet round-trip still
      // imports. Permissive on whitespace is not the same as permissive on
      // values: a measurement that is not a measurement, or an activity type
      // `runs_activity_type_check` cannot hold, is refused above.
      final csv = 'date,distance_m,duration_s,pace_s_per_km,source\n'
          '2026-05-20T08:00:00Z,5000,1500   ,300,app\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs, hasLength(1));
      expect(result.runs.single.duration.inSeconds, 1500);
      expect(result.failures.items, isEmpty);
    });

    test('17-column metadata with deeply-nested objects round-trips', () {
      final nested = '{"activity_type":"run","laps":[{"index":1,"distance_m":1000,"duration_s":300,"start_offset_s":0},{"index":2,"distance_m":1000,"duration_s":290,"start_offset_s":300}]}';
      final csv = 'id,started_at,distance_m,duration_s,source,metadata\n'
          'r-1,2026-05-20T08:00:00Z,5000,1500,app,"${nested.replaceAll('"', '""')}"\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.failures.items, isEmpty);
      final laps = result.runs.single.metadata!['laps'] as List;
      expect(laps, hasLength(2));
      expect((laps.first as Map)['index'], 1);
      expect((laps.last as Map)['duration_s'], 290);
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

  // Parsing is not validating. `double.tryParse` accepts the literals `NaN`
  // and `Infinity`, and neither parse rejects a negative, so a hand-edited or
  // third-party CSV could import a run of -5 km. `runs.distance_m` is
  // `numeric(10, 2)` with no CHECK and postgres numeric holds NaN, so nothing
  // downstream would have caught one.
  group('non-physical measurements are refused, not imported', () {
    String rowsCsv(List<String> rows) =>
        'date,distance_m,duration_s,pace_s_per_km,source\n${rows.join('\n')}\n';

    test('a negative distance is refused', () {
      final result = CsvRunImporter.parse(rowsCsv([
        '2026-05-20T08:00:00Z,-5000,1500,300,app',
        '2026-05-21T08:00:00Z,5000,1500,300,app',
      ]));
      expect(result.runs, hasLength(1));
      expect(result.runs.single.distanceMetres, 5000);
      expect(result.failures.total, 1);
    });

    test('a negative duration is refused', () {
      final result = CsvRunImporter.parse(rowsCsv([
        '2026-05-20T08:00:00Z,5000,-1500,300,app',
      ]));
      expect(result.runs, isEmpty);
      expect(result.failures.total, 1);
    });

    test('a non-finite distance is refused AS a bad measurement', () {
      // Previously refused only by accident: _syntheticExternalId calls
      // .round() on it, which throws "Unsupported operation: Infinity or NaN
      // toInt", and the runner saw that rather than a bad measurement. The
      // assertion is on the guard's OWN wording, because the accidental
      // throw's message happens to contain "NaN" and "Infinity" as well and
      // a substring test on the value alone cannot tell the two apart.
      for (final bad in ['NaN', 'Infinity', '-Infinity']) {
        final result =
            CsvRunImporter.parse(rowsCsv(['2026-05-20T08:00:00Z,$bad,1500,300,app']));
        expect(result.runs, isEmpty, reason: bad);
        expect(result.failures.total, 1, reason: bad);
        final detail = result.failures.items.single.detail;
        expect(detail, contains('must be zero or more'), reason: bad);
        expect(detail, contains(bad), reason: bad);
      }
    });

    test('zero distance and zero duration are still allowed', () {
      // A zero-distance row is odd but not impossible, and refusing it would
      // drop a real logged entry.
      final result = CsvRunImporter.parse(rowsCsv([
        '2026-05-20T08:00:00Z,0,0,0,app',
      ]));
      expect(result.runs, hasLength(1));
      expect(result.failures.total, 0);
    });
  });

  group('activity type is validated against the column vocabulary', () {
    String activityCsv(String value) =>
        'date,distance_m,duration_s,activity_type\n'
        '2026-05-20T08:00:00Z,5000,1500,$value\n';

    test('every value the ActivityType rail carries is accepted', () {
      for (final a in ActivityType.values) {
        final result = CsvRunImporter.parse(activityCsv(a.name));
        expect(result.runs, hasLength(1), reason: a.name);
        expect(result.runs.single.metadata?[MetadataKeys.activityType], a.name,
            reason: a.name);
      }
    });

    test('case is normalised rather than refused', () {
      final result = CsvRunImporter.parse(activityCsv('Walk'));
      expect(result.runs, hasLength(1));
      expect(result.runs.single.metadata?[MetadataKeys.activityType], 'walk');
    });

    test('a value the column CHECK cannot hold is refused at import', () {
      // It used to be written through verbatim: the import reported success
      // and the row then failed to sync forever on a postgres 23514 the
      // runner never saw.
      for (final bad in ['Ride', 'Swim', 'totally-made-up']) {
        final result = CsvRunImporter.parse(activityCsv(bad));
        expect(result.runs, isEmpty, reason: bad);
        expect(result.failures.total, 1, reason: bad);
        expect(result.failures.items.single.detail, contains(bad), reason: bad);
      }
    });

    test('an absent activity type still defaults to run', () {
      final csv = 'date,distance_m,duration_s\n2026-05-20T08:00:00Z,5000,1500\n';
      final result = CsvRunImporter.parse(csv);
      expect(result.runs.single.metadata?[MetadataKeys.activityType], 'run');
    });
  });
}
