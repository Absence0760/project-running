import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/backup.dart';
import '../lib/backup_server_client.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

class _OfflineApi extends ApiClient {
  @override
  String? get userId => null;
}

Map<String, dynamic> runRow({
  required String id,
  String startedAt = '2026-04-10T08:00:00Z',
  int durationS = 1500,
  double distanceM = 5000,
  String source = 'app',
  Map<String, dynamic>? metadata,
  String? routeId,
  String? trackUrl,
}) {
  return <String, dynamic>{
    'id': id,
    'started_at': startedAt,
    'duration_s': durationS,
    'distance_m': distanceM,
    'route_id': routeId,
    'source': source,
    'external_id': null,
    'metadata': metadata,
    'created_at': null,
    'updated_at': null,
    'track_url': trackUrl,
    'is_public': null,
    'event_id': null,
  };
}

Map<String, dynamic> routeRow({
  required String id,
  String name = 'Park loop',
  List<Map<String, dynamic>>? waypoints,
  double distanceM = 5000,
}) {
  return <String, dynamic>{
    'id': id,
    'name': name,
    'waypoints': waypoints ??
        const [
          {'lat': 0.0, 'lng': 0.0},
          {'lat': 0.0, 'lng': 0.001},
        ],
    'distance_m': distanceM,
    'elevation_m': null,
    'surface': null,
    'is_public': false,
    'slug': null,
    'created_at': null,
    'updated_at': null,
    'tags': const <String>[],
    'featured': false,
    'run_count': 0,
    'is_starred': false,
  };
}

void addJson(Archive archive, String path, Object body) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(body)));
  archive.addFile(ArchiveFile(path, bytes.length, bytes));
}

void addGzippedTrack(
  Archive archive,
  String runId,
  List<Map<String, dynamic>> waypoints,
) {
  final json = jsonEncode(waypoints);
  final gz = Uint8List.fromList(GZipEncoder().encode(utf8.encode(json)));
  archive.addFile(
    ArchiveFile('tracks/$runId.json.gz', gz.length, gz),
  );
}

