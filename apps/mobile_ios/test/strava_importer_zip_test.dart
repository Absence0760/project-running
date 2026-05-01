import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/strava_importer.dart';

const _gpxOnePoint = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><trk><trkseg>
  <trkpt lat="47.37" lon="8.54"><ele>400</ele><time>2026-04-09T07:30:00Z</time></trkpt>
</trkseg></trk></gpx>''';

const _gpxTwoPoint = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><trk><trkseg>
  <trkpt lat="47.37" lon="8.54"><ele>400</ele><time>2026-04-09T07:30:00Z</time></trkpt>
  <trkpt lat="47.371" lon="8.541"><ele>405</ele><time>2026-04-09T08:00:00Z</time></trkpt>
</trkseg></trk></gpx>''';

const _gpxNoPoints = '''<?xml version="1.0"?>
<gpx version="1.1" creator="test"><metadata><name>Empty</name></metadata></gpx>''';

String csv(List<List<String>> rows) {
  final buf = StringBuffer();
  for (final row in rows) {
    final cells = row.map((c) {
      if (c.contains(',') || c.contains('"')) {
        return '"${c.replaceAll('"', '""')}"';
      }
      return c;
    });
    buf.writeln(cells.join(','));
  }
  return buf.toString();
}

const _stravaHeader = [
  'Activity ID',
  'Activity Date',
  'Activity Name',
  'Activity Type',
  'Distance',
  'Elapsed Time',
  'Filename',
];

