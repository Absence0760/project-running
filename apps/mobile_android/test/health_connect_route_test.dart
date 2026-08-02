import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/health_connect_importer.dart';

HcRoutePoint _p(double lat, double lng, int minute, {double? altitude}) => (
      lat: lat,
      lng: lng,
      at: DateTime.utc(2026, 6, 1, 8, minute),
      altitudeMetres: altitude,
    );

void main() {
  group('HealthConnectImporter.tracksFromRoutePoints (#664)', () {
    test('a session with a route imports its points as the track', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (
          uuid: 'session-a',
          points: [
            _p(51.5, -0.12, 0, altitude: 10),
            _p(51.51, -0.13, 1, altitude: 12),
            _p(51.52, -0.14, 2, altitude: 15),
          ],
        ),
      ]);

      expect(tracks.keys, ['session-a']);
      final track = tracks['session-a']!;
      expect(track.length, 3);
      expect(track.first.lat, 51.5);
      expect(track.first.lng, -0.12);
      expect(track.first.elevationMetres, 10);
      expect(track.first.timestamp, DateTime.utc(2026, 6, 1, 8, 0));
      expect(track.last.lat, 51.52);
    });

    test('altitude is optional — a route without it still imports', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'flat', points: [_p(1, 1, 0), _p(1.001, 1.001, 1)]),
      ]);
      expect(tracks['flat']!.length, 2);
      expect(tracks['flat']!.every((w) => w.elevationMetres == null), isTrue);
    });

    test('points are ordered by time, not by arrival order', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (
          uuid: 'shuffled',
          points: [_p(3, 3, 2), _p(1, 1, 0), _p(2, 2, 1)],
        ),
      ]);
      expect(
        tracks['shuffled']!.map((w) => w.lat).toList(),
        [1.0, 2.0, 3.0],
      );
    });

    // Health Connect answers ConsentRequired — the route exists but the
    // exercise-route permission isn't granted — as a route point with zero
    // locations. The session must be absent so its run imports trackless,
    // never with a track that claims to be the route.
    test('a withheld route (permission denied) yields no track at all', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'withheld', points: <HcRoutePoint>[]),
      ]);
      expect(tracks, isEmpty);
      expect(tracks['withheld'], isNull);
    });

    test('a session with no route point is simply absent from the map', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'has-route', points: [_p(1, 1, 0), _p(2, 2, 1)]),
      ]);
      // Negative control: the routed session IS present, so absence below is
      // about the missing route and not about the map being empty.
      expect(tracks['has-route'], isNotNull);
      expect(tracks['no-route'], isNull);
    });

    test('one location is a position, not a route — dropped', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'single', points: [_p(1, 1, 0)]),
      ]);
      expect(tracks, isEmpty);
    });

    test('non-finite and out-of-range fixes are screened out', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (
          uuid: 'noisy',
          points: [
            _p(51.5, -0.12, 0),
            _p(double.nan, -0.13, 1),
            _p(51.51, double.infinity, 2),
            _p(91, -0.14, 3),
            _p(51.52, 181, 4),
            _p(51.53, -0.15, 5),
          ],
        ),
      ]);
      // Negative control: exactly the two clean fixes survive, and the
      // garbage never reaches a Waypoint.
      expect(tracks['noisy']!.map((w) => w.lat).toList(), [51.5, 51.53]);
    });

    test('screening that leaves fewer than two fixes drops the session', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'mostly-junk', points: [_p(51.5, -0.12, 0), _p(91, 200, 1)]),
      ]);
      expect(tracks, isEmpty);
    });

    test('boundary coordinates are kept, not screened', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'edges', points: [_p(90, 180, 0), _p(-90, -180, 1)]),
      ]);
      expect(tracks['edges']!.length, 2);
    });

    test('sessions are keyed independently — routed and unrouted coexist', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 'a', points: [_p(1, 1, 0), _p(2, 2, 1)]),
        (uuid: 'b', points: <HcRoutePoint>[]),
        (uuid: 'c', points: [_p(5, 5, 0), _p(6, 6, 1), _p(7, 7, 2)]),
      ]);
      expect(tracks.keys.toSet(), {'a', 'c'});
      expect(tracks['a']!.length, 2);
      expect(tracks['c']!.length, 3);
    });

    test('no routes at all leaves every workout trackless', () {
      expect(HealthConnectImporter.tracksFromRoutePoints([]), isEmpty);
    });
  });

  // Losing this permission doesn't fail an import — it silently reverts
  // every Health Connect run to trackless, which is precisely the class of
  // regression that never shows up in a green test run.
  group('READ_EXERCISE_ROUTES stays declared (#664)', () {
    // The iOS twin carries this file byte-identically but has no android/
    // tree, matching how the existing health-permission guards behave.
    final manifest = File('android/app/src/main/AndroidManifest.xml');
    final permsXml =
        File('android/app/src/main/res/xml/health_permissions.xml');

    test('AndroidManifest declares the route read permission', () {
      if (!manifest.existsSync()) return;
      expect(
        manifest.readAsStringSync(),
        contains('android.permission.health.READ_EXERCISE_ROUTES'),
        reason:
            'Without the manifest uses-permission Health Connect withholds '
            'every route written by another app, and the import silently '
            'goes back to summary-only.',
      );
    });

    test('health_permissions.xml lists it for the Play Console form', () {
      if (!permsXml.existsSync()) return;
      expect(
        permsXml.readAsStringSync(),
        contains('android.permission.health.READ_EXERCISE_ROUTES'),
        reason:
            'Play Console validates the Health Connect data-access form '
            'against this file; a permission missing here is a review '
            'rejection, not a runtime bug.',
      );
    });
  });

  group('imported track feeds the run track contract', () {
    test('shaped points are Waypoints the save path can upload', () {
      final tracks = HealthConnectImporter.tracksFromRoutePoints([
        (uuid: 's', points: [_p(51.5, -0.12, 0), _p(51.51, -0.13, 1)]),
      ]);
      // api_client only uploads a track (and writes runs.track_url) when
      // run.track is non-empty and carries real fixes.
      expect(tracks['s'], isA<List<Waypoint>>());
      expect(tracks['s']!.every((w) => w.timestamp != null), isTrue);
    });
  });
}
