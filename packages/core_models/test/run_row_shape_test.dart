import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

Run _run({
  Map<String, dynamic>? metadata,
  DateTime? createdAt,
  double distanceMetres = 10000,
}) =>
    Run(
      id: 'run-1',
      startedAt: DateTime.utc(2026, 5, 1, 7, 30),
      duration: const Duration(minutes: 42),
      distanceMetres: distanceMetres,
      source: RunSource.app,
      metadata: metadata,
      createdAt: createdAt,
    );

void main() {
  group('runRowFromRun is total, as Run.toJson already was', () {
    // decisions § 986 made the DOMAIN serializer total by screening its
    // OUTPUT. `runRowFromRun` reads the FIELDS, and the resident run object a
    // sync drain uploads is the one that was handed to the store — not the
    // screened copy that was written to disk. So every hole § 986 closed on
    // one path was still open on the other. decisions § 1010.
    void expectEncodable(RunRow row) {
      expect(() => jsonEncode(row.toJson()), returnsNormally);
    }

    test('a non-finite distance resolves to zero, not to a refused encode', () {
      for (final d in [double.nan, double.infinity, double.negativeInfinity]) {
        final row = runRowFromRun(_run(distanceMetres: d), userId: 'u');
        expect(row.distanceM, 0.0, reason: '$d');
        expectEncodable(row);
      }
    });

    test('the row and the domain object agree on that answer', () {
      // Two copies of a coercion rule drift. `storableDistanceMetres` is the
      // one home both go through.
      for (final d in [double.nan, double.infinity, -1.0, 0.0, 4213.7]) {
        expect(
          runRowFromRun(_run(distanceMetres: d), userId: 'u').distanceM,
          _run(distanceMetres: d).toJson()['distanceMetres'],
          reason: '$d',
        );
      }
    });

    test('a non-finite embedded best is dropped, not thrown on', () {
      // `toInt()` raises "Infinity or NaN toInt" — an UnsupportedError out of
      // the row BUILDER, before any writer could catch it per-run.
      for (final v in [double.nan, double.infinity]) {
        late RunRow row;
        expect(
          () => row = runRowFromRun(
              _run(metadata: {MetadataKeys.fastest5kS: v}), userId: 'u'),
          returnsNormally,
          reason: '$v',
        );
        expect(row.fastest5kS, isNull);
        expectEncodable(row);
      }
    });

    test('a non-finite value anywhere in the bag is dropped', () {
      final row = runRowFromRun(
        _run(metadata: {
          MetadataKeys.avgBpm: double.nan,
          MetadataKeys.elevationM: double.infinity,
          'ok': 12,
        }),
        userId: 'u',
      );
      expectEncodable(row);
      expect(row.metadata, {'ok': 12});
      // Dropping, not coercing: a bag key has no column and no CHECK saying
      // what a missing value means, so a zero would state a heart rate nobody
      // recorded.
      expect(row.metadata!.containsKey(MetadataKeys.avgBpm), isFalse);
    });

    test('the bag scrub reaches nested lists and maps', () {
      // `workout_step_results` is a list of maps and `jsonEncode` walks all of
      // it, so a top-level-only scrub would leave the encoder what it refuses.
      final row = runRowFromRun(
        _run(metadata: {
          'workout_step_results': [
            {'stepIndex': 0, 'paceSecPerKm': double.nan, 'ok': 1},
            {'stepIndex': 1, 'paceSecPerKm': 300.0},
          ],
          'nested': {
            'deeper': {'bad': double.infinity, 'good': 2}
          },
        }),
        userId: 'u',
      );
      expectEncodable(row);
      final steps = (row.metadata!['workout_step_results'] as List)
          .cast<Map<String, dynamic>>();
      expect(steps[0].containsKey('paceSecPerKm'), isFalse);
      expect(steps[0]['ok'], 1);
      expect(steps[1]['paceSecPerKm'], 300.0);
      expect(
          ((row.metadata!['nested'] as Map)['deeper'] as Map)['good'], 2);
      expect(
          ((row.metadata!['nested'] as Map)['deeper'] as Map)
              .containsKey('bad'),
          isFalse);
    });

    test('a finite bag survives untouched', () {
      final row = runRowFromRun(
        _run(metadata: {'avg_bpm': 148, 'steps': 9001, 'note': 'x'}),
        userId: 'u',
      );
      expect(row.metadata, {'avg_bpm': 148, 'steps': 9001, 'note': 'x'});
    });

    test('an explicit null in the bag is preserved, not read as non-finite', () {
      final row = runRowFromRun(_run(metadata: {'note': null, 'ok': 1}),
          userId: 'u');
      expect(row.metadata!.containsKey('note'), isTrue);
      expect(row.metadata!['note'], isNull);
    });
  });

  group('runMetadataForRow (write-side bag strip)', () {
    test('strips activity_type + is_dnf from the persisted bag', () {
      expect(
        runMetadataForRow({
          MetadataKeys.activityType: 'cycle',
          MetadataKeys.isDnf: true,
          MetadataKeys.avgBpm: 142,
        }),
        {MetadataKeys.avgBpm: 142},
      );
    });

    test('strips the four promoted embedded-best keys', () {
      expect(
        runMetadataForRow({
          MetadataKeys.fastest5kS: 1170,
          MetadataKeys.fastest10kS: 2450,
          MetadataKeys.fastestHalfMarathonS: 5400,
          MetadataKeys.fastestMarathonS: 10500,
          MetadataKeys.avgBpm: 150,
        }),
        {MetadataKeys.avgBpm: 150},
      );
    });

    test('strips the two read-side storage stashes', () {
      expect(
        runMetadataForRow({
          MetadataKeys.trackUrl: 'u/run-1.json.gz',
          MetadataKeys.hrSeriesUrl: 'u/run-1.hr.json.gz',
          MetadataKeys.notes: 'felt good',
        }),
        {MetadataKeys.notes: 'felt good'},
      );
    });

    test('keeps elevation_m — 20270302_001 has writers populate both', () {
      expect(
        runMetadataForRow({MetadataKeys.elevationM: 312.5}),
        {MetadataKeys.elevationM: 312.5},
      );
    });

    test('collapses to null when only promoted keys were present', () {
      expect(
        runMetadataForRow(
            {MetadataKeys.activityType: 'run', MetadataKeys.isDnf: false}),
        isNull,
      );
    });

    test('null in, null out; the caller argument is not mutated', () {
      expect(runMetadataForRow(null), isNull);
      final input = {MetadataKeys.activityType: 'walk', MetadataKeys.steps: 9000};
      runMetadataForRow(input);
      expect(input[MetadataKeys.activityType], 'walk');
      expect(input[MetadataKeys.steps], 9000);
    });
  });

  group('runEmbeddedBestSeconds (bag to column lift)', () {
    test('lifts an int through, coerces a num, admits zero', () {
      expect(runEmbeddedBestSeconds({'fastest_5k_s': 1170}, 'fastest_5k_s'), 1170);
      expect(
          runEmbeddedBestSeconds({'fastest_5k_s': 1170.0}, 'fastest_5k_s'), 1170);
      expect(runEmbeddedBestSeconds({'fastest_5k_s': 0}, 'fastest_5k_s'), 0);
    });

    test('drops negative, non-numeric, absent and null-bag values', () {
      expect(runEmbeddedBestSeconds({'fastest_5k_s': -5}, 'fastest_5k_s'), isNull);
      expect(
          runEmbeddedBestSeconds({'fastest_5k_s': 'nope'}, 'fastest_5k_s'), isNull);
      expect(
          runEmbeddedBestSeconds({'fastest_10k_s': 2450}, 'fastest_5k_s'), isNull);
      expect(runEmbeddedBestSeconds(null, 'fastest_5k_s'), isNull);
    });
  });

  group('runPromotedDouble', () {
    test('takes a finite num, refuses everything else', () {
      expect(runPromotedDouble({'elevation_m': 312}, 'elevation_m'), 312.0);
      expect(runPromotedDouble({'elevation_m': double.nan}, 'elevation_m'), isNull);
      expect(
          runPromotedDouble({'elevation_m': double.infinity}, 'elevation_m'), isNull);
      expect(runPromotedDouble({'elevation_m': 'high'}, 'elevation_m'), isNull);
      expect(runPromotedDouble(null, 'elevation_m'), isNull);
    });
  });

  group('runRowFromRun', () {
    test('lifts every declared column out of the bag', () {
      final row = runRowFromRun(
        _run(metadata: {
          MetadataKeys.activityType: 'walk',
          MetadataKeys.isDnf: true,
          MetadataKeys.elevationM: 312.5,
          MetadataKeys.fastest5kS: 1170,
          MetadataKeys.fastest10kS: 2450,
          MetadataKeys.fastestHalfMarathonS: 5400,
          MetadataKeys.fastestMarathonS: 10500,
          MetadataKeys.notes: 'hilly',
        }),
        userId: 'owner-1',
      );
      expect(row.activityType, 'walk');
      expect(row.isDnf, isTrue);
      expect(row.elevationGainM, 312.5);
      expect(row.fastest5kS, 1170);
      expect(row.fastest10kS, 2450);
      expect(row.fastestHalfMarathonS, 5400);
      expect(row.fastestMarathonS, 10500);
      expect(row.metadata, {
        MetadataKeys.elevationM: 312.5,
        MetadataKeys.notes: 'hilly',
      });
    });

    test('defaults activity_type to run and is_dnf to false', () {
      final row = runRowFromRun(_run(), userId: 'owner-1');
      expect(row.activityType, 'run');
      expect(row.isDnf, isFalse);
      expect(row.metadata, isNull);
    });

    test('forces started_at to UTC', () {
      final local = DateTime(2026, 5, 1, 7, 30);
      final row = runRowFromRun(
        Run(
          id: 'r',
          startedAt: local,
          duration: const Duration(minutes: 10),
          distanceMetres: 1000,
          source: RunSource.app,
        ),
        userId: 'owner-1',
      );
      expect(row.startedAt.isUtc, isTrue);
      expect(row.startedAt, local.toUtc());
    });

    test('carries only the caller-supplied owner, track url and visibility',
        () {
      final row = runRowFromRun(_run(),
          userId: 'owner-1', trackUrl: 'owner-1/run-1.json.gz', isPublic: true);
      expect(row.userId, 'owner-1');
      expect(row.trackUrl, 'owner-1/run-1.json.gz');
      expect(row.isPublic, isTrue);
      expect(runRowFromRun(_run(), userId: '').trackUrl, isNull);
      expect(runRowFromRun(_run(), userId: '').isPublic, isNull);
      expect(runRowFromRun(_run(), userId: '').createdAt, isNull);
    });
  });

  group('promoted-column registry', () {
    Set<String> constValues(String path, {String? within}) {
      var text = File(path).readAsStringSync();
      if (within != null) {
        final start = text.indexOf(within);
        if (start < 0) throw StateError('$within not found in $path');
        final end = text.indexOf('\nclass ', start + 1);
        text = text.substring(start, end == -1 ? text.length : end);
      }
      return RegExp(r"static const String \w+ = '([^']+)';")
          .allMatches(text)
          .map((m) => m.group(1)!)
          .toSet();
    }

    final runColumns = constValues('lib/src/generated/db_rows.dart',
        within: 'class RunRow {');
    final metadataKeys = constValues('lib/src/metadata_keys.dart',
        within: 'class MetadataKeys {');

    test('every metadata key that names a runs column is declared', () {
      final overlap = metadataKeys.intersection(runColumns);
      expect(
        overlap,
        kRunPromotedMetadataColumns.keys.toSet(),
        reason: 'a migration promoted a metadata key into a same-named `runs` '
            'column. Decide whether the bag copy is a shadow (add it to '
            'kRunPromotedMetadataColumns, which drops it) or a deliberate '
            'double-write like elevation_m (kRunMirroredMetadataColumns), and '
            'lift it in runRowFromRun. A column no writer fills reads as 0 or '
            'null for every row the app writes.',
      );
    });

    test('every declared column exists on RunRow', () {
      for (final col in [
        ...kRunPromotedMetadataColumns.values,
        ...kRunMirroredMetadataColumns.values,
      ]) {
        expect(runColumns, contains(col));
      }
    });

    test('the mirrored keys are not also stripped', () {
      expect(
        kRunMirroredMetadataColumns.keys
            .toSet()
            .intersection(kRunPromotedMetadataColumns.keys.toSet()),
        isEmpty,
      );
    });

    test('runRowFromRun fills every declared column', () {
      final row = runRowFromRun(
        _run(metadata: {
          for (final k in kRunPromotedMetadataColumns.keys)
            k: k == MetadataKeys.activityType
                ? 'walk'
                : k == MetadataKeys.isDnf
                    ? true
                    : k.endsWith('_url')
                        ? 'owner/run-1.gz'
                        : 900,
          MetadataKeys.elevationM: 312.5,
        }),
        userId: 'owner-1',
        trackUrl: 'owner-1/run-1.json.gz',
      ).toJson();
      for (final col in [
        ...kRunPromotedMetadataColumns.values,
        ...kRunMirroredMetadataColumns.values,
      ]) {
        // hr_series_url has no bag lift: the column is written by the sidecar
        // upload, and the bag key is only the read-side stash.
        if (col == RunRow.colHrSeriesUrl) continue;
        expect(row[col], isNotNull, reason: '$col left unfilled');
      }
    });
  });
}
