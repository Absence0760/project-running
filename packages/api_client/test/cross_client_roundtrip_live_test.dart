@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Cross-client round-trip for IN-PROGRESS (live spectator) runs — the
/// Dart **write** half.
///
/// Sibling of `cross_client_roundtrip_test.dart` (completed runs) and
/// `cross_client_roundtrip_route_test.dart` (routes). Opens an in-progress
/// run through the Dart `ApiClient.beginLiveBroadcast` + appends a few
/// `live_run_pings` via `ApiClient.insertLivePing` against a LIVE local
/// Supabase stack, then writes the run id + the fixture's expected field
/// values to a JSON file on disk. A sibling Node script
/// (`apps/web/scripts/cross_client_roundtrip_live_read.mjs`) re-reads the
/// SAME live run + pings back through the web's `/live/[id]` catch-up read
/// shape and asserts field-for-field equality against that fixture.
///
/// The point is the same *runtime* drift check the run + route round-trips
/// make (which the static `gen:types:check` can't): nothing proves a value
/// the Dart live broadcaster writes (a ping's `lat`/`lng`/`ele`, its
/// `distance_m` float, its `elapsed_s` int, the per-ping `at` instant, the
/// in-progress stub run's `metadata.in_progress` marker + `is_public` flag)
/// is read back as the same value by the web spectator page.
///
/// **In-progress-run-specific concerns this fixture exercises:**
///   * the in-progress run is a STUB `runs` row (`distance_m = 0`,
///     `is_public = true`) created by `beginLiveBroadcast`. The spectator
///     surface reads it through the `public_runs` view — which only
///     contains the row when `is_public = true` — so the round-trip
///     asserts the row is visible there at all and that `distance_m`
///     round-trips as the stub 0. (The base-row `metadata.in_progress`
///     marker is deliberately stripped by the `public_runs` view, so the
///     spectator never sees it — it is NOT part of this read shape.)
///   * each `live_run_pings` row's `lat`/`lng`/`ele`/`distance_m`/`elapsed_s`
///     survive the insert and re-read in chronological `at` order — the web
///     catch-up query selects exactly these columns ordered by `at asc`;
///   * the trigger-owned `coarse` column (migration `20270121_001`) defaults
///     false for an out-of-zone ping and is part of the web read shape; the
///     fixture asserts the round-trip stays false (the seed user has no
///     privacy zones, so the `live_run_pings_drop_in_zone` BEFORE-INSERT
///     trigger passes every ping through unchanged).
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** (same gate as the run +
/// route round-trips). Run locally with:
/// ```
/// cd apps/backend && supabase status -o env   # copy ANON_KEY
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY>
/// export CROSS_CLIENT_LIVE_FIXTURE_OUT=/abs/path/to/live_fixture.json
/// cd packages/api_client
/// flutter test test/cross_client_roundtrip_live_test.dart
/// ```
/// then run the Node read half pointed at the same fixture file.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
const _fixtureOut = String.fromEnvironment('CROSS_CLIENT_LIVE_FIXTURE_OUT');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';
  final fixtureOut = _fixtureOut.isNotEmpty
      ? _fixtureOut
      : Platform.environment['CROSS_CLIENT_LIVE_FIXTURE_OUT'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'cross-client live round-trip — skipped (SUPABASE_TEST_URL not set)',
      () {},
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run this '
          'test against a local Supabase (see file header).',
    );
    return;
  }

  group('cross-client live round-trip — Dart write half', () {
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

    test('beginLiveBroadcast + insertLivePing persist an in-progress run '
        'and emit the expected-field fixture for the Node read half',
        () async {
      // A deterministic-but-unique id (distinct namespace from the run
      // round-trip's `0badf00d-…` and the route round-trip's `0badcafe-…`)
      // so re-runs don't collide and the Node half can find exactly this
      // row.
      final id = '0badbeef-0000-4000-8000-' +
          DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);

      final startedAt = DateTime.utc(2026, 6, 20, 14, 30, 15);

      await api.beginLiveBroadcast(runId: id, startedAt: startedAt);

      // Three pings outside any privacy zone (the seed user has none), in
      // emission order. The web catch-up query orders by `at asc`, so the
      // fixture asserts the first + last ping by that ordering. Floats +
      // an int + an elevation exercise the same per-field serialisation the
      // completed-run track does, but through the per-ping insert path.
      final pings = [
        {
          'lat': 47.37,
          'lng': 8.54,
          'ele': 408.2,
          'distance_m': 0.0,
          'elapsed_s': 0,
        },
        {
          'lat': 47.38,
          'lng': 8.55,
          'ele': 415.6,
          'distance_m': 152.4,
          'elapsed_s': 30,
        },
        {
          'lat': 47.39,
          'lng': 8.56,
          'ele': 402.1,
          'distance_m': 311.8,
          'elapsed_s': 61,
        },
      ];

      for (final p in pings) {
        await api.insertLivePing(
          runId: id,
          lat: p['lat']! as double,
          lng: p['lng']! as double,
          ele: p['ele']! as double,
          distanceM: p['distance_m']! as double,
          elapsedS: p['elapsed_s']! as int,
        );
      }

      // The fixture the Node read half will assert against. Canonical
      // expected values — written once here, never duplicated in Node.
      final fixture = {
        'run_id': id,
        'started_at_iso': startedAt.toUtc().toIso8601String(),
        'distance_m': 0.0,
        'ping_count': 3,
        'first_lat': 47.37,
        'first_lng': 8.54,
        'first_ele': 408.2,
        'first_distance_m': 0.0,
        'first_elapsed_s': 0,
        'last_lat': 47.39,
        'last_lng': 8.56,
        'last_ele': 402.1,
        'last_distance_m': 311.8,
        'last_elapsed_s': 61,
        // `coarse` is trigger-owned (migration 20270121_001), defaults false,
        // and is NOT written by insertLivePing. An out-of-zone ping stays
        // false; the read half asserts the round-trip.
        'coarse': false,
      };

      // Sanity-check the write from the Dart side before handing off to
      // Node: read the pings straight back via fetchLiveRunPings so a write
      // that silently no-op'd (or got dropped by the privacy-zone trigger)
      // fails here with a Dart-side message rather than as an opaque Node
      // assertion.
      final readBack = await api.fetchLiveRunPings(id);
      expect(readBack, hasLength(3),
          reason: 'insertLivePing must persist 3 pings visible via '
              'fetchLiveRunPings — none dropped by the privacy-zone trigger');
      expect(readBack.first['lat'], 47.37);
      expect(readBack.first['distance_m'], 0.0);
      expect(readBack.last['lng'], 8.56);
      expect(readBack.last['elapsed_s'], 61);

      if (fixtureOut.isNotEmpty) {
        File(fixtureOut).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(fixture));
      }
    });
  });
}