Future<File> writeZip(
  Directory tmpDir, {
  required String csvContent,
  Map<String, String>? gpxFiles,
}) async {
  final archive = Archive()
    ..addFile(ArchiveFile(
      'activities.csv',
      csvContent.length,
      utf8.encode(csvContent),
    ));
  if (gpxFiles != null) {
    for (final entry in gpxFiles.entries) {
      archive.addFile(ArchiveFile(
        entry.key,
        entry.value.length,
        utf8.encode(entry.value),
      ));
    }
  }
  final bytes = ZipEncoder().encode(archive);
  final zip = File('${tmpDir.path}/strava.zip');
  await zip.writeAsBytes(bytes);
  return zip;
}

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('strava_importer_test_');
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  group('activity_type derivation from Strava type column', () {
    Future<String> activityTypeFor(String stravaType) async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', stravaType, '5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1), reason: 'failed for "$stravaType"');
      return r.runs.first.metadata!['activity_type'] as String;
    }

    test('"Run" → "run"', () async {
      expect(await activityTypeFor('Run'), 'run');
    });

    test('"Walk" → "walk"', () async {
      expect(await activityTypeFor('Walk'), 'walk');
    });

    test('"Hike" → "hike"', () async {
      expect(await activityTypeFor('Hike'), 'hike');
    });

    test('"Trail Running" still maps to "run"', () async {
      expect(await activityTypeFor('Trail Running'), 'run');
    });

    test('Case-insensitive match: "WALKING" → "walk"', () async {
      expect(await activityTypeFor('WALKING'), 'walk');
    });

    test('Unknown activity type falls back to "run"', () async {
      expect(await activityTypeFor('Yoga'), 'run');
    });
  });

  group('csv column handling', () {
    test('throws when activities.csv is absent', () async {
      final archive = Archive()
        ..addFile(ArchiveFile('readme.txt', 1, utf8.encode('x')));
      final zip = File('${tmpDir.path}/empty.zip')
        ..writeAsBytesSync(ZipEncoder().encode(archive));

      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when filename column is missing', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          ['Activity ID', 'Activity Date', 'Activity Name'],
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X'],
        ]),
      );
      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when activity date column is missing', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          ['Activity ID', 'Activity Name', 'Filename'],
          ['1', 'X', 'activities/1.gpx'],
        ]),
      );
      await expectLater(
        StravaImporter.importFromZip(zip),
        throwsA(isA<FormatException>()),
      );
    });

    test('header-only CSV produces empty result, no errors', () async {
      final zip = await writeZip(tmpDir, csvContent: csv([_stravaHeader]));
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, isEmpty);
      expect(r.errors, isEmpty);
    });

    test('row with empty filename is silently skipped', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '1500', ''],
        ]),
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, isEmpty);
      expect(r.errors, isEmpty);
    });

    test('"distance (km)" header variant is recognised', () async {
      final header = [..._stravaHeader];
      header[4] = 'Distance (km)';
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          header,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '8.5', '0',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxOnePoint},
      );
      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs, hasLength(1));
      expect(r.runs.first.distanceMetres, 8500);
    });
  });

  group('multi-row imports', () {
    test('imports multiple activities in one zip', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/1.gpx'],
          ['2', 'Apr 10, 2026, 8:00:00 AM', 'B', 'Walk', '3', '2000',
              'activities/2.gpx'],
        ]),
        gpxFiles: {
          'activities/1.gpx': _gpxTwoPoint,
          'activities/2.gpx': _gpxTwoPoint,
        },
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(2));
      expect(r.runs.map((r) => r.externalId), ['strava:1', 'strava:2']);
      expect(r.runs[0].metadata!['activity_type'], 'run');
      expect(r.runs[1].metadata!['activity_type'], 'walk');
    });

    test('one missing track file errors but the rest still import', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/missing.gpx'],
          ['2', 'Apr 10, 2026, 8:00:00 AM', 'B', 'Run', '5', '1500',
              'activities/2.gpx'],
        ]),
        gpxFiles: {'activities/2.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(1));
      expect(r.runs.single.externalId, 'strava:2');
      expect(r.errors, hasLength(1));
      expect(r.errors.single.filename, 'activities/missing.gpx');
    });

    test('unknown track extension is reported as a per-file error', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
              'activities/1.bin'],
        ]),
        gpxFiles: {'activities/1.bin': '<not real>'},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, isEmpty);
      expect(r.errors, hasLength(1));
      expect(r.errors.single.message, contains('Unknown'));
    });
  });

  group('distance and duration fallback', () {
    test('distance falls back to CSV when GPX has no waypoints', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '7.5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxNoPoints},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.distanceMetres, 7500);
    });

    test('duration falls back to CSV elapsed when track has <2 waypoints',
        () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '1234',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxOnePoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.duration, const Duration(seconds: 1234));
    });

    test('duration uses GPX timestamps when CSV elapsed is 0', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'X', 'Run', '5', '0',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs.single.duration, const Duration(minutes: 30));
    });
  });

  group('metadata population', () {
    test('imported_from + strava_activity_type + title are set', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', 'My Tempo', 'Trail Running', '5',
              '1500', 'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);
      final m = r.runs.single.metadata!;

      expect(m['imported_from'], 'strava');
      expect(m['strava_activity_type'], 'Trail Running');
      expect(m['title'], 'My Tempo');
      expect(m['activity_type'], 'run');
      expect(m.containsKey('imported_at'), isTrue);
    });

    test('blank activity name falls back to "Strava import"', () async {
      final zip = await writeZip(
        tmpDir,
        csvContent: csv([
          _stravaHeader,
          ['1', 'Apr 9, 2026, 7:30:00 AM', '', 'Run', '5', '1500',
              'activities/1.gpx'],
        ]),
        gpxFiles: {'activities/1.gpx': _gpxTwoPoint},
      );

      final r = await StravaImporter.importFromZip(zip);
      expect(r.runs.single.metadata!['title'], 'Strava import');
    });
  });

  group('compressed track files', () {
    test('.gpx.gz is decompressed before parsing', () async {
      final gz = GZipEncoder().encode(utf8.encode(_gpxTwoPoint));
      final csvContent = csv([
        _stravaHeader,
        ['1', 'Apr 9, 2026, 7:30:00 AM', 'A', 'Run', '5', '1500',
            'activities/1.gpx.gz'],
      ]);
      final archive = Archive()
        ..addFile(ArchiveFile(
          'activities.csv',
          csvContent.length,
          utf8.encode(csvContent),
        ))
        ..addFile(
            ArchiveFile('activities/1.gpx.gz', gz.length, gz));
      final bytes = ZipEncoder().encode(archive);
      final zip = File('${tmpDir.path}/gz.zip')..writeAsBytesSync(bytes);

      final r = await StravaImporter.importFromZip(zip);

      expect(r.runs, hasLength(1));
      expect(r.runs.single.track, hasLength(2));
    });
  });
}
