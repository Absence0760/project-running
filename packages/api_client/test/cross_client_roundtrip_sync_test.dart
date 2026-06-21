@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Cross-client round-trip for the SYNC path — the Dart **write** half.
///
/// Sibling of `cross_client_roundtrip_test.dart` (completed runs),
/// `cross_client_roundtrip_route_test.dart` (routes), and
/// `cross_client_roundtrip_live_test.dart` (in-progress runs). Where the
/// run round-trip saves a run ONCE, this one exercises the mobile **sync
/// semantics**: a run is saved with a real GPS track (uploaded to Storage),
/// then RE-SAVED through the same `saveRun` path with edited stats + an
/// empty `track` but the existing `metadata['track_url']` carried forward —
/// the exact shape the sync layer / edit dialog produces for a
/// metadata-only / newer-wins edit. The expectation is that the second save
/// updates the editable columns (newer-wins) WITHOUT re-uploading or
/// nulling the track. A sibling Node script
/// (`apps/web/scripts/cross_client_roundtrip_sync_read.mjs`) re-reads the
/// SAME run through the web's `fetchRunById` shape and asserts the edited
/// fields landed AND the original GPS trace survived intact.
///
/// The point is the same *runtime* drift check the other round-trips make
/// (which the static `gen:types:check` can't): sync-conflict bugs — a
/// metadata-only edit that re-uploads or clobbers the track, a re-save that
/// drops the existing `track_url`, a newer-wins update that doesn't actually
/// overwrite the stale stats — have been a recurring source of cross-client
/// drift. This catches them by writing through the real save path twice and
/// reading back through the real web read path.
///
/// **Sync-specific concerns this fixture exercises:**
///   * the first `saveRun` uploads a real track to
///     `{user_id}/{run_id}.json.gz` and stores `track_url`;
///   * the second `saveRun` carries an EMPTY `track` + the existing
///     `metadata['track_url']` (the `_runFromRow` stash shape) — `saveRun`
///     must preserve that url rather than re-upload or null it;
///   * the second save is the newer-wins edit: distance, duration, and the
///     metadata bag (`steps`, `notes`) are all changed and must overwrite
///     the first save's values;
///   * the GPS track downloaded after the edit is byte-for-byte the
///     ORIGINAL trace (the metadata edit never touched Storage).
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** (same gate as the run +
/// route + live round-trips). Run locally with:
/// ```
/// cd apps/backend && supabase status -o env   # copy ANON_KEY
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY>
/// export CROSS_CLIENT_SYNC_FIXTURE_OUT=/abs/path/to/sync_fixture.json
/// cd packages/api_client
/// flutter test test/cross_client_roundtrip_sync_test.dart
/// ```
/// then run the Node read half pointed at the same fixture file.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
const _fixtureOut = String.fromEnvironment('CROSS_CLIENT_SYNC_FIXTURE_OUT');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';
  final fixtureOut = _fixtureOut.isNotEmpty
      ? _fixtureOut
      : Platform.environment['CROSS_CLIENT_SYNC_FIXTURE_OUT'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'cross-client sync round-trip — skipped (SUPABASE_TEST_URL not set)',
      () {},
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run this '
          'test against a local Supabase (see file header).',
    );
    return;
  }

  group('cross-client sync round-trip — Dart write half', () {
    late SupabaseClient client;
    late ApiClient api;

    setUp(() async {
      client = SupabaseClient(url, anonKey);
      api = ApiClient.withClient(client);
      await api.signIn(email: 'runner@test.com', password: 'testtest');
    });

    tearDown(() async {
      try {
        await api.signOut();
      } catch (_) {}
      client.dispose();
    });

    test('saveRun then a metadata-only re-save preserves the track and '
        'applies the newer-wins edit, emitting the fixture for the Node '
        'read half', () async {
      // A deterministic-but-unique id (distinct namespace from the run
      // round-trip's `0badf00d-…`, the route round-trip's `0badcafe-…`, and
      // the live round-trip's `0badbeef-…`) so re-runs don't collide and the
      // Node half can find exactly this row.
      final id = '0badd00d-0000-4000-8000-' +
          DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);

      final startedAt = DateTime.utc(2026, 6, 20, 14, 30, 15);

      const track = [
        Waypoint(lat: 47.37, lng: 8.54),
        Waypoint(lat: 47.38, lng: 8.55),
        Waypoint(lat: 47.39, lng: 8.56),
        Waypoint(lat: 47.40, lng: 8.57),
      ];

      // 1) First save: a complete run WITH a GPS track. This uploads the
      //    track to Storage and stores `track_url`.
      final original = Run(
        id: id,
        startedAt: startedAt,
        duration: const Duration(minutes: 40, seconds: 0),
        distanceMetres: 8000.0,
        track: track,
        source: RunSource.app,
        metadata: const {
          'activity_type': 'run',
          'steps': 5000,
        },
      );
      await api.saveRun(original);

      // Read the row back to recover the stashed `track_url`
      // (`_runFromRow` puts it on `metadata['track_url']`). This is the
      // shape the sync layer / edit dialog re-saves from.
      final afterFirst = await api.getRuns(limit: 200);
      final firstRow = afterFirst.firstWhere((r) => r.id == id);
      final trackUrl = firstRow.metadata?['track_url'] as String?;
      expect(trackUrl, isNotNull,
          reason: 'the first saveRun must persist a track_url');
      expect(trackUrl, isNotEmpty);

      // 2) Newer-wins, metadata-only re-save: edited duration + distance +
      //    metadata, an EMPTY track, and the existing `track_url` carried
      //    forward on metadata — exactly what the sync path produces for a
      //    metadata-only edit. `saveRun` must preserve the track_url (no
      //    re-upload, no null) and overwrite the stale stats.
      final edited = Run(
        id: id,
        startedAt: startedAt,
        duration: const Duration(minutes: 38, seconds: 30),
        distanceMetres: 8250.0,
        track: const [],
        source: RunSource.app,
        metadata: {
          'activity_type': 'run',
          'steps': 5400,
          'notes': 'edited after sync',
          'track_url': trackUrl,
        },
      );
      await api.saveRun(edited);

      // The fixture the Node read half will assert against. Canonical
      // expected values — written once here, never duplicated in Node.
      final fixture = {
        'run_id': id,
        'started_at_iso': startedAt.toUtc().toIso8601String(),
        // The newer-wins edit values (NOT the first save's 8000 / 2400).
        'distance_m': 8250.0,
        'duration_s': 38 * 60 + 30,
        'metadata_steps': 5400,
        'metadata_notes': 'edited after sync',
        'activity_type': 'run',
        // The track_url + the original trace must survive the metadata edit.
        'track_url': trackUrl,
        'track_point_count': 4,
        'track_first_lat': 47.37,
        'track_last_lng': 8.57,
      };

      // Sanity-check the sync semantics from the Dart side before handing
      // off to Node: the re-save must NOT have changed the track_url, and
      // the original GPS trace must still download intact. A sync bug that
      // re-uploaded or nulled the track fails here with a Dart-side message
      // rather than as an opaque Node assertion.
      final afterEdit = await api.getRuns(limit: 200);
      final editedRow = afterEdit.firstWhere((r) => r.id == id);
      expect(editedRow.distanceMetres, 8250.0,
          reason: 'the newer-wins edit must overwrite the stale distance');
      expect(editedRow.duration, const Duration(minutes: 38, seconds: 30));
      expect(editedRow.metadata?['track_url'], trackUrl,
          reason: 'the metadata-only edit must preserve the track_url');
      final reloadedTrack = await api.fetchTrack(editedRow);
      expect(reloadedTrack, hasLength(4),
          reason: 'the original GPS track must survive the metadata edit');
      expect(reloadedTrack.first.lat, 47.37);
      expect(reloadedTrack.last.lng, 8.57);

      if (fixtureOut.isNotEmpty) {
        File(fixtureOut).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(fixture));
      }
    });
  });
}
