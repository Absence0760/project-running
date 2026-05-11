import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import '../lib/local_route_store.dart';
import '../lib/routing.dart';
import '../lib/screens/route_builder_screen.dart';

/// Minimal in-memory path_provider stub. flutter_map_cache touches the
/// docs directory at startup; we let it create an ephemeral folder so
/// the widget mounts without exploding.
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

/// Stub OSRM fetcher — returns the same single-point snap for any
/// `/nearest/` request, and a polyline with the same two endpoints
/// (plus a midpoint) for any `/route/` request.
Future<String> _stubOsrm(Uri url) async {
  if (url.path.contains('/nearest/')) {
    // Echo whatever lng,lat came in as the "snapped" point.
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
  // /route/ — fabricate a polyline through the requested pairs.
  final segs = url.path.split('/');
  final pairs = segs.last.split(';');
  final coords = [
    for (final pair in pairs)
      [
        double.parse(pair.split(',')[0]),
        double.parse(pair.split(',')[1]),
      ],
  ];
  final dist = (pairs.length - 1) * 100.0; // 100 m per leg
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
          ),
        ),
      ),
    );
    // Two pumps — first to mount, second to drain post-frame callbacks
    // queued by flutter_map's onMapReady. pumpAndSettle would hang on
    // the tile fetch's retry timer.
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testWidgets('initial state — "Tap the map" hint, Save disabled',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.text('Tap the map to place waypoints'), findsOneWidget);
    // Save button disabled while we have <2 points.
    final save = find.widgetWithText(TextButton, 'Save');
    expect(save, findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNull);
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
    // 1 km @ equator ≈ 0.00899° longitude.
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
}

