import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:test/test.dart';

void main() {
  group('debugWaypointToJson / debugWaypointFromJson', () {
    test('round-trip with all optional fields populated', () {
      const w = Waypoint(
        lat: 47.37,
        lng: 8.54,
        elevationMetres: 408.5,
        bpm: 142,
      );
      final json = ApiClient.debugWaypointToJson(w);

      expect(json['lat'], 47.37);
      expect(json['lng'], 8.54);
      expect(json['ele'], 408.5);
      expect(json['bpm'], 142);
      expect(json.containsKey('ts'), isTrue);
      expect(json['ts'], isNull);

      final back = ApiClient.debugWaypointFromJson(json);
      expect(back.lat, w.lat);
      expect(back.lng, w.lng);
      expect(back.elevationMetres, w.elevationMetres);
      expect(back.bpm, w.bpm);
      expect(back.timestamp, isNull);
    });

    test('round-trip with timestamp encodes UTC ISO 8601', () {
      final w = Waypoint(
        lat: 0,
        lng: 0,
        timestamp: DateTime.utc(2026, 4, 10, 8, 30, 15),
      );
      final json = ApiClient.debugWaypointToJson(w);

      expect(json['ts'], '2026-04-10T08:30:15.000Z');
      expect(ApiClient.debugWaypointFromJson(json).timestamp,
          DateTime.utc(2026, 4, 10, 8, 30, 15));
    });

    test('local-time timestamps are normalised to UTC on encode', () {
      final localNoon = DateTime(2026, 4, 10, 12);
      final json = ApiClient.debugWaypointToJson(
        Waypoint(lat: 0, lng: 0, timestamp: localNoon),
      );

      expect(json['ts'], localNoon.toUtc().toIso8601String());
    });

    test('omits the bpm key when bpm is null', () {
      const w = Waypoint(lat: 0, lng: 0);
      final json = ApiClient.debugWaypointToJson(w);
      expect(json.containsKey('bpm'), isFalse);
    });

    test('decodes integer-typed lat/lng into double', () {
      final json = <String, dynamic>{'lat': 0, 'lng': 0};
      final w = ApiClient.debugWaypointFromJson(json);
      expect(w.lat, 0.0);
      expect(w.lng, 0.0);
      expect(w.lat, isA<double>());
    });

    test('decodes elevation null vs absent the same (both → null)', () {
      final w1 = ApiClient.debugWaypointFromJson({'lat': 0, 'lng': 0});
      final w2 = ApiClient.debugWaypointFromJson(
          {'lat': 0, 'lng': 0, 'ele': null});
      expect(w1.elevationMetres, isNull);
      expect(w2.elevationMetres, isNull);
    });

    test('rejects malformed timestamp gracefully (DateTime.tryParse)', () {
      final w = ApiClient.debugWaypointFromJson(
          {'lat': 0, 'lng': 0, 'ts': 'not-a-date'});
      expect(w.timestamp, isNull);
    });
  });

  group('debugRunFromRow', () {
    Map<String, dynamic> minimalRow({
      String id = 'run-1',
      String userId = 'user-1',
      DateTime? startedAt,
      int durationS = 1500,
      double distanceM = 5000,
      String source = 'app',
      String activityType = 'run',
      bool isDnf = false,
      Map<String, dynamic>? metadata,
      String? trackUrl,
      String? externalId,
      DateTime? createdAt,
      String? routeId,
    }) {
      return <String, dynamic>{
        'id': id,
        'user_id': userId,
        'activity_type': activityType,
        'is_dnf': isDnf,
        'started_at': (startedAt ?? DateTime.utc(2026, 4, 10, 8))
            .toIso8601String(),
        'duration_s': durationS,
        'distance_m': distanceM,
        'route_id': routeId,
        'source': source,
        'external_id': externalId,
        'metadata': metadata,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': null,
        'track_url': trackUrl,
        'is_public': null,
        'event_id': null,
        'tags': null,
      };
    }

    test('basic row maps fields onto the Run domain class', () {
      final run = ApiClient.debugRunFromRow(minimalRow());
      expect(run.id, 'run-1');
      expect(run.startedAt, DateTime.utc(2026, 4, 10, 8));
      expect(run.duration, const Duration(seconds: 1500));
      expect(run.distanceMetres, 5000);
      expect(run.source, RunSource.app);
      expect(run.track, isEmpty);
    });

    test('track_url is stashed onto metadata for lazy-fetch by callers', () {
      final run = ApiClient.debugRunFromRow(
        minimalRow(trackUrl: 'user-1/run-1.json.gz'),
      );
      expect(run.metadata?['track_url'], 'user-1/run-1.json.gz');
    });

    test('activity_type + is_dnf columns are surfaced onto metadata', () {
      final run = ApiClient.debugRunFromRow(
        minimalRow(activityType: 'cycle', isDnf: true),
      );
      expect(run.metadata?['activity_type'], 'cycle');
      expect(run.metadata?['is_dnf'], true);
    });

    test('existing metadata keys survive alongside the stashed columns', () {
      final run = ApiClient.debugRunFromRow(minimalRow(
        activityType: 'cycle',
        metadata: {'avg_bpm': 142},
        trackUrl: 'u/r.json.gz',
      ));
      expect(run.metadata?['activity_type'], 'cycle');
      expect(run.metadata?['avg_bpm'], 142);
      expect(run.metadata?['track_url'], 'u/r.json.gz');
    });

    test('every RunSource value parses correctly', () {
      for (final s in RunSource.values) {
        final run =
            ApiClient.debugRunFromRow(minimalRow(source: s.name));
        expect(run.source, s, reason: 'failed for ${s.name}');
      }
    });

    test('unknown source falls back to RunSource.app', () {
      final run =
          ApiClient.debugRunFromRow(minimalRow(source: 'made-up-source'));
      expect(run.source, RunSource.app);
    });

    test('externalId passes through unchanged', () {
      final run = ApiClient.debugRunFromRow(
          minimalRow(externalId: 'strava:1234567890'));
      expect(run.externalId, 'strava:1234567890');
    });

    test('createdAt passes through when present', () {
      final created = DateTime.utc(2026, 4, 10, 8, 30);
      final run = ApiClient.debugRunFromRow(minimalRow(createdAt: created));
      expect(run.createdAt, created);
    });

    test('route_id is parsed onto Run.routeId so linkRunToRoute survives sync',
        () {
      // Regression: _runFromRow used to drop route_id entirely, so the
      // newer-wins merge wiped a run's route link to null on the next
      // normal sync after linkRunToRoute(). The read must carry it.
      final run = ApiClient.debugRunFromRow(minimalRow(routeId: 'route-9'));
      expect(run.routeId, 'route-9');
    });

    test('null route_id decodes to a null routeId', () {
      final run = ApiClient.debugRunFromRow(minimalRow());
      expect(run.routeId, isNull);
    });
  });

  group('metadataWithoutPromotedColumns (saveRun write-side strip)', () {
    test('strips activity_type + is_dnf from the persisted bag', () {
      final out = ApiClient.debugMetadataWithoutPromotedColumns({
        'activity_type': 'cycle',
        'is_dnf': true,
        'avg_bpm': 142,
      });
      expect(out, {'avg_bpm': 142});
    });

    test('collapses to null when only the promoted keys were present', () {
      final out = ApiClient.debugMetadataWithoutPromotedColumns({
        'activity_type': 'run',
        'is_dnf': false,
      });
      expect(out, isNull);
    });

    test('null in → null out', () {
      expect(ApiClient.debugMetadataWithoutPromotedColumns(null), isNull);
    });

    test('does not mutate the caller argument', () {
      final input = {'activity_type': 'walk', 'steps': 9000};
      ApiClient.debugMetadataWithoutPromotedColumns(input);
      expect(input['activity_type'], 'walk');
      expect(input['steps'], 9000);
    });
  });

  group('debugRouteFromRow', () {
    Map<String, dynamic> minimalRouteRow({
      String id = 'route-1',
      String userId = 'user-1',
      String name = 'Test loop',
      List<Map<String, dynamic>> waypoints = const [
        {'lat': 0, 'lng': 0},
        {'lat': 0, 'lng': 0.001},
      ],
      double distanceM = 111.195,
      double? elevationM,
      bool? isPublic,
      String? surface,
      List<String>? tags,
      bool featured = false,
      bool isStarred = false,
      int runCount = 0,
    }) {
      return <String, dynamic>{
        'id': id,
        'user_id': userId,
        'name': name,
        'waypoints': waypoints,
        'distance_m': distanceM,
        'elevation_m': elevationM,
        'surface': surface,
        'is_public': isPublic,
        'slug': null,
        'created_at': null,
        'updated_at': null,
        'start_point': null,
        'tags': tags ?? const <String>[],
        'is_featured': featured,
        'featured_at': null,
        'run_count': runCount,
        'club_id': null,
        'is_starred': isStarred,
        'geom': null,
      };
    }

    test('basic row maps fields onto the Route domain class', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow());
      expect(route.id, 'route-1');
      expect(route.name, 'Test loop');
      expect(route.waypoints, hasLength(2));
      expect(route.waypoints.first.lat, 0);
      expect(route.waypoints.first.lng, 0);
      expect(route.distanceMetres, closeTo(111.195, 0.001));
      expect(route.isPublic, isFalse);
      expect(route.featured, isFalse);
      expect(route.isStarred, isFalse);
      expect(route.runCount, 0);
    });

    test('null elevation_m collapses to 0 (not null) on the domain class', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow());
      expect(route.elevationGainMetres, 0);
    });

    test('elevation_m is preserved when present', () {
      final route =
          ApiClient.debugRouteFromRow(minimalRouteRow(elevationM: 145.5));
      expect(route.elevationGainMetres, 145.5);
    });

    test('null is_public is treated as false', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow());
      expect(route.isPublic, isFalse);
    });

    test('explicit is_public=true round-trips', () {
      final route =
          ApiClient.debugRouteFromRow(minimalRouteRow(isPublic: true));
      expect(route.isPublic, isTrue);
    });

    test('tags pass through verbatim', () {
      final route = ApiClient.debugRouteFromRow(
          minimalRouteRow(tags: ['5k', 'parkrun_course', 'hilly']));
      expect(route.tags, ['5k', 'parkrun_course', 'hilly']);
    });

    test('featured + run_count + is_starred populate as expected', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow(
        featured: true,
        runCount: 42,
        isStarred: true,
      ));
      expect(route.featured, isTrue);
      expect(route.runCount, 42);
      expect(route.isStarred, isTrue);
    });

    test('waypoint elevation passes through when present', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow(waypoints: [
        {'lat': 0, 'lng': 0, 'ele': 100},
        {'lat': 0, 'lng': 0.001, 'ele': 110},
      ]));
      expect(route.waypoints[0].elevationMetres, 100);
      expect(route.waypoints[1].elevationMetres, 110);
    });

    test('waypoint without elevation produces null on the domain object', () {
      final route = ApiClient.debugRouteFromRow(minimalRouteRow());
      expect(route.waypoints.first.elevationMetres, isNull);
    });
  });
}
