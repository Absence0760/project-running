import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

/// Parity tests for [ApiClient.saveRoute] — the insert-body shape must
/// match `apps/web/src/lib/data.ts:saveRoute` so a route created on
/// either platform reads back identically. The helper
/// [ApiClient.buildSaveRouteBody] is a pure function; these tests
/// exercise it without standing up a Supabase fixture.
///
/// History: mobile + web diverged in three ways before this round:
///   1. Mobile stripped the client-generated `id` from the insert so
///      the server created a different one. The local
///      `LocalRouteStore` entry then pointed at `clientId` while the
///      server row had `serverId` — any later id-keyed operation
///      missed the server row.
///   2. Mobile didn't trim `description` or collapse empty-after-trim
///      to null, so whitespace-only descriptions survived to the DB.
///   3. Mobile silently dropped `club_id` even though `Route.clubId`
///      is exposed in the domain model. Mobile users couldn't create
///      club-owned routes through the API.
///
/// Each is pinned below so the next refactor that quietly reverts one
/// of these has a failing test to find.
void main() {
  const userId = 'user-abc-123';

  Route _route({
    String id = 'route-id-aaa',
    String? description,
    String? clubId,
    List<Waypoint>? waypoints,
  }) =>
      Route(
        id: id,
        name: 'Test loop',
        waypoints: waypoints ??
            const [
              Waypoint(lat: 51.5, lng: -0.1),
              Waypoint(lat: 51.51, lng: -0.11),
            ],
        distanceMetres: 5000,
        elevationGainMetres: 42,
        isPublic: true,
        surface: 'road',
        description: description,
        clubId: clubId,
      );

  group('buildSaveRouteBody — id handling (parity with saveRun)', () {
    test('client-generated route.id is preserved in the insert body', () {
      // Before this fix, the body was built then `id` was removed.
      // That left the local store pointing at a `clientId` that never
      // existed on the server. Now mirror `saveRun` — write the id
      // through.
      final body =
          ApiClient.buildSaveRouteBody(_route(id: 'client-uuid-1'), userId);
      expect(body['id'], 'client-uuid-1');
    });

    test('different ids round-trip independently — no static-field leak',
        () {
      // Sanity-check that the helper is stateless. If a future refactor
      // accidentally caches the body, this catches it.
      final a = ApiClient.buildSaveRouteBody(_route(id: 'a'), userId);
      final b = ApiClient.buildSaveRouteBody(_route(id: 'b'), userId);
      expect(a['id'], 'a');
      expect(b['id'], 'b');
    });
  });

  group('buildSaveRouteBody — description normalisation (parity with web)',
      () {
    // Web's saveRoute does `route.description?.trim() || null` — null
    // for both "absent" and "whitespace only". Mobile used to skip
    // both halves of that contract.

    test('null description stays null', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(description: null),
        userId,
      );
      expect(body.containsKey('description'), isFalse,
          reason: 'null fields are dropped before insert so '
              'Postgres uses the column default.');
    });

    test('empty-string description collapses to null', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(description: ''),
        userId,
      );
      expect(body.containsKey('description'), isFalse,
          reason: 'empty after trim → null → dropped from body');
    });

    test('whitespace-only description collapses to null', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(description: '   \t\n  '),
        userId,
      );
      expect(body.containsKey('description'), isFalse,
          reason: 'whitespace after trim → null → dropped from body');
    });

    test('non-empty description is trimmed but preserved', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(description: '  morning loop  '),
        userId,
      );
      expect(body['description'], 'morning loop');
    });

    test('internal whitespace is preserved (only edges trimmed)', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(description: '  one    two\nthree  '),
        userId,
      );
      expect(body['description'], 'one    two\nthree');
    });
  });

  group('buildSaveRouteBody — club_id pass-through (parity with web)', () {
    // Web supports `club_id`; mobile silently dropped it before this
    // fix, so mobile-created routes were always personal even when the
    // domain model carried a clubId.

    test('null clubId → field dropped from body (defaults to null on the row)',
        () {
      final body = ApiClient.buildSaveRouteBody(
        _route(clubId: null),
        userId,
      );
      expect(body.containsKey('club_id'), isFalse);
    });

    test('non-null clubId is written through', () {
      final body = ApiClient.buildSaveRouteBody(
        _route(clubId: 'club-xyz'),
        userId,
      );
      expect(body['club_id'], 'club-xyz');
    });
  });

  group('buildSaveRouteBody — core column set (parity with web)', () {
    // Pin the union of columns mobile writes so a future refactor that
    // drops one (e.g. `surface`, `elevation_m`) shows up as a parity
    // regression rather than silently affecting only one client.
    test('writes the full canonical column set', () {
      final body = ApiClient.buildSaveRouteBody(_route(), userId);
      expect(body['id'], isNotNull);
      expect(body['user_id'], userId);
      expect(body['name'], 'Test loop');
      expect(body['waypoints'], isA<List>());
      expect(body['distance_m'], 5000);
      expect(body['elevation_m'], 42);
      expect(body['is_public'], true);
      expect(body['surface'], 'road');
    });

    test('waypoints are emitted as {lat, lng, ele} objects', () {
      // Mobile preserves per-waypoint elevation (web doesn't, but the
      // `routes.waypoints` jsonb tolerates both shapes). Either way,
      // lat/lng must be present.
      final body = ApiClient.buildSaveRouteBody(
        _route(waypoints: [
          const Waypoint(lat: 1.0, lng: 2.0, elevationMetres: 50),
          const Waypoint(lat: 3.0, lng: 4.0),
        ]),
        userId,
      );
      final waypoints = body['waypoints'] as List;
      expect(waypoints.length, 2);
      expect(waypoints[0]['lat'], 1.0);
      expect(waypoints[0]['lng'], 2.0);
      expect(waypoints[0]['ele'], 50);
      expect(waypoints[1]['lat'], 3.0);
      expect(waypoints[1]['lng'], 4.0);
      expect(waypoints[1]['ele'], isNull);
    });

    test('user_id is the authenticated caller, not anything from the Route',
        () {
      // Belt-and-braces: even if a future refactor exposes `userId` on
      // the domain Route, the auth-supplied id is the only one that
      // matters for RLS.
      final body = ApiClient.buildSaveRouteBody(_route(), 'auth-user-id');
      expect(body['user_id'], 'auth-user-id');
    });
  });
}
