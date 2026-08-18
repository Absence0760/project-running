import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/screens/import_screen.dart';

/// Behavioural cover for the three file-picked import paths — Strava export
/// ZIP, CSV summary, full-backup ZIP.
///
/// § 659 seamed the four Health Connect platform calls but not `FilePicker`,
/// so these three could only ever be driven as far as their parser; the
/// screen's own reading, error handling and reporting around it were
/// untested. `pickFilesFn` is the same nullable-`…Fn`-defaulting-to-the-real-
/// static seam, so each path runs end to end against a file on disk.
///
/// What is deliberately NOT re-tested here is the shared `_saveImportedRuns`
/// push loop — `import_cloud_push_deferred_test.dart` owns that.

late Directory _tmp;

Future<LocalRunStore> _makeStore() async {
  final store = LocalRunStore();
  await store.init(
      overrideDirectory: Directory('${_tmp.path}/runs')..createSync());
  return store;
}

File _write(String name, List<int> bytes) =>
    File('${_tmp.path}/$name')..writeAsBytesSync(bytes);

Future<FilePickerResult?> Function({
  FileType type,
  List<String>? allowedExtensions,
}) _picks(File? file, {bool withoutPath = false}) =>
    ({FileType type = FileType.any, List<String>? allowedExtensions}) async =>
        file == null
            ? null
            : FilePickerResult([
                PlatformFile(
                  path: withoutPath ? null : file.path,
                  name: file.uri.pathSegments.last,
                  size: file.lengthSync(),
                ),
              ]);

const _gpx = '''<?xml version="1.0" encoding="UTF-8"?>
<gpx version="1.1" creator="Strava"><trk><name>Morning Run</name><trkseg>
<trkpt lat="51.5000" lon="-0.1000"><ele>10</ele><time>2026-04-09T07:30:00Z</time></trkpt>
<trkpt lat="51.5090" lon="-0.1000"><ele>12</ele><time>2026-04-09T07:35:00Z</time></trkpt>
<trkpt lat="51.5180" lon="-0.1000"><ele>11</ele><time>2026-04-09T07:40:00Z</time></trkpt>
</trkseg></trk></gpx>''';