Uint8List buildBackupZip({
  Map<String, dynamic>? manifestOverride,
  List<Map<String, dynamic>>? runs,
  List<Map<String, dynamic>>? routes,
  Map<String, List<Map<String, dynamic>>>? tracksByRunId,
}) {
  final archive = Archive();
  addJson(archive, 'manifest.json', manifestOverride ??
      {
        'format': 'run-app-backup',
        'version': 1,
        'exported_at': DateTime.now().toUtc().toIso8601String(),
      });
  if (runs != null) addJson(archive, 'runs.json', runs);
  if (routes != null) addJson(archive, 'routes.json', routes);
  if (tracksByRunId != null) {
    for (final entry in tracksByRunId.entries) {
      addGzippedTrack(archive, entry.key, entry.value);
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  setUpAll(_ensureSupabase);

  late Directory tempDir;
  late LocalRunStore runStore;
  late LocalRouteStore routeStore;
  late File zipFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('backup_test_');
    runStore = LocalRunStore();
    routeStore = LocalRouteStore();
    await runStore.init(overrideDirectory: Directory('${tempDir.path}/runs')..createSync());
    await routeStore.init(overrideDirectory: Directory('${tempDir.path}/routes')..createSync());
    zipFile = File('${tempDir.path}/backup.zip');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<RestoreResult> restoreFromBytes(
    Uint8List bytes, {
    bool generateNewIds = false,
  }) async {
    await zipFile.writeAsBytes(bytes);
    final svc = BackupService(api: _OfflineApi());
    return svc.restore(
      zipFile: zipFile,
      runStore: runStore,
      routeStore: routeStore,
      generateNewIds: generateNewIds,
    );
  }

  group('manifest validation', () {
    test('throws when manifest is missing entirely', () async {
      final archive = Archive();
      addJson(archive, 'runs.json', const []);
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      await zipFile.writeAsBytes(bytes);

      final svc = BackupService(api: _OfflineApi());

      expect(
        () => svc.restore(zipFile: zipFile, runStore: runStore),
        throwsException,
      );
    });

    test('throws when manifest format does not match', () async {
      final bytes = buildBackupZip(manifestOverride: {
        'format': 'something-else',
        'version': 1,
      });

      expect(restoreFromBytes(bytes), throwsException);
    });

    test('throws when version is newer than supported (forward-compat guard)',
        () async {
      final bytes = buildBackupZip(manifestOverride: {
        'format': 'run-app-backup',
        'version': 99,
      });

      expect(restoreFromBytes(bytes), throwsException);
    });

    test('accepts the current version', () async {
      final bytes = buildBackupZip(runs: const []);
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 0);
    });
  });

  group('offline restore — runs', () {
    test('empty runs.json restores nothing', () async {
      final result = await restoreFromBytes(buildBackupZip(runs: const []));
      expect(result.runsImported, 0);
      expect(runStore.runs, isEmpty);
    });

    test('single run lands in LocalRunStore with id preserved', () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(runStore.runs, hasLength(1));
      final r = runStore.runs.single;
      expect(r.id, 'r-1');
      expect(r.distanceMetres, 5000);
      expect(r.duration, const Duration(seconds: 1500));
    });

    test('default activity_type is "run" when metadata missing the key',
        () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1', metadata: {'avg_bpm': 142}),
      ]);

      await restoreFromBytes(bytes);

      expect(runStore.runs.single.metadata?['activity_type'], 'run');
      expect(runStore.runs.single.metadata?['avg_bpm'], 142);
    });

    test('preserves explicit activity_type from metadata', () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1', metadata: {'activity_type': 'cycle'}),
      ]);

      await restoreFromBytes(bytes);

      expect(runStore.runs.single.metadata?['activity_type'], 'cycle');
    });

    test('decodes a gzipped track and attaches waypoints to the Run',
        () async {
      final bytes = buildBackupZip(
        runs: [runRow(id: 'r-1')],
        tracksByRunId: {
          'r-1': const [
            {'lat': 47.37, 'lng': 8.54, 'ele': 408.0, 'ts': '2026-04-10T08:00:00.000Z'},
            {'lat': 47.371, 'lng': 8.541, 'ele': 410.0, 'ts': '2026-04-10T08:00:30.000Z'},
          ],
        },
      );

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(result.tracksUploaded, 1);
      final r = runStore.runs.single;
      expect(r.track, hasLength(2));
      expect(r.track.first.lat, 47.37);
      expect(r.track.first.elevationMetres, 408.0);
      expect(r.track.first.timestamp,
          DateTime.utc(2026, 4, 10, 8, 0, 0));
    });

    test('unknown source falls back to RunSource.app', () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1', source: 'made-up-source'),
      ]);

      await restoreFromBytes(bytes);

      expect(runStore.runs.single.source.name, 'app');
    });

    test('generateNewIds replaces ids — original ids are not in the store',
        () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'original-id-1'),
        runRow(id: 'original-id-2'),
      ]);

      await restoreFromBytes(bytes, generateNewIds: true);

      expect(runStore.runs, hasLength(2));
      expect(runStore.runs.map((r) => r.id), isNot(contains('original-id-1')));
      expect(runStore.runs.map((r) => r.id), isNot(contains('original-id-2')));
    });

    test('non-Map run entry is skipped without crashing', () async {
      final archive = Archive();
      addJson(archive, 'manifest.json',
          {'format': 'run-app-backup', 'version': 1});
      addJson(archive, 'runs.json', [
        'not-a-map',
        runRow(id: 'r-good'),
      ]);
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(runStore.runs.single.id, 'r-good');
    });

    test('malformed run row is captured as a warning, others continue',
        () async {
      final bytes = buildBackupZip(runs: [
        {'id': 'broken'},
        runRow(id: 'r-good'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(result.warnings.any((w) => w.contains('broken')), isTrue);
    });
  });

  group('offline restore — routes', () {
    test('single route lands in LocalRouteStore with waypoints intact',
        () async {
      final bytes = buildBackupZip(
        runs: const [],
        routes: [
          routeRow(
            id: 'rt-1',
            name: 'River loop',
            waypoints: const [
              {'lat': 0.0, 'lng': 0.0, 'ele': 100.0},
              {'lat': 0.0, 'lng': 0.001, 'ele': 110.0},
            ],
          ),
        ],
      );

      final result = await restoreFromBytes(bytes);

      expect(result.routesImported, 1);
      expect(routeStore.routes, hasLength(1));
      final r = routeStore.routes.single;
      expect(r.id, 'rt-1');
      expect(r.name, 'River loop');
      expect(r.waypoints, hasLength(2));
      expect(r.waypoints.first.elevationMetres, 100.0);
    });

    test('null route name falls back to "Route"', () async {
      final bytes = buildBackupZip(routes: [
        {
          ...routeRow(id: 'rt-1'),
          'name': null,
        },
      ]);

      await restoreFromBytes(bytes);

      expect(routeStore.routes.single.name, 'Route');
    });

    test('generateNewIds replaces route ids', () async {
      final bytes = buildBackupZip(routes: [
        routeRow(id: 'orig-1'),
        routeRow(id: 'orig-2'),
      ]);

      await restoreFromBytes(bytes, generateNewIds: true);

      expect(routeStore.routes, hasLength(2));
      expect(
        routeStore.routes.map((r) => r.id),
        isNot(contains('orig-1')),
      );
    });

    test('non-Map waypoint entries inside a route are silently skipped',
        () async {
      final bytes = buildBackupZip(routes: [
        {
          ...routeRow(id: 'rt-1'),
          'waypoints': [
            {'lat': 0, 'lng': 0},
            'garbage',
            {'lat': 0, 'lng': 0.001},
          ],
        },
      ]);

      await restoreFromBytes(bytes);

      expect(routeStore.routes.single.waypoints, hasLength(2));
    });
  });

  group('offline restore — guard clauses', () {
    test('throws when no stores are supplied and offline', () async {
      final bytes = buildBackupZip(runs: const []);
      await zipFile.writeAsBytes(bytes);
      final svc = BackupService(api: _OfflineApi());

      expect(
        () => svc.restore(zipFile: zipFile),
        throwsException,
      );
    });

    test('runs branch leaves a warning when only routeStore was supplied',
        () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1'),
      ], routes: const []);
      await zipFile.writeAsBytes(bytes);
      final svc = BackupService(api: _OfflineApi());

      final result = await svc.restore(
        zipFile: zipFile,
        routeStore: routeStore,
      );

      expect(result.runsImported, 0);
      expect(result.warnings.any((w) => w.contains('LocalRunStore')), isTrue);
    });
  });

  group('progress reporting', () {
    test('emits stage events through the optional callback', () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-1'),
      ]);
      await zipFile.writeAsBytes(bytes);
      final svc = BackupService(api: _OfflineApi());

      final stages = <String>[];
      await svc.restore(
        zipFile: zipFile,
        runStore: runStore,
        routeStore: routeStore,
        onProgress: (p) => stages.add(p.stage),
      );

      expect(stages.first, 'reading');
      expect(stages.last, 'done');
      expect(stages, contains('runs'));
    });
  });

  // Regression group for the offline-restore-without-credentials bug
  // (commit fc716ea). Pre-fix, `BackupService` required a non-null
  // `ApiClient` and read `Supabase.instance.client` eagerly in its
  // constructor, so a release APK built without --dart-define
  // SUPABASE_URL/ANON_KEY couldn't restore a backup at all — the user
  // saw "Backup service unavailable." even though the offline path
  // doesn't touch Supabase or the network.
  group('no-credentials path — api: null', () {
    test('BackupService(api: null) constructs without throwing', () {
      // The smoke test for the constructor relaxation. If this throws,
      // the release APK regresses to the pre-fix behaviour.
      expect(() => BackupService(api: null), returnsNormally);
    });

    test('restore with api: null routes to offline and writes runStore',
        () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-no-creds-1', distanceM: 4321),
        runRow(id: 'r-no-creds-2', distanceM: 5555),
      ]);
      await zipFile.writeAsBytes(bytes);
      final svc = BackupService(api: null);

      final result = await svc.restore(
        zipFile: zipFile,
        runStore: runStore,
      );

      expect(result.runsImported, 2);
      expect(
        runStore.runs.map((r) => r.id).toList(),
        containsAll(['r-no-creds-1', 'r-no-creds-2']),
      );
      // The offline branch advertises this warning so the user knows
      // why their profile / settings weren't restored.
      expect(
        result.warnings.any((w) => w.contains('Restoring offline')),
        isTrue,
      );
    });

    test('restore with api: null still throws when no stores are supplied',
        () async {
      // The "you forgot to wire a store" case stays a hard failure —
      // the offline branch needs somewhere to land the rows.
      final bytes = buildBackupZip(runs: const []);
      await zipFile.writeAsBytes(bytes);
      final svc = BackupService(api: null);

      expect(() => svc.restore(zipFile: zipFile), throwsException);
    });

    test('createBackup with api: null throws a clear error', () async {
      // Read-side requires creds; this test pins that we report the
      // unavailability cleanly rather than NPEing on a null
      // `Supabase.instance.client`.
      final svc = BackupService(api: null);
      final out = File('${tempDir.path}/should-not-be-written.zip');

      await expectLater(
        () => svc.createBackup(outputFile: out),
        throwsA(predicate(
          (e) => e.toString().contains('Backup unavailable'),
        )),
      );
      expect(out.existsSync(), isFalse);
    });
  });

  // ---- writeBackupZipStreaming: the streaming + parallel writer ----
  //
  // Exercises the testable seam extracted from `createBackup` (which
  // requires a live ApiClient + Supabase). The writer is responsible
  // for: opening a ZipFileEncoder on disk, downloading tracks in
  // bounded-concurrency batches, dropping each track's bytes after
  // it's written, and finalising the archive. The downstream restore
  // path is the existing contract — these tests round-trip end-to-
  // end through restore to prove the on-disk format hasn't drifted.
  group('writeBackupZipStreaming', () {
    /// Test fetcher that hands back deterministic gzipped bytes per
    /// `track_url` and records concurrent + total invocations so the
    /// concurrency contract is observable from the outside.
    final Map<String, Uint8List> trackBlobs = {};
    int inFlight = 0;
    int peakInFlight = 0;
    int totalCalls = 0;
    Future<Uint8List> fetcher(String path) async {
      totalCalls++;
      inFlight++;
      if (inFlight > peakInFlight) peakInFlight = inFlight;
      // Yield so concurrent calls observably overlap rather than
      // round-tripping synchronously and resetting peakInFlight to 1.
      await Future<void>.delayed(const Duration(milliseconds: 5));
      inFlight--;
      final bytes = trackBlobs[path];
      if (bytes == null) {
        throw StateError('test fetcher: no blob for $path');
      }
      return bytes;
    }

    setUp(() {
      trackBlobs.clear();
      inFlight = 0;
      peakInFlight = 0;
      totalCalls = 0;
    });

    Uint8List gzipOf(List<Map<String, dynamic>> waypoints) {
      final body = utf8.encode(jsonEncode(waypoints));
      return Uint8List.fromList(GZipEncoder().encode(body));
    }

    test('writes a valid backup that restores cleanly via the existing decoder',
        () async {
      const trackUrl = 'uid/r-1.json.gz';
      trackBlobs[trackUrl] = gzipOf(const [
        {'lat': 47.37, 'lng': 8.54},
        {'lat': 47.371, 'lng': 8.541},
      ]);

      final out = File('${tempDir.path}/streamed.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1', trackUrl: trackUrl)],
        routesOut: [routeRow(id: 'rt-1', name: 'My route')],
        profile: const {'username': 'tester'},
        settingsPrefs: const {'unit': 'km'},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: [runRow(id: 'r-1', trackUrl: trackUrl)],
        fetchTrackBytes: fetcher,
      );

      expect(out.existsSync(), isTrue);
      // Round-trip through the existing restore decoder — proves the
      // on-disk format hasn't drifted.
      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(
        zipFile: out,
        runStore: runStore,
        routeStore: routeStore,
      );
      expect(res.runsImported, 1);
      expect(res.routesImported, 1);
      expect(res.tracksUploaded, 1);
      // Track lat/lng survived the round-trip.
      final restored = runStore.runs.single;
      expect(restored.track.first.lat, 47.37);
      expect(restored.track.last.lng, 8.541);
    });

    test('archives indoor HR sidecars under hr/ + counts them (decisions §116)',
        () async {
      const trackUrl = 'uid/r-1.json.gz';
      const hrUrl = 'uid/r-2.hr.json.gz';
      trackBlobs[trackUrl] = gzipOf(const [
        {'lat': 1.0, 'lng': 2.0},
        {'lat': 1.0, 'lng': 2.001},
      ]);
      trackBlobs[hrUrl] = Uint8List.fromList(
        GZipEncoder().encode(utf8.encode(jsonEncode(const [
          {'bpm': 140},
          {'bpm': 150},
        ]))),
      );

      final out = File('${tempDir.path}/hr.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1', trackUrl: trackUrl), runRow(id: 'r-2')],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: [runRow(id: 'r-1', trackUrl: trackUrl)],
        runsWithHrSeries: [
          {'id': 'r-2', 'hr_series_url': hrUrl},
        ],
        fetchTrackBytes: fetcher,
      );

      final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
      expect(archive.findFile('hr/r-2.hr.json.gz'), isNotNull,
          reason: 'the indoor run\'s HR sidecar is archived under hr/');
      expect(archive.findFile('tracks/r-1.json.gz'), isNotNull);
      final manifest = jsonDecode(utf8
              .decode(archive.findFile('manifest.json')!.content as List<int>))
          as Map<String, dynamic>;
      expect((manifest['counts'] as Map)['hr_series'], 1);
      expect((manifest['counts'] as Map)['tracks'], 1);
      // The HR bytes round-trip (gunzip -> the same {bpm} samples).
      final hrEntry = archive.findFile('hr/r-2.hr.json.gz')!;
      final decoded = jsonDecode(utf8
          .decode(GZipDecoder().decodeBytes(hrEntry.content as List<int>))) as List;
      expect(decoded.map((e) => (e as Map)['bpm']).toList(), [140, 150]);
    });

    test('emits stage + tracks progress callbacks in order', () async {
      const trackUrl = 'uid/r-1.json.gz';
      trackBlobs[trackUrl] = gzipOf(const [
        {'lat': 0.0, 'lng': 0.0},
        {'lat': 0.0, 'lng': 0.001},
      ]);

      final stages = <String>[];
      final out = File('${tempDir.path}/staged.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1', trackUrl: trackUrl)],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: [runRow(id: 'r-1', trackUrl: trackUrl)],
        fetchTrackBytes: fetcher,
        onProgress: (p) => stages.add(p.stage),
      );
      // Tracks stage fires (initial 0/1 + post-batch 1/1) and the
      // final write+done events land at the end.
      expect(stages, contains('tracks'));
      expect(stages.last, 'done');
      expect(stages, contains('writing'));
    });

    test('downloads tracks in bounded-concurrency batches', () async {
      // 20 runs each with a unique track. Concurrency 4 means peak
      // in-flight should never exceed 4. Total calls should equal 20.
      for (var i = 0; i < 20; i++) {
        final url = 'uid/r-$i.json.gz';
        trackBlobs[url] = gzipOf(const [
          {'lat': 0.0, 'lng': 0.0},
          {'lat': 0.0, 'lng': 0.001},
        ]);
      }
      final runsWithTracks = [
        for (var i = 0; i < 20; i++)
          runRow(id: 'r-$i', trackUrl: 'uid/r-$i.json.gz'),
      ];

      final out = File('${tempDir.path}/bounded.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: runsWithTracks,
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: runsWithTracks,
        fetchTrackBytes: fetcher,
        concurrency: 4,
      );

      expect(totalCalls, 20);
      expect(peakInFlight, lessThanOrEqualTo(4),
          reason: 'concurrency: 4 must cap simultaneous downloads at 4');
      // With concurrency 4 and 20 tasks the peak should also reach
      // ≥2 (it would be 1 if the writer were secretly sequential).
      expect(peakInFlight, greaterThanOrEqualTo(2),
          reason:
              'with 20 tasks + 5ms-each fetcher we should observe parallelism');
    });

    test('a single download failure does not sink the rest of the backup',
        () async {
      // First track URL has no blob → fetcher throws. The writer
      // should swallow that one and still archive the other run.
      trackBlobs['uid/r-2.json.gz'] = gzipOf(const [
        {'lat': 0.0, 'lng': 0.0},
        {'lat': 0.0, 'lng': 0.001},
      ]);
      final runs = [
        runRow(id: 'r-1', trackUrl: 'uid/missing.json.gz'),
        runRow(id: 'r-2', trackUrl: 'uid/r-2.json.gz'),
      ];

      final out = File('${tempDir.path}/partial.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: runs,
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: runs,
        fetchTrackBytes: fetcher,
        concurrency: 4,
      );

      // The healthy run's track is in the archive; the bad one is
      // simply absent (offline-restore would see no track for r-1
      // and produce a Run with an empty track list).
      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(
        zipFile: out,
        runStore: runStore,
      );
      expect(res.runsImported, 2);
      expect(res.tracksUploaded, 1);
    });

    test('runsWithTracks=[] produces a valid manifest-only backup',
        () async {
      final out = File('${tempDir.path}/no-tracks.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        fetchTrackBytes: fetcher,
      );

      // No download calls should fire.
      expect(totalCalls, 0);
      // Manifest is still readable.
      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(zipFile: out, runStore: runStore);
      expect(res.runsImported, 0);
    });

    test('overwrites an existing output file rather than appending',
        () async {
      final out = File('${tempDir.path}/twice.zip');
      // Pre-seed the output with junk so the test fails if the writer
      // appends to it rather than truncating.
      await out.writeAsBytes(List<int>.filled(1024, 0xff));
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        fetchTrackBytes: fetcher,
      );
      // The result must be a valid ZIP — junk bytes would break the
      // ZIP central directory at the end of file.
      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(zipFile: out, runStore: runStore);
      expect(res.runsImported, 0);
    });

    test('rejects concurrency < 1', () async {
      await expectLater(
        () => BackupService.writeBackupZipStreaming(
          outputFile: File('${tempDir.path}/x.zip'),
          runsOut: const [],
          routesOut: const [],
          profile: null,
          settingsPrefs: const {},
          userId: 'uid',
          exportedFrom: 'test',
          runsWithTracks: const [],
          fetchTrackBytes: fetcher,
          concurrency: 0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ---- tryServerBackup orchestration ----------------------------------
  //
  // The extracted helper that decides whether to attempt the Go
  // service's /v1/export?format=backup path. Drives all the
  // server-first branches createBackup composes — without needing
  // a live Supabase session or a real network. Production failure
  // returns false + cleans up any partial file so the local writer
  // sees a clean slate.
  group('tryServerBackup', () {
    test('returns false when serverClient is null', () async {
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: null,
        accessToken: 'tok',
        outputFile: file,
      );
      expect(result, isFalse);
      expect(file.existsSync(), isFalse);
    });

    test('returns false when serverClient has empty baseUrl', () async {
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: BackupServerClient(baseUrl: ''),
        accessToken: 'tok',
        outputFile: file,
      );
      expect(result, isFalse);
    });

    test('returns false when accessToken is null', () async {
      var called = false;
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async {
          called = true;
          return (statusCode: 200, body: {'url': 'https://x/y', 'count': 0});
        },
      );
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: null,
        outputFile: file,
      );
      expect(result, isFalse);
      expect(called, isFalse,
          reason: 'request fetcher must not fire when token is null');
    });

    test('returns false when accessToken is empty string', () async {
      var called = false;
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async {
          called = true;
          return (statusCode: 200, body: {'url': 'https://x/y', 'count': 0});
        },
      );
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: '',
        outputFile: file,
      );
      expect(result, isFalse);
      expect(called, isFalse);
    });

    test('returns true + writes file on server success', () async {
      var requestCount = 0;
      var downloadCount = 0;
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async {
          requestCount++;
          return (
            statusCode: 200,
            body: <String, dynamic>{'url': 'https://signed/x', 'count': 12},
          );
        },
        downloadFetcher: (_, f) async {
          downloadCount++;
          await f.writeAsBytes([0x50, 0x4B, 0x05, 0x06]); // empty-zip marker
          return 4;
        },
      );
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok-abc',
        outputFile: file,
      );
      expect(result, isTrue);
      expect(requestCount, 1);
      expect(downloadCount, 1);
      expect(file.existsSync(), isTrue);
    });

    test('returns false + deletes partial file when fetchBackupToFile throws',
        () async {
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 1},
        ),
        downloadFetcher: (_, f) async {
          // Write a partial body then throw — emulates a mid-stream
          // disconnect.
          await f.writeAsBytes(List<int>.filled(128, 0xff));
          throw const HttpException('connection reset');
        },
      );
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok-abc',
        outputFile: file,
      );
      expect(result, isFalse,
          reason: 'failure should not be reported as a successful server run');
      expect(file.existsSync(), isFalse,
          reason: 'partial file must be cleaned up so the local '
              'writer sees a clean slate');
    });

    test('returns false on non-200 server response (no partial file)', () async {
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async => (
          statusCode: 429,
          body: <String, dynamic>{'error': 'rate_limited'},
        ),
        downloadFetcher: (_, __) async => 0,
      );
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok-abc',
        outputFile: file,
      );
      expect(result, isFalse);
      expect(file.existsSync(), isFalse);
    });

    test('emits server stage + done progress events on success', () async {
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 5},
        ),
        downloadFetcher: (_, f) async {
          await f.writeAsBytes([0]);
          return 1;
        },
      );
      final file = File('${tempDir.path}/backup.zip');
      final stages = <String>[];
      await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok',
        outputFile: file,
        onProgress: (p) => stages.add(p.stage),
      );
      expect(stages, contains('server'));
      expect(stages.last, 'done');
    });

    test('does not emit done after a failed attempt', () async {
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async => (
          statusCode: 500,
          body: <String, dynamic>{'error': 'oops'},
        ),
        downloadFetcher: (_, __) async => 0,
      );
      final file = File('${tempDir.path}/backup.zip');
      final stages = <String>[];
      await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok',
        outputFile: file,
        onProgress: (p) => stages.add(p.stage),
      );
      // The `server` stage marker fires, but `done` does NOT —
      // caller will fall through to local and either land that
      // path's `done` or surface an error.
      expect(stages, contains('server'));
      expect(stages, isNot(contains('done')));
    });

    test('cleanup is best-effort: deleteSync exception is swallowed',
        () async {
      // Simulate a download that doesn't actually write the file —
      // the cleanup path then has nothing to delete and must not
      // throw. (The `outputFile.existsSync() == false` branch.)
      final stub = BackupServerClient(
        baseUrl: 'https://example/',
        requestFetcher: (_, __, ___) async => (
          statusCode: 200,
          body: <String, dynamic>{'url': 'https://signed/x', 'count': 0},
        ),
        downloadFetcher: (_, __) async {
          throw const SocketException('refused');
        },
      );
      final file = File('${tempDir.path}/never-written.zip');
      // Should complete without throwing despite the no-file case.
      final result = await BackupService.tryServerBackup(
        serverClient: stub,
        accessToken: 'tok',
        outputFile: file,
      );
      expect(result, isFalse);
      expect(file.existsSync(), isFalse);
    });
  });
}
