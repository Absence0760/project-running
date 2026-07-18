import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/imported_run_id.dart';
import '../lib/strava_importer.dart';

void main() {
  // Build the minimal one-activity Strava export ZIP the prefix + id-stability
  // tests share.
  Future<File> buildStravaZip() async {
    const csvContent = 'Activity ID,Activity Date,Activity Name,Activity Type,'
        'Distance,Elapsed Time,Filename\r\n'
        '98765,"Apr 9, 2026, 7:30:00 AM",Morning Run,Run,'
        '5.0,1800,activities/98765.gpx\r\n';

    const gpxContent = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="test">
  <trk><trkseg>
    <trkpt lat="47.37" lon="8.54">
      <ele>400</ele>
      <time>2026-04-09T07:30:00Z</time>
    </trkpt>
    <trkpt lat="47.38" lon="8.55">
      <ele>405</ele>
      <time>2026-04-09T08:00:00Z</time>
    </trkpt>
  </trkseg></trk>
</gpx>''';

    final archive = Archive()
      ..addFile(ArchiveFile(
          'activities.csv', csvContent.length, utf8.encode(csvContent)))
      ..addFile(ArchiveFile(
          'activities/98765.gpx', gpxContent.length, utf8.encode(gpxContent)));
    final zipBytes = ZipEncoder().encode(archive);

    final tmpDir = Directory.systemTemp.createTempSync('strava_import_test_');
    final zipFile = File('${tmpDir.path}/strava_export.zip');
    await zipFile.writeAsBytes(zipBytes);
    return zipFile;
  }

  group('StravaImporter external_id prefix', () {
    test('external_id is prefixed with strava:', () async {
      final zipFile = await buildStravaZip();
      final tmpDir = zipFile.parent;
      try {
        final result = await StravaImporter.importFromZip(zipFile);
        expect(result.runs, hasLength(1));
        expect(result.runs.first.externalId, startsWith('strava:'));
        expect(result.runs.first.externalId, equals('strava:98765'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });

  group('StravaImporter re-import id stability (#361)', () {
    test('a second import of the same ZIP yields an identical, stable id',
        () async {
      final zipFile = await buildStravaZip();
      final tmpDir = zipFile.parent;
      try {
        final first = await StravaImporter.importFromZip(zipFile);
        final second = await StravaImporter.importFromZip(zipFile);
        expect(first.runs, hasLength(1));
        expect(second.runs, hasLength(1));
        // Same external_id → same local id, so LocalRunStore.save dedupes the
        // re-import and the server upsert never rewrites the primary key.
        expect(first.runs.first.id, second.runs.first.id);
        expect(first.runs.first.id,
            stableRunIdFromExternalId('strava:98765'));
      } finally {
        tmpDir.deleteSync(recursive: true);
      }
    });
  });

  // HealthConnectImporter.fetchWorkouts calls Health.getHealthDataFromTypes,
  // which requires the Android Health Connect platform channel and cannot
  // run in a unit-test environment. The namespace prefix
  // 'healthconnect:${point.uuid}' is verified by static inspection: the
  // fixed line is the only assignment of externalId in that file.
  //
  // If a seam for injection is added in future (e.g. a Health factory
  // parameter), add an integration test here covering the prefix.
  group('HealthConnectImporter external_id prefix', () {
    test('externalId format constant is namespaced', () {
      // Read the source file and assert the fixed line is present.
      final source = File(
        'lib/health_connect_importer.dart',
      ).readAsStringSync();
      expect(source, contains("'healthconnect:\${point.uuid}'"));
    });

    test('id is derived from the stable external_id, not a fresh uuid (#361)',
        () {
      final source = File(
        'lib/health_connect_importer.dart',
      ).readAsStringSync();
      expect(source, contains('stableRunIdFromExternalId(externalId)'));
      expect(source, isNot(contains('_uuid.v4()')));
    });
  });
}
