@TestOn('vm')
library;

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Wire-level integration tests for `ApiClient` priority methods —
/// `signIn` / `getRuns` / `fetchTrack` / `saveRun` (which transitively
/// exercises `_uploadTrack`).
///
/// **Skipped unless `SUPABASE_TEST_URL` is set.** These tests need a
/// live local Supabase stack on the URL pointed to by the env vars
/// below, with the project's `seed.sql` applied (`supabase db reset
/// --local` from `apps/backend`). The seed user `runner@test.com /
/// testtest` is the fixture: 12 runs, 5 routes, two connected
/// integrations.
///
/// Run locally with:
/// ```
/// cd apps/backend && supabase status -o env
/// # …
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY from `supabase status`>
/// cd ../../packages/api_client
/// flutter test test/api_client_integration_test.dart
/// ```
///
/// Why integration tests rather than mocktail mocks: the methods under
/// test are predominantly chained PostgREST + Storage builder calls
/// (`_client.from(...).upsert(...)`, `_client.storage.from(...)
/// .upload(...)`). Mocking the fluent surface end-to-end is verbose
/// enough that the test would mostly assert "we called the methods
/// in this order" rather than "the wire shape is correct" — i.e.
/// re-implementing the methods inside the mock. Real Supabase is the
/// authoritative fixture (cf. docs/testing.md "No mocks for databases
/// we control").
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');

void main() {
  // The env-var indirection through `String.fromEnvironment` means
  // these are baked in at compile time when `--dart-define` is used.
  // The Platform.environment fallback covers the shell-export path,
  // which is what the local-dev recipe above uses.
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'ApiClient integration tests — skipped (SUPABASE_TEST_URL not set)',
      () {
        // Intentional no-op. CI without a Supabase stack still sees a
        // passing test; locally with the env vars set, the real tests
        // below run.
      },
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run '
          'these tests against a local Supabase (see file header).',
    );
    return;
  }

  group('ApiClient — wire-level integration (real local Supabase)', () {
    late SupabaseClient client;
    late ApiClient api;
    String? userId;
    final inserted = <String>[];

    setUp(() async {
      // Each test gets a fresh SupabaseClient so the auth state of one
      // test never bleeds into the next (the GoTrue client owns a
      // session that's per-instance, not per-test).
      client = SupabaseClient(url, anonKey);
      api = ApiClient.withClient(client);
      userId = await api.signIn(email: 'runner@test.com', password: 'testtest');
    });

    tearDown(() async {
      // Clean up any rows the test inserted before signing out, so
      // the seed user's row count stays stable across runs.
      for (final runId in inserted) {
        try {
          await api.deleteRunById(runId);
        } catch (_) {
          // Best-effort. If the row's already gone, that's fine.
        }
      }
      inserted.clear();
      try {
        await api.signOut();
      } catch (_) {}
      client.dispose();
    });

    test('signIn returns the seed user id', () {
      // signIn ran in setUp; just assert the returned value.
      expect(userId, isNotNull);
      expect(userId, isA<String>());
      expect(userId!.length, greaterThan(8));
    });

    test('getRuns returns the seeded runs for runner@test.com', () async {
      final runs = await api.getRuns();
      // seed.sql provisions exactly 12 runs for this user.
      expect(runs.length, greaterThanOrEqualTo(12));
      // Tracks are NOT eagerly loaded — dashboard list never wants them.
      // Pin that contract.
      expect(runs.first.track, isEmpty,
          reason: 'getRuns must return Run objects with empty track; '
              'callers download via fetchTrack on demand.');
      // Newest-first ordering pinned by the api_client comment.
      for (var i = 1; i < runs.length; i++) {
        expect(
          runs[i].startedAt.isAtSameMomentAs(runs[i - 1].startedAt) ||
              runs[i].startedAt.isBefore(runs[i - 1].startedAt),
          isTrue,
          reason: 'getRuns must return rows newest-first by startedAt',
        );
      }
    });

    test('saveRun + fetchTrack round-trip through Storage and the '
        'runs row (exercises _uploadTrack + fetchTrack)', () async {
      // The integration roundtrip pins three guarantees in one shot:
      //   1. saveRun persists the row (visible via getRuns).
      //   2. _uploadTrack uploads gzipped JSON bytes the runs bucket
      //      accepts (migration 20260815_001 mime allowlist — the
      //      contentType must be `application/gzip`, not
      //      `application/json`; the wrong one 415s silently).
      //   3. fetchTrack decodes the same payload back to the same
      //      waypoints.
      //
      // The seed runs in seed.sql set `track_url` to the canonical
      // path-shape (to exercise the path-shape CHECK constraint test)
      // but DON'T upload an actual file — a standalone fetchTrack
      // test against a seed run would 404 against the Storage object,
      // not the code under test. Generating + saving our own run
      // sidesteps that.
      // Build a tiny but real Run with a 3-point track. The
      // _uploadTrack path serialises this to gzipped JSON and writes
      // it to the `runs` Storage bucket at `{user_id}/{run_id}.json.gz`.
      final id = '00000000-0000-0000-0000-' + DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);
      final run = Run(
        id: id,
        startedAt: DateTime.now().toUtc(),
        duration: const Duration(minutes: 25),
        distanceMetres: 5000,
        track: const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.56),
        ],
        source: RunSource.app,
        // Required by `runs_metadata_activity_type_check` (migration
        // 20260601_001) — every row needs a non-empty
        // `metadata.activity_type`. Production mobile callsites
        // (add_run_screen, run_screen) populate it; the test must
        // too.
        metadata: const {'activity_type': 'run'},
      );
      inserted.add(id);

      await api.saveRun(run);

      // Read it back via getRuns and confirm the track is downloadable.
      final all = await api.getRuns(limit: 100);
      final saved = all.where((r) => r.id == id).toList();
      expect(saved, hasLength(1),
          reason: 'saveRun must persist a row visible to the same '
              'user via getRuns.');
      expect(saved.first.distanceMetres, 5000);
      expect(saved.first.duration, const Duration(minutes: 25));

      // The track url is in metadata['track_url'] after _runFromRow's
      // synthesised stash (see CLAUDE.md "Run.metadata is a jsonb
      // bag"). Use fetchTrack to verify the Storage upload landed.
      final downloaded = await api.fetchTrack(saved.first);
      expect(downloaded, hasLength(3),
          reason: 'fetchTrack must return the 3 waypoints that '
              'saveRun uploaded to Storage.');
      expect(downloaded.first.lat, closeTo(47.37, 0.001));
      expect(downloaded.last.lng, closeTo(8.56, 0.001));
    });
  });
}
