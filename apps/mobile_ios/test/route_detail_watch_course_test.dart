import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';
import '../lib/sim_watch_sync.dart' show WatchBleTransport;
import '../lib/watch_course.dart' show kMaxCoursePoints;

const _localBackend = 'http://127.0.0.1:54321';
const _prodBackend = 'https://abcdefgh.supabase.co';

/// Course-only transport: the push writes chunks, nothing else is exercised.
class _FakeCourseTransport implements WatchBleTransport {
  final courseWrites = <List<int>>[];
  final roadbookWrites = <List<int>>[];
  final bool failWrite;
  int scans = 0;
  int disconnects = 0;

  _FakeCourseTransport({this.failWrite = false});

  @override
  Future<void> scan() async => scans++;
  @override
  Future<void> disconnect() async => disconnects++;
  @override
  Stream<List<int>> get chunkStream => const Stream<List<int>>.empty();
  @override
  Future<List<int>> readManifest() async => const [];
  @override
  Future<void> writeChunkRequest(List<int> request) async {}
  @override
  Future<void> writeSettings(List<int> frame) async {}
  @override
  Future<void> writeWorkout(List<int> chunk) async {}
  @override
  Future<void> writeScreens(List<int> frame) async {}

  @override
  Future<void> writeCourse(List<int> chunk) async {
    if (failWrite) throw StateError('radio gone');
    courseWrites.add(chunk);
  }

  @override
  Future<void> writeRoadbook(List<int> chunk) async {
    if (failWrite) throw StateError('radio gone');
    roadbookWrites.add(chunk);
  }

  /// Rebuild the CRS1 frame from the offset-tagged chunks the screen wrote.
  Uint8List get frame {
    var length = 0;
    for (final c in courseWrites) {
      final off = ByteData.sublistView(Uint8List.fromList(c))
          .getUint16(0, Endian.little);
      length = math.max(length, off + c.length - 2);
    }
    final out = Uint8List(length);
    for (final c in courseWrites) {
      final off = ByteData.sublistView(Uint8List.fromList(c))
          .getUint16(0, Endian.little);
      out.setRange(off, off + c.length - 2, c.sublist(2));
    }
    return out;
  }

  int get pointCount =>
      ByteData.sublistView(frame).getUint16(5, Endian.little);

  /// Rebuild the RBK1 frame from the offset-tagged roadbook chunks.
  Uint8List get roadbookFrame => _reassemble(roadbookWrites);

  int get checkpointCount => roadbookFrame[5];
  int get cutoffCount => roadbookFrame[6];

  static Uint8List _reassemble(List<List<int>> writes) {
    var length = 0;
    for (final c in writes) {
      final off = ByteData.sublistView(Uint8List.fromList(c))
          .getUint16(0, Endian.little);
      length = math.max(length, off + c.length - 2);
    }
    final out = Uint8List(length);
    for (final c in writes) {
      final off = ByteData.sublistView(Uint8List.fromList(c))
          .getUint16(0, Endian.little);
      out.setRange(off, off + c.length - 2, c.sublist(2));
    }
    return out;
  }

  ({double lat, double lng}) pointAt(int i) {
    final view = ByteData.sublistView(frame);
    return (
      lat: view.getInt32(8 + i * 8, Endian.little) / 1e7,
      lng: view.getInt32(8 + i * 8 + 4, Endian.little) / 1e7,
    );
  }
}

/// Owner viewer that serves a canned course-marker set, so the roadbook half of
/// the push has something to schedule. [failMarkers] models the offline / RLS
/// case the push must degrade through rather than sink on.
class _MarkersApi extends ApiClient {
  final List<cm.RouteMarkerRow> markers;
  final bool failMarkers;
  int fetchCount = 0;
  _MarkersApi(this.markers, {this.failMarkers = false});

  @override
  String? get userId => 'owner-uuid';

  @override
  Future<List<cm.RouteMarkerRow>> fetchRouteMarkers(String routeId) async {
    fetchCount++;
    if (failMarkers) throw StateError('rls said no');
    return markers;
  }
}

