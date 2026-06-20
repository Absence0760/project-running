@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:test/test.dart';

/// Cross-client round-trip for ROUTES — the Dart **write** half.
///
/// Sibling of `cross_client_roundtrip_test.dart` (which covers runs).
/// Saves a fixture route through the Dart `ApiClient.saveRoute` against a
/// LIVE local Supabase stack, then writes the route id + the fixture's
/// expected field values to a JSON file on disk. A sibling Node script
/// (`apps/web/scripts/cross_client_roundtrip_route_read.mjs`) reads the
/// SAME route back through the web data layer's `fetchRouteById` read
/// shape and asserts field-for-field equality against that fixture.
///
/// The point is the same *runtime* drift check the runs round-trip makes
/// (which the static `gen:types:check` can't): the TS and Dart row types
/// are generated from the same migrations, but nothing proves a value the
/// Dart client writes (a `RouteSurface` narrow-union string, a waypoint's
/// `ele`, a tags array, a float distance/elevation) is read back as the
/// same value by the web client. A serialisation skew round-trips
/// incorrectly and this catches it.
///
/// **Routes-specific concerns this fixture exercises:**
///   * the `waypoints` jsonb array structure (`{lat,lng,ele}` per point) —
///     the Dart writer keys elevation as `ele`, the web reader consumes
///     `waypoints` straight off the row;
///   * the `RouteSurface` narrow union (`road`/`trail`/`mixed`) surviving
///     the round-trip;
///   * the NOT NULL `shadow_hidden` moderation column (migration
///     `20270218_001`): `saveRoute` strips it (it is trigger-owned), the
///     DB defaults it false, and `fetchRouteById` must not surface a
///     `shadow_hidden=true` route to a client. The fixture asserts the
///     read-back value is false.
///
/// **Skipped unless `SUPABASE_TEST_URL` is set** (same gate as
/// `cross_client_roundtrip_test.dart`). Run locally with:
/// ```
/// cd apps/backend && supabase status -o env   # copy ANON_KEY
/// export SUPABASE_TEST_URL=http://127.0.0.1:54321
/// export SUPABASE_TEST_ANON_KEY=<ANON_KEY>
/// export CROSS_CLIENT_ROUTE_FIXTURE_OUT=/abs/path/to/route_fixture.json
/// cd packages/api_client
/// flutter test test/cross_client_roundtrip_route_test.dart
/// ```
/// then run the Node read half pointed at the same fixture file.
const _testUrl = String.fromEnvironment('SUPABASE_TEST_URL');
const _testAnonKey = String.fromEnvironment('SUPABASE_TEST_ANON_KEY');
const _fixtureOut = String.fromEnvironment('CROSS_CLIENT_ROUTE_FIXTURE_OUT');

void main() {
  final url = _testUrl.isNotEmpty
      ? _testUrl
      : Platform.environment['SUPABASE_TEST_URL'] ?? '';
  final anonKey = _testAnonKey.isNotEmpty
      ? _testAnonKey
      : Platform.environment['SUPABASE_TEST_ANON_KEY'] ?? '';
  final fixtureOut = _fixtureOut.isNotEmpty
      ? _fixtureOut
      : Platform.environment['CROSS_CLIENT_ROUTE_FIXTURE_OUT'] ?? '';

  if (url.isEmpty || anonKey.isEmpty) {
    test(
      'cross-client route round-trip — skipped (SUPABASE_TEST_URL not set)',
      () {},
      skip: 'Set SUPABASE_TEST_URL + SUPABASE_TEST_ANON_KEY to run this '
          'test against a local Supabase (see file header).',
    );
    return;
  }

  group('cross-client route round-trip — Dart write half', () {
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

    test('saveRoute persists a fixture route and emits the expected-field '
        'fixture for the Node read half', () async {
      // A deterministic-but-unique id (distinct namespace from the run
      // round-trip's `0badf00d-…`) so re-runs don't collide and the Node
      // half can find exactly this row.
      final id = '0badcafe-0000-4000-8000-' +
          DateTime.now()
              .microsecondsSinceEpoch
              .toRadixString(16)
              .padLeft(12, '0')
              .substring(0, 12);

      final route = Route(
        id: id,
        name: 'Cross-client fixture loop',
        waypoints: const [
          Waypoint(lat: 47.37, lng: 8.54, elevationMetres: 408.2),
          Waypoint(lat: 47.38, lng: 8.55, elevationMetres: 415.6),
          Waypoint(lat: 47.39, lng: 8.56, elevationMetres: 402.1),
        ],
        distanceMetres: 5123.5,
        elevationGainMetres: 87.4,
        // The headline narrow-union round-trip: 'trail' must survive jsonb
        // and re-read as exactly 'trail' through the web RouteSurface union.
        surface: 'trail',
        tags: const ['5k', 'loop', 'hill'],
        isPublic: true,
        description: 'A fixture route for the cross-client round-trip.',
      );

      await api.saveRoute(route);

      // The fixture the Node read half will assert against. Canonical
      // expected values — written once here, never duplicated in Node.
      final fixture = {
        'route_id': id,
        'name': 'Cross-client fixture loop',
        'distance_m': 5123.5,
        'elevation_m': 87.4,
        'surface': 'trail',
        'is_public': true,
        'tags': const ['5k', 'loop', 'hill'],
        'description': 'A fixture route for the cross-client round-trip.',
        'waypoint_count': 3,
        'wp_first_lat': 47.37,
        'wp_first_lng': 8.54,
        'wp_first_ele': 408.2,
        'wp_last_lat': 47.39,
        'wp_last_lng': 8.56,
        'wp_last_ele': 402.1,
        // shadow_hidden is trigger-owned, defaults false, and is NOT written
        // by saveRoute. The read half asserts the round-trip stays false.
        'shadow_hidden': false,
      };

      // Sanity-check the write from the Dart side before handing off to
      // Node, so a save that silently no-op'd fails here with a Dart-side
      // message rather than as an opaque Node assertion.
      final all = await api.getRoutes(limit: 200);
      final saved = all.where((r) => r.id == id).toList();
      expect(saved, hasLength(1),
          reason: 'saveRoute must persist a row visible via getRoutes');
      expect(saved.first.distanceMetres, 5123.5);
      expect(saved.first.surface, 'trail');
      expect(saved.first.waypoints, hasLength(3));
      expect(saved.first.waypoints.first.elevationMetres, 408.2);
      expect(saved.first.isPublic, isTrue);
      expect(saved.first.tags, const ['5k', 'loop', 'hill']);

      if (fixtureOut.isNotEmpty) {
        File(fixtureOut).writeAsStringSync(
            const JsonEncoder.withIndent('  ').convert(fixture));
      }
    });
  });
}
