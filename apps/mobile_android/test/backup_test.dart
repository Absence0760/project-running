import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:archive/archive.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:archive/archive_io.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/backup.dart';
import '../lib/backup_server_client.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gym_store.dart';
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
    'is_featured': false,
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
  Map<String, List<Map<String, dynamic>>>? hrByRunId,
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
  if (hrByRunId != null) {
    for (final entry in hrByRunId.entries) {
      final gz = Uint8List.fromList(
          GZipEncoder().encode(utf8.encode(jsonEncode(entry.value))));
      archive.addFile(ArchiveFile('hr/${entry.key}.hr.json.gz', gz.length, gz));
    }
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Online-path fake: signed-in user, captures the restore re-home calls.
/// The online restore only touches `_client` for profile/events/routes, so an
/// archive with none of those drives the runs loop using just these overrides.
class _CapturingOnlineApi extends ApiClient {
  _CapturingOnlineApi(this._uid);
  final String _uid;
  final List<Map<String, dynamic>> upsertedRuns = [];
  final List<(String userId, String runId)> hrUploads = [];
  final List<(String userId, String runId)> trackUploads = [];

  @override
  String? get userId => _uid;

  @override
  Future<void> uploadTrackBytes({
    required String userId,
    required String runId,
    required Uint8List gzippedBytes,
  }) async {
    trackUploads.add((userId, runId));
  }

  @override
  Future<void> uploadHrSeriesBytes({
    required String userId,
    required String runId,
    required Uint8List gzippedBytes,
  }) async {
    hrUploads.add((userId, runId));
  }

  @override
  Future<void> upsertRunRowRaw(Map<String, dynamic> row) async {
    upsertedRuns.add(Map<String, dynamic>.from(row));
  }
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

  group('online restore — hr_series_url re-stamp (decisions §116)', () {
    // The online path ALWAYS overwrites hr_series_url (re-homed path or null).
    // A stale archived path (old owner/run) left in place would fail the
    // runs_hr_series_url_path_shape CHECK (23514) and sink the whole upsert.
    const uid = 'aaaaaaaa-0000-0000-0000-0000000000a1';

    test('re-homes the sidecar + re-stamps hr_series_url (id preserved)', () async {
      final api = _CapturingOnlineApi(uid);
      final bytes = buildBackupZip(
        runs: [
          {
            ...runRow(id: 'run-1'),
            'hr_series_url': 'old-owner/old-run.hr.json.gz', // stale archived path
          },
        ],
        hrByRunId: {
          'run-1': const [
            {'bpm': 140},
            {'bpm': 150},
          ],
        },
      );
      await zipFile.writeAsBytes(bytes);
      final result = await BackupService(api: api).restore(zipFile: zipFile);

      expect(result.runsImported, 1);
      // Sidecar re-homed to the signed-in user's bucket under the kept id.
      expect(api.hrUploads, [(uid, 'run-1')]);
      // The upserted row carries the NEW canonical path, NOT the stale one.
      expect(api.upsertedRuns.single['hr_series_url'], '$uid/run-1.hr.json.gz');
    });

    test('clears a stale hr_series_url to null when no sidecar file is present',
        () async {
      final api = _CapturingOnlineApi(uid);
      final bytes = buildBackupZip(
        runs: [
          {
            ...runRow(id: 'run-1'),
            'hr_series_url': 'old-owner/old-run.hr.json.gz', // stale, but no hr/ file
          },
        ],
      );
      await zipFile.writeAsBytes(bytes);
      final result = await BackupService(api: api).restore(zipFile: zipFile);

      expect(result.runsImported, 1);
      expect(api.hrUploads, isEmpty);
      // The stale path must never survive — it would fail the path-shape
      // CHECK (23514). It leaves as an OMITTED column rather than an explicit
      // null, so an existing row's own valid sidecar path is left alone.
      expect(api.upsertedRuns.single.containsKey('hr_series_url'), isFalse);
    });

    test('generateNewIds re-stamps hr_series_url to the new id', () async {
      final api = _CapturingOnlineApi(uid);
      final bytes = buildBackupZip(
        runs: [runRow(id: 'orig-1')],
        hrByRunId: {
          'orig-1': const [
            {'bpm': 130},
          ],
        },
      );
      await zipFile.writeAsBytes(bytes);
      await BackupService(api: api).restore(zipFile: zipFile, generateNewIds: true);

      // One upsert; its id is fresh (not orig-1) and hr_series_url matches it.
      final row = api.upsertedRuns.single;
      final newId = row['id'] as String;
      expect(newId, isNot('orig-1'));
      expect(row['hr_series_url'], '$uid/$newId.hr.json.gz');
      expect(api.hrUploads, [(uid, newId)]);
    });
  });

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

    // The id read used to sit OUTSIDE the per-row guard its sibling casts are
    // inside, so a hand-edited or third-party archive aborted the whole restore
    // mid-way: earlier rows were already committed, the caller got a bare
    // TypeError instead of a RestoreResult, and a re-run died at the same row.
    test('a run row with no id is skipped, later rows still land', () async {
      final bytes = buildBackupZip(runs: [
        runRow(id: 'r-before'),
        <String, dynamic>{'started_at': '2026-04-10T08:00:00Z', 'distance_m': 5000},
        runRow(id: 'r-after'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 2);
      expect(runStore.runs.map((r) => r.id),
          containsAll(<String>['r-before', 'r-after']));
      expect(result.warnings.any((w) => w.contains('missing id')), isTrue);
    });

    test('a run row with a null id is skipped, later rows still land', () async {
      final bytes = buildBackupZip(runs: [
        <String, dynamic>{'id': null, 'started_at': '2026-04-10T08:00:00Z'},
        runRow(id: 'r-after-null'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(runStore.runs.single.id, 'r-after-null');
      expect(result.warnings.any((w) => w.contains('missing id')), isTrue);
    });

    test('a run row with a non-string id is skipped', () async {
      final bytes = buildBackupZip(runs: [
        <String, dynamic>{'id': 42, 'started_at': '2026-04-10T08:00:00Z'},
        runRow(id: 'r-after-int'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(runStore.runs.single.id, 'r-after-int');
      expect(result.warnings.any((w) => w.contains('missing id')), isTrue);
    });

    test('an empty-string run id is skipped rather than written', () async {
      final bytes = buildBackupZip(runs: [
        <String, dynamic>{'id': '', 'started_at': '2026-04-10T08:00:00Z'},
        runRow(id: 'r-after-empty'),
      ]);

      final result = await restoreFromBytes(bytes);

      expect(result.runsImported, 1);
      expect(runStore.runs.single.id, 'r-after-empty');
      expect(result.warnings.any((w) => w.contains('missing id')), isTrue);
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

  // ---- truncated-export disclosure ------------------------------------
  //
  // The server caps an export at 5 000 runs and reports `complete:
  // false` when the archive is short of the account. Until this landed,
  // both clients said only "your export is ready" and the shortfall was
  // visible nowhere but inside the archive's own manifest.json.
  group('BackupOutcome.shortfall', () {
    final file = File('/tmp/does-not-need-to-exist.zip');

    test('a whole server archive discloses nothing', () {
      final outcome = BackupOutcome(file,
          server: const ServerBackupSummary(
              count: 12, total: 12, complete: true));
      expect(outcome.shortfall, isNull);
    });

    test('a truncated server archive reports both counts', () {
      final outcome = BackupOutcome(file,
          server: const ServerBackupSummary(
              count: 5000, total: 7412, complete: false));
      expect(outcome.shortfall?.count, 5000);
      expect(outcome.shortfall?.total, 7412);
    });

    test('a locally-built archive makes no completeness claim', () {
      // The local writer has no server verdict to read, so the screen
      // must not label its output partial OR whole from this field.
      expect(BackupOutcome(file).shortfall, isNull);
    });

    test('the disclosure copy names both counts', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final banner = l10n.settingsAccountBackupPartial(5000, 7412);
      expect(banner, contains('5000'));
      expect(banner, contains('7412'));
      final notice = l10n.settingsAccountBackupPartialNotice(5000, 7412);
      expect(notice, contains('5000'));
      expect(notice, contains('7412'));
      expect(notice, contains('manifest.json'));
    });
  });

  // ---- tryServerBackup orchestration ----------------------------------
  //
  // The extracted helper that decides whether to attempt the Go
  // service's /v1/export?format=backup path. Drives all the
  // server-first branches createBackup composes — without needing
  // a live Supabase session or a real network. Production failure
  // returns null + cleans up any partial file so the local writer
  // sees a clean slate; success returns the server's completeness
  // verdict so the screen can disclose a truncated archive.
  group('tryServerBackup', () {
    test('returns null when serverClient is null', () async {
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: null,
        accessToken: 'tok',
        outputFile: file,
      );
      expect(result, isNull);
      expect(file.existsSync(), isFalse);
    });

    test('returns null when serverClient has empty baseUrl', () async {
      final file = File('${tempDir.path}/backup.zip');
      final result = await BackupService.tryServerBackup(
        serverClient: BackupServerClient(baseUrl: ''),
        accessToken: 'tok',
        outputFile: file,
      );
      expect(result, isNull);
    });

    test('returns null when accessToken is null', () async {
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
      expect(result, isNull);
      expect(called, isFalse,
          reason: 'request fetcher must not fire when token is null');
    });

    test('returns null when accessToken is empty string', () async {
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
      expect(result, isNull);
      expect(called, isFalse);
    });

    test('returns the summary + writes file on server success', () async {
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
      expect(result, isNotNull);
      expect(result!.count, 12);
      expect(result.total, 12);
      expect(result.complete, isTrue);
      expect(requestCount, 1);
      expect(downloadCount, 1);
      expect(file.existsSync(), isTrue);
    });

    test('returns null + deletes partial file when fetchBackupToFile throws',
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
      expect(result, isNull,
          reason: 'failure should not be reported as a successful server run');
      expect(file.existsSync(), isFalse,
          reason: 'partial file must be cleaned up so the local '
              'writer sees a clean slate');
    });

    test('returns null on non-200 server response (no partial file)', () async {
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
      expect(result, isNull);
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
      expect(result, isNull);
      expect(file.existsSync(), isFalse);
    });
  });

  // ---- gym + food backup/restore round-trip (M5) ----
  //
  // The local gym/food stores aren't server-synced yet, so the backup
  // sources them from the stores' `backupRecords` and restore hydrates them
  // back into fresh stores as pendingCreate. Proves the Phase 4 multi-modal
  // data survives a device-swap backup -> restore.
  group('gym + food backup/restore round-trip', () {
    late LocalGymStore srcGym;
    late LocalFoodStore srcFood;
    late LocalGymStore dstGym;
    late LocalFoodStore dstFood;

    setUp(() async {
      srcGym = LocalGymStore();
      srcFood = LocalFoodStore();
      dstGym = LocalGymStore();
      dstFood = LocalFoodStore();
      await srcGym.init(
          overrideDirectory: Directory('${tempDir.path}/src_gym')..createSync());
      await srcFood.init(
          overrideDirectory: Directory('${tempDir.path}/src_food')..createSync());
      await dstGym.init(
          overrideDirectory: Directory('${tempDir.path}/dst_gym')..createSync());
      await dstFood.init(
          overrideDirectory: Directory('${tempDir.path}/dst_food')..createSync());
    });

    test('backup includes gym_workouts.json + food_log.json + manifest counts',
        () async {
      await srcGym.createLocal(
        title: 'Leg day',
        startedAt: DateTime.utc(2026, 6, 1, 7),
        sets: const [
          (exerciseName: 'Squat', reps: 5, weightKg: 100.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      await srcFood.createLocal(
        startedAt: DateTime.utc(2026, 6, 1, 12),
        itemName: 'Oatmeal',
        calories: 300,
      );

      final out = File('${tempDir.path}/gymfood.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        gymWorkoutsOut: srcGym.backupRecords,
        foodLogOut: srcFood.backupRecords,
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final archive =
          ZipDecoder().decodeBytes(await out.readAsBytes());
      expect(archive.findFile('gym_workouts.json'), isNotNull);
      expect(archive.findFile('food_log.json'), isNotNull);
      final manifest = jsonDecode(
              utf8.decode(archive.findFile('manifest.json')!.content as List<int>))
          as Map<String, dynamic>;
      expect((manifest['counts'] as Map)['gym_workouts'], 1);
      expect((manifest['counts'] as Map)['food_log'], 1);
    });

    test('restore hydrates the gym + food stores from the archive', () async {
      final workout = await srcGym.createLocal(
        title: 'Push day',
        startedAt: DateTime.utc(2026, 6, 2, 7),
        sets: const [
          (exerciseName: 'Bench', reps: 8, weightKg: 60.0, rpe: null, setType: null, durationS: null, exerciseId: null),
        ],
      );
      final entry = await srcFood.createLocal(
        startedAt: DateTime.utc(2026, 6, 2, 12),
        itemName: 'Banana',
        calories: 90,
      );

      final out = File('${tempDir.path}/gymfood2.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        gymWorkoutsOut: srcGym.backupRecords,
        foodLogOut: srcFood.backupRecords,
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(
        zipFile: out,
        gymStore: dstGym,
        foodStore: dstFood,
      );

      expect(res.gymWorkoutsImported, 1);
      expect(res.foodLogImported, 1);

      final restoredWorkout = dstGym.byId(workout.id);
      expect(restoredWorkout, isNotNull);
      expect(restoredWorkout!.workout.title, 'Push day');
      expect(restoredWorkout.sets, hasLength(1));
      // Queued for the next sync drain.
      expect(restoredWorkout.syncState, GymSyncState.pendingCreate);

      final restoredFood =
          dstFood.rows.where((r) => r['id'] == entry.id).toList();
      expect(restoredFood, hasLength(1));
      expect(restoredFood.single['item_name'], 'Banana');
      // Queued for the next sync drain.
      expect(dstFood.hasPending, isTrue);
    });

    test('restore of gym/food is idempotent — re-running keeps the local copy',
        () async {
      await srcGym.createLocal(
        title: 'Once',
        startedAt: DateTime.utc(2026, 6, 3, 7),
      );
      final out = File('${tempDir.path}/gymfood3.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        gymWorkoutsOut: srcGym.backupRecords,
        foodLogOut: const [],
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final svc = BackupService(api: _OfflineApi());
      final first = await svc.restore(zipFile: out, gymStore: dstGym);
      final second = await svc.restore(zipFile: out, gymStore: dstGym);

      expect(first.gymWorkoutsImported, 1);
      expect(second.gymWorkoutsImported, 0);
      expect(dstGym.workouts, hasLength(1));
    });
  

    test('generateNewIds re-keys gym + food rows so a foreign archive can land',
        () async {
      // The flag exists to restore SOMEONE ELSE's archive. It re-minted run
      // and route ids but was never plumbed into the gym/food path, so those
      // rows kept the archive's id and were queued as pendingCreate — an
      // INSERT that can never succeed against an id the server already has.
      // pushCreate fails on the PK/RLS, the error is swallowed, hasPending
      // never clears, and every refresh re-runs the drain.
      final workout = await srcGym.createLocal(
        title: 'Foreign push day',
        startedAt: DateTime.utc(2026, 6, 5, 7),
      );
      final entry = await srcFood.createLocal(
        startedAt: DateTime.utc(2026, 6, 5, 12),
        itemName: 'Foreign banana',
        calories: 90,
      );

      final out = File('${tempDir.path}/gymfood4.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        gymWorkoutsOut: srcGym.backupRecords,
        foodLogOut: srcFood.backupRecords,
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final svc = BackupService(api: _OfflineApi());
      final res = await svc.restore(
        zipFile: out,
        gymStore: dstGym,
        foodStore: dstFood,
        generateNewIds: true,
      );

      expect(res.gymWorkoutsImported, 1);
      expect(res.foodLogImported, 1);
      expect(dstGym.byId(workout.id), isNull,
          reason: "the archive's id must not be reused");
      expect(dstGym.workouts.single.workout.title, 'Foreign push day');
      expect(dstFood.rows.where((r) => r['id'] == entry.id), isEmpty);
      expect(dstFood.rows.single['item_name'], 'Foreign banana');
    });

    test('generateNewIds lets the same archive restore twice, side by side',
        () async {
      // The other half: with fresh ids there is no id collision to skip on,
      // so a second restore lands as a second row rather than being dropped
      // by the idempotence check.
      await srcGym.createLocal(
        title: 'Twice',
        startedAt: DateTime.utc(2026, 6, 6, 7),
      );
      final out = File('${tempDir.path}/gymfood5.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: const [],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        gymWorkoutsOut: srcGym.backupRecords,
        foodLogOut: const [],
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final svc = BackupService(api: _OfflineApi());
      await svc.restore(zipFile: out, gymStore: dstGym, generateNewIds: true);
      await svc.restore(zipFile: out, gymStore: dstGym, generateNewIds: true);

      expect(dstGym.workouts, hasLength(2));
      expect(dstGym.workouts.map((w) => w.id).toSet(), hasLength(2));
    });
  });

  // ---- M5: undrained runs must be in the archive ----
  group('local-only runs in the archive', () {
    test('rawRunRowForBackup emits the raw column shape restore upserts',
        () async {
      final run = cm.Run(
        id: 'local-1',
        startedAt: DateTime.utc(2026, 4, 10, 8),
        duration: const Duration(seconds: 1500),
        distanceMetres: 5000,
        track: const [],
        source: cm.RunSource.app,
        metadata: const {
          'activity_type': 'trail_run',
          'is_dnf': true,
          'fastest_5k_s': 1200,
          'title': 'Ridge loop',
        },
      );
      final row = BackupService.rawRunRowForBackup(run);

      expect(row['id'], 'local-1');
      expect(row.containsKey('user_id'), isFalse,
          reason: 'the archive is re-homeable; restore stamps the new owner');
      expect(row.containsKey('track_url'), isFalse,
          reason: 'the blob rides in tracks/<id>.json.gz, not a storage path');
      expect(row['started_at'], '2026-04-10T08:00:00.000Z');
      expect(row['duration_s'], 1500);
      expect(row['distance_m'], 5000);
      // Promoted columns are lifted out of the bag, exactly as saveRun does.
      expect(row['activity_type'], 'trail_run');
      expect(row['is_dnf'], isTrue);
      expect(row['fastest_5k_s'], 1200);
      expect(row['metadata'], {'title': 'Ridge loop'});
    });

    test('an undrained run round-trips through the archive with its track',
        () async {
      final localRun = cm.Run(
        id: 'local-1',
        startedAt: DateTime.utc(2026, 4, 10, 8),
        duration: const Duration(seconds: 1500),
        distanceMetres: 5000,
        track: const [
          cm.Waypoint(lat: 47.37, lng: 8.54),
          cm.Waypoint(lat: 47.371, lng: 8.541),
          cm.Waypoint(lat: 47.372, lng: 8.542),
        ],
        source: cm.RunSource.app,
      );
      final localTracks = <String, Uint8List>{
        'local-1': Uint8List.fromList(GZipEncoder().encode(utf8.encode(
            jsonEncode(const [
          {'lat': 47.37, 'lng': 8.54},
          {'lat': 47.371, 'lng': 8.541},
          {'lat': 47.372, 'lng': 8.542},
        ])))),
      };

      final out = File('${tempDir.path}/localonly.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [BackupService.rawRunRowForBackup(localRun)],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        localTracks: localTracks,
        fetchTrackBytes: (_) async => Uint8List(0),
      );

      final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
      final manifest = jsonDecode(
              utf8.decode(archive.findFile('manifest.json')!.content as List<int>))
          as Map<String, dynamic>;
      expect((manifest['counts'] as Map)['runs'], 1);
      expect((manifest['counts'] as Map)['tracks'], 1,
          reason: 'a device-only track must be counted like a downloaded one');

      final dstDir = Directory('${tempDir.path}/restored')..createSync();
      final dst = LocalRunStore();
      await dst.init(overrideDirectory: dstDir);
      final res = await BackupService(api: _OfflineApi())
          .restore(zipFile: out, runStore: dst);

      expect(res.runsImported, 1);
      expect((await dst.runById('local-1'))!.track, hasLength(3));
    });
  });

  // ---- M4: the offline restore is additive ----
  group('offline restore never clobbers a local run', () {
    test('a track-less archive entry leaves the richer local copy alone',
        () async {
      final local = cm.Run(
        id: 'r-1',
        startedAt: DateTime.utc(2026, 4, 10, 8),
        duration: const Duration(seconds: 1500),
        distanceMetres: 5000,
        track: const [
          cm.Waypoint(lat: 47.37, lng: 8.54),
          cm.Waypoint(lat: 47.371, lng: 8.541),
          cm.Waypoint(lat: 47.372, lng: 8.542),
        ],
        source: cm.RunSource.app,
      );
      await runStore.save(local);
      await runStore.markSynced('r-1');

      // createBackup only LOGS a failed track download, so an archive can
      // carry the row with no tracks/ entry at all.
      final res = await restoreFromBytes(buildBackupZip(runs: [runRow(id: 'r-1')]));

      expect(res.runsImported, 0);
      expect((await runStore.runById('r-1'))!.track, hasLength(3),
          reason: 'the on-device GPS trace is the only copy of what happened');
      expect(res.warnings.any((w) => w.contains('already present locally')),
          isTrue);
    });

    test('generateNewIds still imports the archive copy alongside', () async {
      await runStore.save(cm.Run(
        id: 'r-1',
        startedAt: DateTime.utc(2026, 4, 10, 8),
        duration: const Duration(seconds: 1500),
        distanceMetres: 5000,
        track: const [],
        source: cm.RunSource.app,
      ));

      final res = await restoreFromBytes(
        buildBackupZip(runs: [runRow(id: 'r-1')]),
        generateNewIds: true,
      );

      expect(res.runsImported, 1);
      expect(runStore.summaries, hasLength(2));
    });
  });

  // ---- archive completeness disclosure ---------------------------------
  //
  // The run + route reads are paged and uncapped, so a local archive is the
  // whole account by construction. The one thing that can still come up short
  // is a blob download the writer swallows to keep the rest of the backup
  // alive — and a swallow nobody is told about is how a runner finds out at
  // restore time. The manifest states the verdict in the same `complete` /
  // `incomplete` vocabulary the Go writer publishes.
  group('local archive completeness', () {
    final Map<String, Uint8List> blobs = {};
    Future<Uint8List> fetcher(String path) async {
      final bytes = blobs[path];
      if (bytes == null) throw StateError('no blob for $path');
      return bytes;
    }

    setUp(blobs.clear);

    Uint8List gz(Object body) =>
        Uint8List.fromList(GZipEncoder().encode(utf8.encode(jsonEncode(body))));

    Map<String, dynamic> manifestOf(File f) {
      final archive = ZipDecoder().decodeBytes(f.readAsBytesSync());
      return jsonDecode(utf8
          .decode(archive.findFile('manifest.json')!.content as List<int>)) as Map<String, dynamic>;
    }

    test('a whole archive says so', () async {
      const url = 'uid/r-1.json.gz';
      blobs[url] = gz(const [
        {'lat': 1.0, 'lng': 2.0},
      ]);
      final out = File('${tempDir.path}/whole.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1', trackUrl: url)],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: [runRow(id: 'r-1', trackUrl: url)],
        fetchTrackBytes: fetcher,
      );

      expect(summary.complete, isTrue);
      expect(summary.blobsMissing, 0);
      final manifest = manifestOf(out);
      expect(manifest['complete'], isTrue);
      expect(manifest['incomplete'], isEmpty);
    });

    test('a failed track download makes the archive say it is incomplete',
        () async {
      blobs['uid/r-2.json.gz'] = gz(const [
        {'lat': 1.0, 'lng': 2.0},
      ]);
      final runs = [
        runRow(id: 'r-1', trackUrl: 'uid/missing.json.gz'),
        runRow(id: 'r-2', trackUrl: 'uid/r-2.json.gz'),
      ];
      final out = File('${tempDir.path}/short.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: runs,
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: runs,
        fetchTrackBytes: fetcher,
      );

      expect(summary.complete, isFalse);
      expect(summary.incomplete, ['tracks']);
      expect(summary.blobsWanted, 2);
      expect(summary.blobsWritten, 1);
      expect(summary.blobsMissing, 1);
      final manifest = manifestOf(out);
      expect(manifest['complete'], isFalse,
          reason: 'an archive short of what was asked for must never read '
              'as whole — restore is the only other place it surfaces');
      expect(manifest['incomplete'], ['tracks']);
      // The count stays what the file actually holds, matching the Go
      // writer's `tracks` key.
      expect((manifest['counts'] as Map)['tracks'], 1);
    });

    test('a failed HR sidecar names its own section', () async {
      final out = File('${tempDir.path}/hrshort.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1')],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        runsWithHrSeries: const [
          {'id': 'r-1', 'hr_series_url': 'uid/r-1.hr.json.gz'},
        ],
        fetchTrackBytes: fetcher,
      );

      expect(summary.incomplete, ['hr_series']);
      expect(manifestOf(out)['incomplete'], ['hr_series']);
    });

    test('both sections short are both named, in the shared sort order',
        () async {
      final runs = [runRow(id: 'r-1', trackUrl: 'uid/gone.json.gz')];
      final out = File('${tempDir.path}/bothshort.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: runs,
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: runs,
        runsWithHrSeries: const [
          {'id': 'r-1', 'hr_series_url': 'uid/gone.hr.json.gz'},
        ],
        fetchTrackBytes: fetcher,
      );

      expect(summary.incomplete, ['hr_series', 'tracks']);
      expect(summary.blobsMissing, 2);
    });

    test('a device-only track cannot fail, so it never marks the archive short',
        () async {
      final out = File('${tempDir.path}/localonly-complete.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'local-1')],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        localTracks: {'local-1': gz(const [{'lat': 1.0, 'lng': 2.0}])},
        fetchTrackBytes: fetcher,
      );

      expect(summary.complete, isTrue);
      expect(summary.blobsWanted, 1);
      expect(summary.blobsWritten, 1);
      expect((manifestOf(out)['counts'] as Map)['tracks'], 1);
    });

    // The bug this whole change exists for: `fetchRunRowsRaw` issued an
    // unranged select, so PostgREST clamped it to db-max-rows (1000) and the
    // archive silently held the newest page. The read is paged now — this
    // pins that the WRITER carries whatever it is handed across that
    // boundary, at a count that is genuinely past it.
    test('an archive of more than one PostgREST page holds every run',
        () async {
      const total = kPostgrestPageSize + 500; // 1500 — two full pages and a bit
      expect(total, greaterThan(kPostgrestPageSize),
          reason: 'the point of this test is crossing the page boundary');
      final runs = [
        for (var i = 0; i < total; i++)
          runRow(
            id: 'r-$i',
            startedAt: DateTime.utc(2026, 1, 1)
                .add(Duration(minutes: i))
                .toIso8601String(),
          ),
      ];
      final out = File('${tempDir.path}/big.zip');
      final summary = await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: runs,
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: const [],
        fetchTrackBytes: fetcher,
      );

      expect(summary.complete, isTrue);
      final archive = ZipDecoder().decodeBytes(out.readAsBytesSync());
      final archived = jsonDecode(utf8
          .decode(archive.findFile('runs.json')!.content as List<int>)) as List;
      expect(archived, hasLength(total));
      expect((archived.first as Map)['id'], 'r-0');
      expect((archived.last as Map)['id'], 'r-${total - 1}');
      expect((manifestOf(out)['counts'] as Map)['runs'], total);
    });

    test('a mid-read failure produces no archive at all, never a whole-looking one',
        () async {
      var page = 0;
      Future<List<int>> failOnSecondPage(int from, int to) async {
        if (page++ == 0) return List<int>.generate(kPostgrestPageSize, (i) => i);
        throw StateError('network died mid-read');
      }

      // `readAllPages` rethrows rather than returning the pages it managed,
      // so `createBackup` never reaches the writer and no file is left behind
      // for the runner to mistake for a backup.
      await expectLater(
        readAllPages<int>(failOnSecondPage),
        throwsA(isA<StateError>()),
      );
      expect(File('${tempDir.path}/never-written.zip').existsSync(), isFalse);
    });
  });

  group('restore of an archive that declares itself incomplete', () {
    Map<String, dynamic> manifest({
      bool? complete,
      List<String>? incomplete,
    }) =>
        <String, dynamic>{
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-08-18T10:00:00Z',
          if (complete != null) 'complete': complete,
          if (incomplete != null) 'incomplete': incomplete,
        };

    test('surfaces the verdict and names the short sections', () async {
      final res = await restoreFromBytes(buildBackupZip(
        manifestOverride: manifest(complete: false, incomplete: ['tracks']),
        runs: [runRow(id: 'r-1')],
      ));

      expect(res.runsImported, 1, reason: 'a short archive still restores');
      expect(res.archiveIncomplete, isTrue);
      expect(res.archiveIncompleteSections, ['tracks']);
      expect(res.warnings.first, contains('incomplete'));
      expect(res.warnings.first, contains('tracks'));
    });

    test('a short archive with no section list still discloses', () async {
      final res = await restoreFromBytes(buildBackupZip(
        manifestOverride: manifest(complete: false),
        runs: const [],
      ));

      expect(res.archiveIncomplete, isTrue);
      expect(res.archiveIncompleteSections, isEmpty);
      expect(res.warnings.first, contains('incomplete'));
    });

    test('a whole archive claims nothing', () async {
      final res = await restoreFromBytes(buildBackupZip(
        manifestOverride: manifest(complete: true, incomplete: const []),
        runs: const [],
      ));

      expect(res.archiveIncomplete, isFalse);
      expect(res.warnings.any((w) => w.contains('incomplete')), isFalse);
    });

    test('an archive from a writer that predates the field claims nothing',
        () async {
      // Only an explicit `complete: false` is evidence of a shortfall —
      // warning on every older / web-built archive would be its own
      // dishonesty. Mirrors ServerBackupSummary.fromJson.
      final res = await restoreFromBytes(buildBackupZip(
        manifestOverride: manifest(),
        runs: const [],
      ));

      expect(res.archiveIncomplete, isFalse);
      expect(res.warnings.any((w) => w.contains('incomplete')), isFalse);
    });

    test('the whole-archive round trip carries its own verdict into restore',
        () async {
      final out = File('${tempDir.path}/roundtrip.zip');
      await BackupService.writeBackupZipStreaming(
        outputFile: out,
        runsOut: [runRow(id: 'r-1', trackUrl: 'uid/gone.json.gz')],
        routesOut: const [],
        profile: null,
        settingsPrefs: const {},
        userId: 'uid',
        exportedFrom: 'test',
        runsWithTracks: [runRow(id: 'r-1', trackUrl: 'uid/gone.json.gz')],
        fetchTrackBytes: (_) async => throw StateError('offline'),
      );

      final res = await BackupService(api: _OfflineApi())
          .restore(zipFile: out, runStore: runStore);
      expect(res.archiveIncomplete, isTrue);
      expect(res.archiveIncompleteSections, ['tracks']);
    });
  });

  group('online restore — a blob the archive lacks keeps the row\'s own path',
      () {
    const uid = 'aaaaaaaa-0000-0000-0000-0000000000a2';

    test('track_url is omitted, not nulled, when the archive has no track',
        () async {
      final api = _CapturingOnlineApi(uid);
      final bytes = buildBackupZip(runs: [
        {...runRow(id: 'run-1'), 'track_url': 'old-owner/old-run.json.gz'},
      ]);
      await zipFile.writeAsBytes(bytes);
      await BackupService(api: api).restore(zipFile: zipFile);

      // Restoring a track-short archive over the account it came from used to
      // set track_url = null, orphaning the Storage object and costing the run
      // its trace. An omitted column is left alone by the upsert.
      expect(api.upsertedRuns.single.containsKey('track_url'), isFalse);
      expect(api.trackUploads, isEmpty);
    });

    test('track_url is re-stamped when the archive does carry the track',
        () async {
      final api = _CapturingOnlineApi(uid);
      final bytes = buildBackupZip(
        runs: [runRow(id: 'run-1')],
        tracksByRunId: {
          'run-1': const [
            {'lat': 47.37, 'lng': 8.54},
          ],
        },
      );
      await zipFile.writeAsBytes(bytes);
      await BackupService(api: api).restore(zipFile: zipFile);

      expect(api.trackUploads, [(uid, 'run-1')]);
      expect(api.upsertedRuns.single['track_url'], '$uid/run-1.json.gz');
    });
  });
}