cm.RouteMarkerRow _marker(
  String id, {
  required double positionM,
  String kind = 'aid_station',
  int? cutoffElapsedS,
  String? cutoffClock,
}) =>
    cm.RouteMarkerRow(
      id: id,
      routeId: 'r1',
      userId: 'owner-uuid',
      kind: kind,
      label: 'stop $id',
      lat: 40,
      lng: -105,
      positionM: positionM,
      meta: {
        if (cutoffElapsedS != null) 'cutoff_elapsed_s': cutoffElapsedS,
        if (cutoffClock != null) 'cutoff_clock': cutoffClock,
        if (kind == 'aid_station') 'services': const ['water'],
      },
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

/// Non-owner viewer whose clip RPC returns a privacy-clipped subset.
class _ClippingApi extends ApiClient {
  final List<cm.Waypoint> clipped;
  _ClippingApi(this.clipped);

  @override
  String? get userId => 'viewer-uuid';

  @override
  Future<List<cm.Waypoint>> clipRouteForViewer(String routeId) async => clipped;
}

cm.Route _route({
  required List<cm.Waypoint> waypoints,
  String userId = '',
}) =>
    cm.Route(
      id: 'r1',
      userId: userId,
      name: 'Generated Loop',
      waypoints: waypoints,
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: false,
    );

List<cm.Waypoint> _loop(int n, {bool withElevation = false}) => [
      for (var i = 0; i < n; i++)
        cm.Waypoint(
          lat: 40.0 + math.sin(i / 8) * 0.004,
          lng: -105.0 + math.cos(i / 8) * 0.004,
          elevationMetres: withElevation ? 1600 + i.toDouble() : null,
        ),
    ];

/// A west-to-east line of [km] legs of ~1 km each at 40°N, so a course-marker
/// position in whole kilometres lands where the test means it to. `_loop` is a
/// ~450 m circle, short enough that every schedule marker would clamp onto the
/// finish and collapse.
List<cm.Waypoint> _longLine(int km) {
  const metresPerDegLng = 111320 * 0.766;
  return [
    for (var i = 0; i <= km; i++)
      cm.Waypoint(
        lat: 40,
        lng: -105 + i * 1000 / metresPerDegLng,
        elevationMetres: 1600 + i * 3.0,
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester,
  cm.Route route, {
  required _FakeCourseTransport transport,
  String backendUrl = _localBackend,
  ApiClient? api,
  bool? isOwner,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteDetailScreen(
        route: route,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        apiClient: api,
        isOwner: isOwner ?? api == null,
        devBackendUrl: backendUrl,
        watchTransportFactory: () => transport,
      ),
    ),
  );
  // One pump to build; pumpAndSettle would spin LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

Future<void> _openShareMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.ios_share));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _sendToWatch(WidgetTester tester) async {
  await tester.tap(find.text('Send to watch'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// `showTopBanner` arms a dismissal timer; leaving it pending trips the
/// test binding's "a Timer is still pending" invariant. Call after asserting
/// on the banner text.
Future<void> _drainBanner(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 6));
  await tester.pump();
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('RouteDetailScreen — send the course to the watch', () {
    testWidgets('the action is offered against a loopback backend',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(tester, _route(waypoints: _loop(20)), transport: transport);
      await _openShareMenu(tester);
      expect(find.text('Send to watch'), findsOneWidget);
      // The product export targets are still there beside it.
      expect(find.text('Share as GPX'), findsOneWidget);
    });

    testWidgets('the action is absent against a production backend',
        (tester) async {
      // The custom watch is research-tier with no unit in a runner's hands —
      // offering the push to every user would promise hardware that does not
      // exist (decisions §71).
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _loop(20)),
        transport: transport,
        backendUrl: _prodBackend,
      );
      await _openShareMenu(tester);
      expect(find.text('Send to watch'), findsNothing);
      expect(find.text('Share as GPX'), findsOneWidget);
    });

    testWidgets('a short route pushes every point and says so', (tester) async {
      final transport = _FakeCourseTransport();
      final waypoints = _loop(20);
      await _pump(tester, _route(waypoints: waypoints), transport: transport);
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.courseWrites, isNotEmpty);
      expect(transport.pointCount, 20);
      expect(transport.pointAt(0).lat, closeTo(waypoints.first.lat, 1e-6));
      expect(transport.pointAt(19).lng, closeTo(waypoints.last.lng, 1e-6));
      expect(transport.scans, 1);
      expect(transport.disconnects, 1);
      expect(find.textContaining('Course sent to the watch'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a route past the frame capacity is thinned, not cut',
        (tester) async {
      final transport = _FakeCourseTransport();
      final waypoints = _loop(1500, withElevation: true);
      await _pump(tester, _route(waypoints: waypoints), transport: transport);
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.pointCount, kMaxCoursePoints);
      // The last position on the wire is the route's real end — a course cut at
      // the cap would strand the breadcrumb mid-route.
      expect(
        transport.pointAt(kMaxCoursePoints - 1).lng,
        closeTo(waypoints.last.lng, 1e-6),
      );
      expect(find.textContaining('thinned from 1500 points to 256'),
          findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a route with one position is refused, and nothing is written',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(tester, _route(waypoints: _loop(1)), transport: transport);
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.courseWrites, isEmpty);
      expect(transport.scans, 0);
      expect(find.textContaining('too few points'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a failed write surfaces the failure rather than a success',
        (tester) async {
      final transport = _FakeCourseTransport(failWrite: true);
      await _pump(tester, _route(waypoints: _loop(20)), transport: transport);
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(find.textContaining("Couldn't send the course"), findsOneWidget);
      expect(find.textContaining('Course sent to the watch'), findsNothing);
      // The connection is still torn down on the failure path.
      expect(transport.disconnects, 1);
      await _drainBanner(tester);
    });

    testWidgets('a non-owner sends the clipped trace, not the stored one',
        (tester) async {
      // Same invariant the GPX exporter honours (decisions §33) — the radio is
      // just another way out of the app.
      final transport = _FakeCourseTransport();
      final stored = _loop(40);
      final clipped = stored.sublist(10, 30);
      await _pump(
        tester,
        _route(waypoints: stored, userId: 'owner-uuid'),
        transport: transport,
        api: _ClippingApi(clipped),
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.pointCount, clipped.length);
      expect(transport.pointAt(0).lat, closeTo(clipped.first.lat, 1e-6));
      expect(
        transport.pointAt(clipped.length - 1).lng,
        closeTo(clipped.last.lng, 1e-6),
      );
      await _drainBanner(tester);
    });
  });

  group('RouteDetailScreen — the race schedule rides the course push', () {
    testWidgets('markers become an RBK1 schedule on the same action',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          _marker('a', positionM: 2000),
          _marker('b', positionM: 5000, kind: 'cutoff', cutoffElapsedS: 3600),
          _marker('c', positionM: 7000),
        ]),
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.courseWrites, isNotEmpty,
          reason: 'the schedule is useless without the course it indexes into');
      expect(transport.roadbookWrites, isNotEmpty);
      // Three markers plus the finish; the synthetic start is dropped.
      expect(transport.checkpointCount, 4);
      expect(transport.cutoffCount, 1);
      expect(find.textContaining('race schedule'), findsOneWidget);
      expect(find.textContaining('4 checkpoints'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a route with no markers pushes the course alone',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi(const []),
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.courseWrites, isNotEmpty);
      expect(transport.roadbookWrites, isEmpty,
          reason: 'nothing to schedule is not a failure');
      expect(find.textContaining('Course sent to the watch'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('an over-cap schedule is thinned and the banner says by how much',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          for (var i = 1; i <= 25; i++) _marker('m$i', positionM: i * 200),
        ]),
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.checkpointCount, 16);
      expect(find.textContaining('thinned from 26 to 16 checkpoints'),
          findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('too many cut-offs refuses the schedule, the course still lands',
        (tester) async {
      // Cut-offs are never trimmed — a dropped one makes the watch confidently
      // wrong about which limit is next, so the whole schedule is refused and
      // the runner is told to remove some.
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          for (var i = 1; i <= 17; i++)
            _marker('c$i',
                positionM: i * 200, kind: 'cutoff', cutoffElapsedS: i * 600),
        ]),
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.courseWrites, isNotEmpty);
      expect(transport.roadbookWrites, isEmpty);
      expect(find.textContaining('17 cut-offs'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('clock-only cut-offs are disclosed, never silently missing',
        (tester) async {
      // No start clock is available headlessly, so a clock-only cut-off cannot
      // resolve into a limit. It must be reported — a cut-off that quietly
      // fails to reach the watch is the exact failure this schedule prevents.
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          _marker('a', positionM: 2000),
          _marker('b', positionM: 5000, kind: 'cutoff', cutoffClock: '14:00'),
        ]),
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.roadbookWrites, isNotEmpty);
      expect(transport.cutoffCount, 0);
      expect(find.textContaining('need a race start time'), findsOneWidget);
      await _drainBanner(tester);
    });

    testWidgets('a marker-fetch failure degrades to a course-only push',
        (tester) async {
      final transport = _FakeCourseTransport();
      final api = _MarkersApi(const [], failMarkers: true);
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: api,
        isOwner: true,
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(api.fetchCount, 1);
      expect(transport.courseWrites, isNotEmpty,
          reason: 'the course already landed; an auxiliary failure must not '
              'retroactively report it as failed');
      expect(transport.roadbookWrites, isEmpty);
      expect(find.textContaining('Course sent to the watch'), findsOneWidget);
      await _drainBanner(tester);
    });
  });
}
