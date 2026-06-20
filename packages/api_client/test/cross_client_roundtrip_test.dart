@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Cross-client round-trip — the Dart **write** half.
///
/// This test saves a fixture run through the Dart `ApiClient.saveRun`
/// against a LIVE local Supabase stack, then writes the run id + the
/// fixture's expected field values to a JSON file on disk. A sibling
/// Node script (`apps/web/scripts/cross_client_roundtrip_read.mjs`)
/// reads the SAME run back through the web data layer's read shape and
/// asserts field-for-field equality against that fixture.
///
/// The point is a *runtime* drift check the static `gen:types:check`
/// can't make: the TS and Dart row types are generated from the same
/// migrations, but nothing proves that a value the Dart client writes
/// (a duration in seconds, a `metadata.steps` int, an `activity_type`,
/// a `RunSource` enum name) is read back as the same value by the web
/// client. A serialisation skew — say the Dart side writing steps as a
/// string while the web side `parseInt`s it, or a timezone bug in the
/// `started_at` write — round-trips incorrectly and this catches it.
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** (same gate as
/// `api_client_integration_test.dart`). Run locally with:
/// ```
/// cd apps/backend && supabase status -o env   # copy ANON_KEY
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY>
/// export CROSS_CLIENT_FIXTURE_OUT=/abs/path/to/fixture.json
/// cd packages/api_client
/// flutter test test/cross_client_roundtrip_test.dart
/// ```
/// then run the Node read half pointed at the same fixture file.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
const _fixtureOut = String.fromEnvironment('CROSS_CLIENT_FIXTURE_OUT');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';
  final fixtureOut = _fixtureOut.isNotEmpty
      ? _fixtureOut
      : Platform.environment['CROSS_CLIENT_FIXTURE_OUT'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'cross-client round-trip — skipped (SUPABASE_TEST_URL not set)',
      () {},
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run this '
          'test against a local Supabase (see file header).',
    );
    return;
  }

  group('cross-client round-trip — Dart write half', () {
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

    test('saveRun persists a fixture run and emits the expected-field '
        'fixture for the Node read half', () async {
      // A deterministic-but-unique id so re-runs don't collide and so
      // the Node half can find exactly this row. The hex suffix is
      // derived from a microsecond clock — same shape as the existing
      // saveRun integration test.
      final id = '0badf00d-0000-4000-8000-' +
          DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);

      // A deliberate UTC instant so the UTC-normalisation in saveRun
      // (run.startedAt.toUtc()) is exercised; the Node half compares
      // the instant, not the wall-clock string.
      final startedAt = DateTime.utc(2026, 6, 20, 14, 30, 15);

      final run = Run(
        id: id,
        startedAt: startedAt,
        duration: const Duration(minutes: 42, seconds: 7),
        distanceMetres: 8123.5,
        track: const [
          Waypoint(lat: 47.37, lng: 8.54),
          Waypoint(lat: 47.38, lng: 8.55),
          Waypoint(lat: 47.39, lng: 8.56),
        ],
        source: RunSource.healthkit,
        metadata: const {
          // `activity_type` is promoted to its own column on write
          // (saveRun), then re-overlaid by the web read. Round-trips
          // through the promoted column, not the bag.
          'activity_type': 'run',
          // `steps` is the headline jsonb-bag round-trip: stored as a
          // JSON number, read back by the web as `metadata.steps` and
          // `parseInt`-ed. A skew (string-vs-number) shows up here.
          'steps': 5234,
          // A float metadata key — age_grade is a documented jsonb key
          // and a float survives jsonb only if neither side coerces it.
          'age_grade': 61.7,
        },
      );

      await api.saveRun(run);

      // The fixture the Node read half will assert against. These are
      // the canonical expected values — written once here, never
      // duplicated in the Node script.
      final fixture = {
        'run_id': id,
        'distance_m': 8123.5,
        'duration_s': 42 * 60 + 7,
        'source': 'healthkit',
        'activity_type': 'run',
        'started_at_iso': startedAt.toUtc().toIso8601String(),
        'metadata_steps': 5234,
        'metadata_age_grade': 61.7,
        'track_point_count': 3,
        'track_first_lat': 47.37,
        'track_last_lng': 8.56,
      };

      // Sanity-check the write from the Dart side before handing off to
      // Node: read the row straight back via getRuns so a save that
      // silently no-op'd fails here with a Dart-side message rather
      // than as an opaque Node assertion.
      final all = await api.getRuns(limit: 200);
      final saved = all.where((r) => r.id == id).toList();
      expect(saved, hasLength(1),
          reason: 'saveRun must persist a row visible via getRuns');
      expect(saved.first.distanceMetres, 8123.5);
      expect(saved.first.duration, const Duration(minutes: 42, seconds: 7));
      expect(saved.first.source, RunSource.healthkit);

      if (fixtureOut.isNotEmpty) {
        File(fixtureOut).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(fixture));
      }
    });
  });
}
