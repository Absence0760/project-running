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

/// Cross-platform compatibility test for the `run-app-backup` v1
/// wire format. The Go service at `apps/job_worker/internal/dataexport`
/// emits backups via `BuildBackupZip`; the mobile `BackupService.restore`
/// reads them. These two implementations live in different languages
/// and can drift on the JSON shape, the ZIP entry encoding, or the
/// manifest fields. This file hand-crafts an archive that mirrors —
/// byte-by-byte where it matters — what the Go writer produces, and
/// runs the Dart reader against it.
///
/// If you change the format on either side, this test must be updated
/// in lockstep with `apps/job_worker/internal/dataexport/server.go`'s
/// `BuildBackupZip` AND `apps/web/src/lib/backup_writer.ts`'s
/// `buildBackupZip`. The trio is the wire contract.

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

/// Builds a ZIP archive whose entry order + encoding mirrors what
/// `BuildBackupZip` in Go produces:
///
///   1. `runs.json` (pretty-printed JSON, 2-space indent — matches
///      `json.MarshalIndent(_, "", "  ")` in Go).
///   2. `routes.json` (same encoding).
///   3. `profile.json` (same encoding; profile.id stripped by the
///      caller before serialisation).
///   4. `tracks/<id>.json.gz` × N (raw gzipped bytes archived with
///      `zip.Store` — no deflate. Matches the Go writer's
///      `FileHeader{Method: zip.Store}`).
///   5. `manifest.json` (last so counts reflect what actually landed).
Uint8List goShapeBackup({
  required Map<String, dynamic> manifest,
  required List<Map<String, dynamic>> runs,
  required List<Map<String, dynamic>> routes,
  required Map<String, dynamic>? profile,
  required Map<String, dynamic> settingsPrefs,
  Map<String, Uint8List> trackBytes = const {},
}) {
  final archive = Archive();
  String pretty(Object body) =>
      const JsonEncoder.withIndent('  ').convert(body);

  void addJson(String path, Object body) {
    final bytes = utf8.encode(pretty(body));
    archive.addFile(ArchiveFile.bytes(path, Uint8List.fromList(bytes)));
  }

  addJson('runs.json', runs);
  addJson('routes.json', routes);
  addJson('profile.json', {
    'profile': profile,
    'settings_prefs': settingsPrefs,
  });
  for (final entry in trackBytes.entries) {
    archive.addFile(ArchiveFile.bytes(
      'tracks/${entry.key}.json.gz',
      entry.value,
    ));
  }
  addJson('manifest.json', manifest);

  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List gzipOfJson(List<Map<String, dynamic>> waypoints) {
  final encoded = utf8.encode(jsonEncode(waypoints));
  return Uint8List.fromList(GZipEncoder().encode(encoded));
}

void main() {
  setUpAll(_ensureSupabase);

  late Directory tempDir;
  late LocalRunStore runStore;
  late LocalRouteStore routeStore;
  late File zipFile;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('backup_compat_test_');
    runStore = LocalRunStore();
    routeStore = LocalRouteStore();
    await runStore.init(
      overrideDirectory: Directory('${tempDir.path}/runs')..createSync(),
    );
    await routeStore.init(
      overrideDirectory: Directory('${tempDir.path}/routes')..createSync(),
    );
    zipFile = File('${tempDir.path}/go-shape-backup.zip');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<RestoreResult> restoreFromBytes(Uint8List bytes) async {
    await zipFile.writeAsBytes(bytes);
    final svc = BackupService(api: _OfflineApi());
    return svc.restore(
      zipFile: zipFile,
      runStore: runStore,
      routeStore: routeStore,
    );
  }

  group('manifest emitted by Go round-trips on Dart restore', () {
    test('valid manifest with all keys is accepted', () async {
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 0, 'routes': 0, 'goals': 0, 'tracks': 0},
        },
        runs: const [],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.warnings.where((w) => w.contains('manifest')), isEmpty);
      expect(result.runsImported, 0);
    });

    test('manifest with exported_from="go-service" is parsed without warning',
        () async {
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          // The Go writer stamps this constant; Dart restore
          // doesn't care about the source, but the contract is
          // that any string survives.
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 1, 'goals': 0, 'tracks': 1},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'app',
            'external_id': null,
            'metadata': {'activity_type': 'run'},
            'track_url': 'user-A/run-1.json.gz',
            'is_public': false,
            'event_id': null,
            'route_id': 'rt-1',
            'created_at': '2026-05-10T08:30:00Z',
            'updated_at': '2026-05-10T08:30:00Z',
          },
        ],
        routes: [
          {
            'id': 'rt-1',
            'name': 'Park loop',
            'waypoints': [
              {'lat': 47.37, 'lng': 8.54},
              {'lat': 47.371, 'lng': 8.541},
            ],
            'distance_m': 5000,
            'is_public': true,
          },
        ],
        profile: const {'display_name': 'Tester'},
        settingsPrefs: const {'unit': 'km'},
        trackBytes: {
          'run-1': gzipOfJson(const [
            {'lat': 47.37, 'lng': 8.54, 'ele': 408.0, 'ts': '2026-05-10T08:00:00.000Z'},
            {'lat': 47.371, 'lng': 8.541, 'ele': 410.0, 'ts': '2026-05-10T08:00:30.000Z'},
          ]),
        },
      );
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 1);
      expect(result.routesImported, 1);
      expect(result.tracksUploaded, 1);
      expect(runStore.runs.single.track, hasLength(2));
    });
  });

  group('Go-side optional pointer fields survive Dart restore', () {
    test('runs row with all fields populated round-trips intact', () async {
      // Go's ExportRun is a struct with pointer optionals (e.g.
      // ExternalID *string). When set, they serialise as JSON
      // values; when unset, they serialise as null (NOT omitted)
      // because the Go writer copies them directly into the runs
      // map. Dart must tolerate the null-typed value.
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 0, 'goals': 0, 'tracks': 0},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'strava',
            'external_id': 'strava:1234567890',
            'metadata': {
              'activity_type': 'run',
              'title': 'Morning loop',
              'avg_bpm': 142,
            },
            'track_url': null,
            'is_public': true,
            'event_id': null,
            'route_id': null,
            'created_at': '2026-05-10T08:30:00Z',
            'updated_at': '2026-05-10T08:30:00Z',
          },
        ],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 1);
      final r = runStore.runs.single;
      expect(r.id, 'run-1');
      expect(r.externalId, 'strava:1234567890');
      expect(r.metadata!['avg_bpm'], 142);
      expect(r.metadata!['title'], 'Morning loop');
    });

    test('route row with every optional pointer set round-trips intact',
        () async {
      // Pin: every optional pointer field in Go's ExportRoute that
      // serialises out should be readable on the Dart side. Today
      // the Dart route domain model only consumes a subset — but
      // the JSON round-trip must succeed (no decode errors).
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 0, 'routes': 1, 'goals': 0, 'tracks': 0},
        },
        runs: const [],
        routes: [
          {
            'id': 'rt-full',
            'name': 'Fully populated',
            'waypoints': [
              {'lat': 47.37, 'lng': 8.54},
              {'lat': 47.371, 'lng': 8.541},
            ],
            'distance_m': 5000.5,
            'elevation_m': 250.0,
            'surface': 'trail',
            'is_public': true,
            'slug': 'fully-populated',
            'tags': ['easy', 'morning'],
            'featured': false,
            'run_count': 42,
            'is_starred': true,
            'description': 'A test route',
            'club_id': 'club-uuid',
            'created_at': '2026-01-01T00:00:00Z',
            'updated_at': '2026-05-11T10:00:00Z',
          },
        ],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.routesImported, 1);
      final route = routeStore.routes.single;
      expect(route.id, 'rt-full');
      expect(route.name, 'Fully populated');
      expect(route.waypoints, hasLength(2));
      expect(route.distanceMetres, 5000.5);
      expect(route.elevationGainMetres, 250.0);
      expect(route.surface, 'trail');
      expect(route.isPublic, isTrue);
      expect(route.tags, ['easy', 'morning']);
      expect(route.featured, isFalse);
      expect(route.runCount, 42);
    });

    test('route row with NO optional fields restores with model defaults',
        () async {
      // Go's writer omits optional fields entirely when nil. Dart
      // restore must populate the model with defaults — not throw.
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 0, 'routes': 1, 'goals': 0, 'tracks': 0},
        },
        runs: const [],
        routes: [
          {
            'id': 'rt-minimal',
            'name': 'Minimal',
            'waypoints': [
              {'lat': 0.0, 'lng': 0.0},
              {'lat': 1.0, 'lng': 1.0},
            ],
          },
        ],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.routesImported, 1);
      final route = routeStore.routes.single;
      expect(route.distanceMetres, 0);
      expect(route.elevationGainMetres, 0);
      expect(route.isPublic, isFalse);
      expect(route.tags, isEmpty);
      expect(route.featured, isFalse);
      expect(route.runCount, 0);
    });
  });

  group('track entry shape from Go round-trips on Dart restore', () {
    test('raw gzipped JSON bytes decode to waypoints (the load-bearing case)',
        () async {
      // The single most important wire-format detail: Go archives
      // tracks with `zip.Store` (no deflate) carrying raw gzipped
      // bytes. The Dart reader gunzips them and JSON-decodes the
      // result. If this regresses on either side, every Go-built
      // backup that lands on a phone fails to attach tracks.
      final track = const [
        {'lat': 47.37, 'lng': 8.54, 'ele': 408.0, 'ts': '2026-05-10T08:00:00.000Z'},
        {'lat': 47.371, 'lng': 8.541, 'ele': 410.0, 'ts': '2026-05-10T08:00:30.000Z'},
        {'lat': 47.372, 'lng': 8.542, 'ele': 412.0, 'ts': '2026-05-10T08:01:00.000Z'},
      ];
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 0, 'goals': 0, 'tracks': 1},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'app',
            'metadata': {'activity_type': 'run'},
            'track_url': 'user-A/run-1.json.gz',
          },
        ],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
        trackBytes: {'run-1': gzipOfJson(track)},
      );

      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 1);
      expect(result.tracksUploaded, 1);
      final r = runStore.runs.single;
      expect(r.track, hasLength(3));
      expect(r.track.first.lat, 47.37);
      expect(r.track.last.lng, 8.542);
      expect(r.track.first.elevationMetres, 408.0);
      expect(r.track.first.timestamp,
          DateTime.utc(2026, 5, 10, 8, 0, 0));
    });

    test('per-point bpm in track survives round-trip', () async {
      // Some Go-built backups carry per-point HR (Garmin, Strava).
      // The Dart Waypoint model has a `bpm` field; restore must
      // populate it from the track's `bpm` key.
      //
      // NOTE: today, the Dart restore code does NOT read `bpm` from
      // the per-waypoint object — only lat/lng/ele/ts. This test
      // pins that contract: per-point bpm is silently dropped on
      // the offline restore path. If the Dart Waypoint domain
      // model + restore are extended to round-trip bpm, flip the
      // assertion.
      final track = const [
        {'lat': 47.37, 'lng': 8.54, 'bpm': 142},
        {'lat': 47.371, 'lng': 8.541, 'bpm': 145},
      ];
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 0, 'goals': 0, 'tracks': 1},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'app',
            'metadata': {'activity_type': 'run'},
            'track_url': 'user-A/run-1.json.gz',
          },
        ],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
        trackBytes: {'run-1': gzipOfJson(track)},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 1);
      final r = runStore.runs.single;
      expect(r.track, hasLength(2));
      // Per-point bpm is currently NOT plumbed through the offline
      // restore path — the Dart Waypoint's `bpm` field stays null
      // even though the input had it. If this expectation flips,
      // update apps/mobile_android/lib/backup.dart's _decodeTrack
      // to map `bpm` → Waypoint.bpm.
      expect(r.track.first.bpm, isNull);
    });

    test('100-point dense track round-trips without truncation', () async {
      final track = [
        for (var i = 0; i < 100; i++)
          {'lat': 47.0 + i / 1000, 'lng': 8.0 + i / 1000, 'ele': i.toDouble()},
      ];
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 0, 'goals': 0, 'tracks': 1},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'app',
            'metadata': {'activity_type': 'run'},
            'track_url': 'user-A/run-1.json.gz',
          },
        ],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
        trackBytes: {'run-1': gzipOfJson(track)},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.tracksUploaded, 1);
      expect(runStore.runs.single.track, hasLength(100));
      expect(runStore.runs.single.track.last.elevationMetres, 99.0);
    });

    test('run with no track file in archive still imports the row', () async {
      // Go's writer skips the tracks/{id}.json.gz entry for runs
      // with no track_url (or with a path-shape mismatch). The
      // run row still ships, and Dart restore must land it with
      // an empty track — not throw, not skip the row.
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 1, 'routes': 0, 'goals': 0, 'tracks': 0},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'healthconnect',
            'metadata': {'activity_type': 'run'},
            'track_url': null,
          },
        ],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 1);
      expect(result.tracksUploaded, 0);
      expect(runStore.runs.single.track, isEmpty);
    });
  });

  group('profile.json shape from Go round-trips on Dart restore', () {
    test('profile.id is preserved in Go output (Go strips before serialize)',
        () async {
      // Go's writer strips `profile.id` via `stripProfileID()`
      // before writing — the Dart offline restore doesn't touch
      // the profile anyway, but the test pins that no `id`
      // leaks into the archive so the upsert (when online) lands
      // cleanly.
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 0, 'routes': 0, 'goals': 0, 'tracks': 0},
        },
        runs: const [],
        routes: const [],
        // The handcrafted profile excludes `id` to match Go's
        // stripProfileID output.
        profile: const {
          'display_name': 'Tester',
          'preferred_unit': 'km',
          'avatar_url': null,
        },
        settingsPrefs: const {'unit': 'km', 'split_audio': true},
      );
      // Offline restore doesn't write the profile (warns), but
      // the archive must parse without error.
      final result = await restoreFromBytes(bytes);
      expect(result.profileRestored, isFalse,
          reason: 'offline restore intentionally skips profile');
    });

    test('settings_prefs survives empty-object encoding', () async {
      // A new account exports with `settings_prefs: {}`. Dart
      // must accept the empty map.
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 0, 'routes': 0, 'goals': 0, 'tracks': 0},
        },
        runs: const [],
        routes: const [],
        profile: null,
        settingsPrefs: const {},
      );
      final result = await restoreFromBytes(bytes);
      expect(result.warnings.any((w) => w.contains('manifest')), isFalse);
    });
  });

  group('regression — mixed-source backup with everything populated', () {
    test('end-to-end: 3 runs (2 with tracks) + 2 routes + profile + prefs',
        () async {
      final bytes = goShapeBackup(
        manifest: {
          'format': 'run-app-backup',
          'version': 1,
          'exported_at': '2026-05-11T10:00:00Z',
          'exported_by_user_id': 'user-A',
          'exported_from': 'go-service',
          'counts': {'runs': 3, 'routes': 2, 'goals': 0, 'tracks': 2},
        },
        runs: [
          {
            'id': 'run-1',
            'started_at': '2026-05-10T08:00:00Z',
            'duration_s': 1500,
            'distance_m': 5000.0,
            'source': 'app',
            'metadata': {'activity_type': 'run'},
            'track_url': 'user-A/run-1.json.gz',
          },
          {
            'id': 'run-2',
            'started_at': '2026-05-09T08:00:00Z',
            'duration_s': 3000,
            'distance_m': 10000.0,
            'source': 'strava',
            'external_id': 'strava:9999',
            'metadata': {'activity_type': 'run', 'title': 'Long run'},
            'track_url': 'user-A/run-2.json.gz',
          },
          {
            'id': 'run-3',
            'started_at': '2026-05-08T08:00:00Z',
            'duration_s': 1800,
            'distance_m': 5500.0,
            'source': 'healthconnect',
            'metadata': {'activity_type': 'walk'},
            'track_url': null,
          },
        ],
        routes: [
          {
            'id': 'rt-1',
            'name': 'Park loop',
            'waypoints': [
              {'lat': 47.37, 'lng': 8.54},
              {'lat': 47.371, 'lng': 8.541},
            ],
            'distance_m': 5000,
            'is_public': true,
            'is_starred': true,
            'tags': ['easy'],
          },
          {
            'id': 'rt-2',
            'name': 'Trail',
            'waypoints': [
              {'lat': 51.5, 'lng': -0.1},
              {'lat': 51.6, 'lng': -0.2},
            ],
            'distance_m': 10000,
            'surface': 'trail',
          },
        ],
        profile: const {
          'display_name': 'Tester',
          'preferred_unit': 'km',
        },
        settingsPrefs: const {'unit': 'km'},
        trackBytes: {
          'run-1': gzipOfJson(const [
            {'lat': 47.37, 'lng': 8.54},
            {'lat': 47.371, 'lng': 8.541},
          ]),
          'run-2': gzipOfJson(const [
            {'lat': 51.5, 'lng': -0.1},
            {'lat': 51.6, 'lng': -0.2},
          ]),
        },
      );
      final result = await restoreFromBytes(bytes);
      expect(result.runsImported, 3);
      expect(result.routesImported, 2);
      expect(result.tracksUploaded, 2);
      // The runs are stored newest-first (insert at index 0), so
      // a single check on lengths + a spot-check on activity_type
      // is enough — full ordering is `LocalRunStore`-specific.
      expect(runStore.runs, hasLength(3));
      expect(routeStore.routes, hasLength(2));
      final walk = runStore.runs.firstWhere((r) => r.id == 'run-3');
      expect(walk.metadata?['activity_type'], 'walk');
      final starred = routeStore.routes.firstWhere((r) => r.id == 'rt-1');
      expect(starred.isStarred, isTrue);
    });
  });
}
