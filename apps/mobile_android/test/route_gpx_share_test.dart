import 'package:core_models/core_models.dart' as cm;
import 'package:flutter_test/flutter_test.dart';
import '../lib/screens/route_detail_screen.dart';

cm.RouteMarkerRow _marker({
  required String id,
  required String kind,
  required String label,
  required double lat,
  required double lng,
  dynamic meta,
}) {
  final now = DateTime.utc(2026, 1, 1);
  return cm.RouteMarkerRow(
    id: id,
    routeId: 'route-1',
    userId: 'user-1',
    kind: kind,
    label: label,
    lat: lat,
    lng: lng,
    meta: meta ?? <String, dynamic>{},
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('routeGpxFromRoute', () {
    final route = cm.Route(
      id: 'route-1',
      userId: 'user-1',
      name: 'Canyon Loop',
      waypoints: const [
        cm.Waypoint(lat: 39.0, lng: -120.0, elevationMetres: 1800),
        cm.Waypoint(lat: 39.01, lng: -120.01, elevationMetres: 1850),
      ],
      distanceMetres: 1500,
      elevationGainMetres: 50,
      isPublic: true,
      createdAt: DateTime.utc(2026, 1, 1),
    );

    test('emits the route line as trackpoints', () {
      final gpx = routeGpxFromRoute(route, const []);
      expect(gpx, contains('<trkpt lat="39.0" lon="-120.0">'));
      expect('<trkpt'.allMatches(gpx).length, 2);
      // No markers → no waypoints.
      expect(gpx.contains('<wpt'), isFalse);
    });

    test('emits one wpt per marker with labels and cutoff desc', () {
      final markers = [
        _marker(
          id: 'm1',
          kind: 'aid_station',
          label: 'Aid 2',
          lat: 39.005,
          lng: -120.005,
          meta: <String, dynamic>{
            'cutoff_clock': '14:30',
            'services': ['water', 'food'],
          },
        ),
        _marker(
          id: 'm2',
          kind: 'cutoff',
          label: 'Cutoff A',
          lat: 39.008,
          lng: -120.008,
          meta: <String, dynamic>{'cutoff_elapsed_s': 7200},
        ),
      ];

      final gpx = routeGpxFromRoute(route, markers);

      // One wpt per marker.
      expect('<wpt'.allMatches(gpx).length, 2);
      // Marker labels surface as <name>.
      expect(gpx, contains('<name>Aid 2</name>'));
      expect(gpx, contains('<name>Cutoff A</name>'));
      // Cutoff + services land in <desc>.
      expect(gpx, contains('Cutoff 14:30'));
      expect(gpx, contains('Services: water, food'));
      expect(gpx, contains('Cutoff 2h00m elapsed'));
      // Still contains the line.
      expect(gpx, contains('<trkpt'));
      // GPX 1.1 order: waypoints before the track.
      expect(gpx.indexOf('<wpt'), lessThan(gpx.indexOf('<trk>')));
    });

    test('tolerates a non-map meta', () {
      final markers = [
        _marker(
          id: 'm3',
          kind: 'note',
          label: 'Trailhead',
          lat: 39.0,
          lng: -120.0,
          meta: 'not-a-map',
        ),
      ];
      final gpx = routeGpxFromRoute(route, markers);
      expect(gpx, contains('<name>Trailhead</name>'));
      expect('<wpt'.allMatches(gpx).length, 1);
    });
  });
}