Uint8List _stravaZip({String? csv, bool withTrack = true}) {
  final archive = Archive();
  final body = csv ??
      'Activity ID,Activity Date,Activity Name,Activity Type,Elapsed Time,Filename\n'
          '778899,"Apr 9, 2026, 7:30:00 AM",Morning Run,Run,1800,activities/778899.gpx\n';
  final csvBytes = utf8.encode(body);
  archive.addFile(ArchiveFile('activities.csv', csvBytes.length, csvBytes));
  if (withTrack) {
    final gpx = utf8.encode(_gpx);
    archive.addFile(ArchiveFile('activities/778899.gpx', gpx.length, gpx));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void _addJson(Archive archive, String path, Object body) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}

Uint8List _backupZip({Map<String, dynamic>? manifest}) {
  final archive = Archive();
  _addJson(
      archive,
      'manifest.json',
      manifest ??
          {
            'format': 'run-app-backup',
            'version': 1,
            'exported_at': '2026-04-09T00:00:00Z',
          });
  _addJson(archive, 'runs.json', [
    {
      'id': 'backup-run-1',
      'started_at': '2026-04-09T07:30:00Z',
      'duration_s': 1800,
      'distance_m': 5000,
      'source': 'app',
      'metadata': {'activity_type': 'run'},
    },
  ]);
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<void> _pump(
  WidgetTester tester,
  LocalRunStore store,
  File? picked, {
  bool withoutPath = false,
}) async {
  await tester.binding.setSurfaceSize(const Size(800, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ImportScreen(
          runStore: store,
          pickFilesFn: _picks(picked, withoutPath: withoutPath)),
    ),
  );
  await tester.pump();
}

/// Drives a tap through real disk I/O and `compute` — neither can be advanced
/// by the fake clock.
Future<void> _tapAndDrain(WidgetTester tester, Finder button) async {
  await tester.ensureVisible(button);
  await tester.pump();
  await tester.runAsync(() async {
    await tester.tap(button);
    await tester.pump();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  });
  await tester.pump();
}

Finder get _stravaButton =>
    find.widgetWithText(FilledButton, 'Import Strava ZIP');
Finder get _csvButton => find.widgetWithText(FilledButton, 'Import CSV');
Finder get _backupButton =>
    find.widgetWithText(FilledButton, 'Restore backup ZIP');

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  setUp(() {
    _tmp = Directory.systemTemp.createTempSync('import_paths_test_');
  });
  tearDown(() {
    if (_tmp.existsSync()) _tmp.deleteSync(recursive: true);
  });

  group('Strava export ZIP', () {
    testWidgets('a well-formed export imports its activities', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store, _write('strava.zip', _stravaZip()));

      await _tapAndDrain(tester, _stravaButton);

      expect(store.summaryRuns, hasLength(1));
      final saved = await store.runById(store.summaryRuns.single.id);
      expect(saved!.externalId, 'strava:778899');
      expect(saved.track, hasLength(3));
      expect(saved.metadata?['title'], 'Morning Run');
      expect(find.text(l10n.importStatusImported(1, 'Strava')), findsOneWidget);
    });

    testWidgets('a ZIP that is not a Strava export says so', (tester) async {
      final store = await _makeStore();
      final archive = Archive();
      final junk = utf8.encode('nothing here');
      archive.addFile(ArchiveFile('readme.txt', junk.length, junk));
      await _pump(
          tester, store, _write('other.zip', ZipEncoder().encode(archive)));

      await _tapAndDrain(tester, _stravaButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.textContaining('Not a Strava export'), findsOneWidget);
    });

    testWidgets('a file that is not a ZIP fails visibly rather than silently',
        (tester) async {
      final store = await _makeStore();
      await _pump(tester, store,
          _write('corrupt.zip', utf8.encode('this is not a zip archive')));

      await _tapAndDrain(tester, _stravaButton);

      expect(store.summaryRuns, isEmpty);
      // The message is the decoder's, but something failure-shaped must show:
      // a silent "nothing happened" is the outcome the report exists to stop.
      expect(find.textContaining('Import failed:'), findsOneWidget);
    });

    testWidgets('a row whose track file is missing is reported, not dropped',
        (tester) async {
      final store = await _makeStore();
      await _pump(
          tester, store, _write('strava.zip', _stravaZip(withTrack: false)));

      await _tapAndDrain(tester, _stravaButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.text(l10n.importFailuresHeading(1)), findsOneWidget);
      expect(
          find.text(l10n.importStatusImportedWithErrors(0, 1)), findsOneWidget);
    });

    testWidgets('a cancelled pick changes nothing', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store, null);

      await _tapAndDrain(tester, _stravaButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.text(l10n.importStatusReadingExport), findsNothing);
    });
  });

  group('CSV summary', () {
    testWidgets('a well-formed CSV imports its rows', (tester) async {
      final store = await _makeStore();
      await _pump(
        tester,
        store,
        _write(
            'runs.csv',
            utf8.encode('date,distance_m,duration_s,pace_s_per_km,source\n'
                '2026-04-09T07:30:00Z,5000,1800,360,app\n'
                '2026-04-10T07:30:00Z,10000,3600,360,app\n')),
      );

      await _tapAndDrain(tester, _csvButton);

      expect(store.summaryRuns, hasLength(2));
      expect(find.text(l10n.importStatusImported(2, 'CSV')), findsOneWidget);
    });

    testWidgets('a header missing required columns is reported',
        (tester) async {
      final store = await _makeStore();
      await _pump(
        tester,
        store,
        _write('bad.csv', utf8.encode('name,notes\nMorning run,felt good\n')),
      );

      await _tapAndDrain(tester, _csvButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.text(l10n.importFailuresHeading(1)), findsOneWidget);
      await tester.tap(find.text(l10n.importFailuresShowDetail));
      await tester.pumpAndSettle();
      expect(find.textContaining(l10n.importFailuresReasonUnparseable),
          findsWidgets);
    });

    testWidgets('an unreadable row fails alone, not the whole file',
        (tester) async {
      final store = await _makeStore();
      await _pump(
        tester,
        store,
        _write(
            'mixed.csv',
            utf8.encode('date,distance_m,duration_s\n'
                '2026-04-09T07:30:00Z,5000,1800\n'
                'not-a-date,5000,1800\n')),
      );

      await _tapAndDrain(tester, _csvButton);

      expect(store.summaryRuns, hasLength(1));
      expect(
          find.text(l10n.importStatusImportedWithErrors(1, 1)), findsOneWidget);
      expect(find.text(l10n.importFailuresHeading(1)), findsOneWidget);
    });
  });

  group('backup ZIP', () {
    testWidgets('a well-formed backup restores its runs', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store, _write('backup.zip', _backupZip()));

      await _tapAndDrain(tester, _backupButton);

      expect(store.summaryRuns.single.id, 'backup-run-1');
      expect(
          find.text(l10n.importStatusBackupRestored(1, 0, 0)), findsOneWidget);
      expect(find.text(l10n.importErrorsHeader), findsOneWidget);
    });

    testWidgets('an archive that is not a backup says so', (tester) async {
      final store = await _makeStore();
      await _pump(
        tester,
        store,
        _write('notbackup.zip',
            _backupZip(manifest: {'format': 'something-else', 'version': 1})),
      );

      await _tapAndDrain(tester, _backupButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.textContaining('Not a valid backup'), findsOneWidget);
    });

    testWidgets('a backup from a newer app version refuses', (tester) async {
      final store = await _makeStore();
      await _pump(
        tester,
        store,
        _write('newer.zip',
            _backupZip(manifest: {'format': 'run-app-backup', 'version': 99})),
      );

      await _tapAndDrain(tester, _backupButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.textContaining('Backup restore failed:'), findsOneWidget);
    });

    testWidgets('a pick with no readable path is a no-op on all three paths',
        (tester) async {
      // A `FilePickerResult` can carry a `PlatformFile` with a null `path`.
      // The CSV and backup paths guarded it; the Strava path dereferenced it
      // with `!`, so the runner was shown a Dart null-check error instead.
      final store = await _makeStore();
      await _pump(tester, store, _write('any.zip', _stravaZip()),
          withoutPath: true);

      for (final button in [_stravaButton, _csvButton, _backupButton]) {
        await _tapAndDrain(tester, button);
        expect(find.textContaining('Null check operator'), findsNothing);
      }
      expect(store.summaryRuns, isEmpty);
    });

    testWidgets('a file that is not a ZIP fails visibly', (tester) async {
      final store = await _makeStore();
      await _pump(tester, store,
          _write('corrupt2.zip', utf8.encode('definitely not a zip')));

      await _tapAndDrain(tester, _backupButton);

      expect(store.summaryRuns, isEmpty);
      expect(find.textContaining('Backup restore failed:'), findsOneWidget);
    });
  });
}
