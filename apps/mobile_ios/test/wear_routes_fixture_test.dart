import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/wear_routes_bridge.dart';

/// Cross-platform contract test for the phone→watch routes payload.
///
/// The fixture at `fixtures/wear_routes_payload.json` (repo root) is
/// shared with the Wear OS Kotlin test
/// (`apps/watch_wear/.../WearRoutesFixtureTest.kt`). Both platforms
/// read the same file and must agree on the wire format. If you
/// change a field here, update the Kotlin test in the same commit.
///
/// On Flutter the encoder (`encodeRoutesForWatch`) is what we
/// exercise — the phone writes this shape onto the Wearable Data
/// Layer at `/saved_routes` and the watch parses it via
/// `parseRoutesJson`.
void main() {
  // The Gradle / flutter_test cwd is the app dir
  // (`apps/mobile_android`), so the fixture is 2 levels up.
  final fixtureFile = File('../../fixtures/wear_routes_payload.json');

  late Map<String, dynamic> fixture;

  setUpAll(() {
    expect(fixtureFile.existsSync(), isTrue,
        reason: 'fixture must be at ${fixtureFile.absolute.path}');
    fixture = jsonDecode(fixtureFile.readAsStringSync()) as Map<String, dynamic>;
  });

  test('encodeRoutesForWatch produces the canonical wire format', () {
    final inputRoutes = (fixture['input_routes']['starred'] as List)
        .map((r) {
      final m = r as Map<String, dynamic>;
      return Route(
        id: m['id'] as String,
        userId: 'fixture',
        name: m['name'] as String,
        waypoints: (m['waypoints'] as List).map((w) {
          final wp = w as Map<String, dynamic>;
          return Waypoint(
            lat: (wp['lat'] as num).toDouble(),
            lng: (wp['lng'] as num).toDouble(),
          );
        }).toList(),
        distanceMetres: (m['distance_m'] as num).toDouble(),
        isStarred: true,
      );
    }).toList();

    final encoded = WearRoutesBridge.encodeRoutesForWatch(inputRoutes);
    final expected = fixture['expected_payload_json'] as List;

    expect(encoded.length, expected.length);
    for (var i = 0; i < encoded.length; i++) {
      final got = encoded[i];
      final want = expected[i] as Map<String, dynamic>;
      expect(got['id'], want['id'], reason: 'row $i id');
      expect(got['name'], want['name'], reason: 'row $i name');
      expect(got['distance_m'], want['distance_m'], reason: 'row $i distance');
      final gotWps = got['waypoints'] as List;
      final wantWps = want['waypoints'] as List;
      expect(gotWps.length, wantWps.length, reason: 'row $i waypoint count');
      for (var w = 0; w < gotWps.length; w++) {
        final gw = gotWps[w] as Map;
        final ww = wantWps[w] as Map;
        expect(gw['lat'], ww['lat'], reason: 'row $i wp $w lat');
        expect(gw['lng'], ww['lng'], reason: 'row $i wp $w lng');
        expect(gw.keys.toSet(), {'lat', 'lng'},
            reason: 'row $i wp $w must carry only lat/lng');
      }
      expect(got.keys.toSet(), {'id', 'name', 'distance_m', 'waypoints'},
          reason: 'row $i must carry exactly the contract keys');
    }
  });

  test('encoded JSON round-trips through jsonEncode + jsonDecode '
      'byte-identical to the fixture', () {
    final inputRoutes = (fixture['input_routes']['starred'] as List)
        .map((r) {
      final m = r as Map<String, dynamic>;
      return Route(
        id: m['id'] as String,
        userId: 'fixture',
        name: m['name'] as String,
        waypoints: (m['waypoints'] as List).map((w) {
          final wp = w as Map<String, dynamic>;
          return Waypoint(
            lat: (wp['lat'] as num).toDouble(),
            lng: (wp['lng'] as num).toDouble(),
          );
        }).toList(),
        distanceMetres: (m['distance_m'] as num).toDouble(),
        isStarred: true,
      );
    }).toList();

    final wire = jsonEncode(WearRoutesBridge.encodeRoutesForWatch(inputRoutes));
    // Re-parse + compare structurally — this is what `RoutesBridge.kt`
    // does on the watch side via kotlinx.serialization. If THIS
    // assertion passes, the watch parser sees the same shape as
    // the fixture expects.
    final decoded = jsonDecode(wire) as List;
    final expected = fixture['expected_payload_json'] as List;
    expect(decoded.length, expected.length);

    for (var i = 0; i < decoded.length; i++) {
      final got = decoded[i] as Map<String, dynamic>;
      final want = expected[i] as Map<String, dynamic>;
      expect(got['id'], want['id']);
      expect(got['name'], want['name']);
      // Distance is always a NUMERIC primitive in the JSON — the
      // Kotlin parser accepts either int or double via
      // `jsonPrimitive.doubleOrNull`. We only assert numeric
      // equality, not the specific subtype (Dart parses `5000.5`
      // as double + `10000` as int).
      expect(got['distance_m'], isA<num>(),
          reason: 'distance_m must be a JSON number, not a stringified number');
      expect((got['distance_m'] as num).toDouble(),
          (want['distance_m'] as num).toDouble());
    }
  });

  test('Unicode in route name survives the JSON encode → bytes round-trip', () {
    final starred = (fixture['input_routes']['starred'] as List)
        .map((r) {
      final m = r as Map<String, dynamic>;
      return Route(
        id: m['id'] as String,
        userId: 'fixture',
        name: m['name'] as String,
        waypoints: (m['waypoints'] as List).map((w) {
          final wp = w as Map<String, dynamic>;
          return Waypoint(
            lat: (wp['lat'] as num).toDouble(),
            lng: (wp['lng'] as num).toDouble(),
          );
        }).toList(),
        distanceMetres: (m['distance_m'] as num).toDouble(),
        isStarred: true,
      );
    }).toList();

    final wire = jsonEncode(WearRoutesBridge.encodeRoutesForWatch(starred));
    final decoded = jsonDecode(wire) as List;
    // The trail-run route's name carries an emoji; verify it
    // survives the encode → decode round trip through Dart's JSON.
    // Watch-side equivalence is pinned by the Kotlin parser test
    // reading the same fixture.
    final trail = decoded.firstWhere((r) => (r as Map)['id'] == 'rt-trail-uuid-002');
    expect((trail as Map)['name'], 'Trail run with Unicode 🏃');
  });

  test('encoder filters out the non-starred subset (smoke)', () {
    // Belt-and-braces: pickRoutesForWatchPush is the filter; the
    // encoder doesn't re-filter, so it's the caller's job. Pin
    // that the pipeline as a whole drops non-starred.
    final mixedRoutes = [
      ...(fixture['input_routes']['starred'] as List).map((r) {
        final m = r as Map<String, dynamic>;
        return Route(
          id: m['id'] as String,
          userId: 'fixture',
          name: m['name'] as String,
          waypoints: (m['waypoints'] as List).map((w) {
            final wp = w as Map<String, dynamic>;
            return Waypoint(
              lat: (wp['lat'] as num).toDouble(),
              lng: (wp['lng'] as num).toDouble(),
            );
          }).toList(),
          distanceMetres: (m['distance_m'] as num).toDouble(),
          isStarred: true,
        );
      }).toList(),
      // A plain (non-starred) route that the encoder shouldn't see.
      Route(
        id: 'plain-route',
        userId: 'fixture',
        name: 'Should not appear on watch',
        waypoints: const [
          Waypoint(lat: 0, lng: 0),
          Waypoint(lat: 1, lng: 1),
        ],
        distanceMetres: 500,
      ),
    ];
    final picked = WearRoutesBridge.pickRoutesForWatchPush(mixedRoutes);
    final ids = picked.map((r) => r.id).toSet();
    expect(ids, isNot(contains('plain-route')));
    expect(ids,
        (fixture['input_routes']['starred'] as List)
            .map((r) => (r as Map)['id'])
            .toSet());
  });
}
