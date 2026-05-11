import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/local_route_store.dart';
import '../lib/route_overlap.dart';
import '../lib/routing.dart';
import '../lib/screens/route_builder_screen.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory _tmp;
  _FakePathProvider(this._tmp);
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp.path;
  @override
  Future<String?> getApplicationSupportPath() async => _tmp.path;
  @override
  Future<String?> getTemporaryPath() async => _tmp.path;
}

Future<String> _stubOsrm(Uri url) async {
  if (url.path.contains('/nearest/')) {
    final segs = url.path.split('/');
    final coord = segs.last.split(',');
    final lng = double.parse(coord[0]);
    final lat = double.parse(coord[1]);
    return jsonEncode({
      'code': 'Ok',
      'waypoints': [
        {'location': [lng, lat]},
      ],
    });
  }
  final segs = url.path.split('/');
  final pairs = segs.last.split(';');
  final coords = [
    for (final pair in pairs)
      [
        double.parse(pair.split(',')[0]),
        double.parse(pair.split(',')[1]),
      ],
  ];
  final dist = (pairs.length - 1) * 100.0;
  return jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': dist,
        'geometry': {'coordinates': coords},
      },
    ],
  });
}

Future<String> _stubElev(Uri url) async {
  // open-meteo response with one entry per lat point.
  final lats = (url.queryParameters['latitude'] ?? '').split(',');
  return jsonEncode({
    'elevation': [for (final _ in lats) 400.0],
  });
}

Future<String> _stubGeocoding(Uri url) async {
  // Return a single canned result.
  return jsonEncode({
    'features': [
      {
        'place_name': 'London, United Kingdom',
        'center': [-0.1278, 51.5074],
      },
    ],
  });
}

Future<Position> _stubLocate() async {
  return Position(
    latitude: 51.5074,
    longitude: -0.1278,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late Directory tmpDir;

  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('rb_screen_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
  });

  tearDown(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<LocalRouteStore> _store() async {
    final s = LocalRouteStore();
    await s.init(overrideDirectory: Directory(p.join(tmpDir.path, 'routes')));
    return s;
  }

  Future<void> _pumpScreen(WidgetTester tester, LocalRouteStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: RouteBuilderScreen(
            apiClient: ApiClient(),
            routeStore: store,
            osrmFetcher: _stubOsrm,
            elevationFetcher: _stubElev,
            geocodingFetcher: _stubGeocoding,
            locateFn: _stubLocate,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testWidgets('initial state — "Tap the map" hint, Save disabled',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.text('Tap the map to place waypoints'), findsOneWidget);
    final save = find.widgetWithText(TextButton, 'Save');
    expect(save, findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNull);
  });

  testWidgets('AppBar hosts the place-search field + locate FAB',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search places…'), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('mode toggle has Trail / Road / Straight segments',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.text('Trail'), findsOneWidget);
    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Straight'), findsOneWidget);
  });

  test('straightLineDistance sums haversine legs', () {
    final pts = [
      const cm.Waypoint(lat: 0, lng: 0),
      const cm.Waypoint(lat: 0, lng: 0.00899),
      const cm.Waypoint(lat: 0, lng: 0.01798),
    ];
    final d = straightLineDistance(pts);
    expect(d, closeTo(2000, 5),
        reason: 'two consecutive ~1 km legs should sum to ~2 km');
  });

  test('straightLineDistance is zero for <2 points', () {
    expect(straightLineDistance(const []), 0);
    expect(
      straightLineDistance(const [cm.Waypoint(lat: 0, lng: 0)]),
      0,
    );
  });

  group('overlapLatLngsFor', () {
    test('empty list for empty spans', () {
      expect(
        overlapLatLngsFor(const [], const []),
        isEmpty,
      );
    });

    test('slices the polyline by span indices, skipping <2-point spans',
        () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
        const cm.Waypoint(lat: 0.002, lng: 0),
        const cm.Waypoint(lat: 0.003, lng: 0),
        const cm.Waypoint(lat: 0.004, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 1, endIndex: 3),
        const OverlapSpan(startIndex: 4, endIndex: 4), // single-point, skipped
      ];
      final slices = overlapLatLngsFor(polyline, spans);
      expect(slices, hasLength(1));
      expect(slices.first, hasLength(3));
      expect(slices.first.first.latitude, closeTo(0.001, 1e-9));
      expect(slices.first.last.latitude, closeTo(0.003, 1e-9));
    });

    test('clamps endIndex when it overflows the polyline', () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 0, endIndex: 99),
      ];
      final slices = overlapLatLngsFor(polyline, spans);
      expect(slices.first, hasLength(2));
    });

    test('skips spans whose startIndex is out of range', () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 5, endIndex: 6),
      ];
      expect(overlapLatLngsFor(polyline, spans), isEmpty);
    });
  });
}
