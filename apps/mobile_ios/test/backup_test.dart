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
}
