import 'dart:async';
import 'dart:convert';
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
import '../lib/screens/roadbook_screen.dart'
    show RoadbookScreen, roadbookPlanPrefsKey;
import '../lib/screens/route_detail_screen.dart';
import '../lib/sim_watch_sync.dart' show WatchBleTransport;
import '../lib/watch_course.dart' show kMaxCoursePoints;
import '../lib/watch_roadbook.dart'
    show
        kRoadbookCheckpointLen,
        kRoadbookCutoffLen,
        kRoadbookHeaderLen;

const _localBackend = 'http://127.0.0.1:54321';
const _prodBackend = 'https://abcdefgh.supabase.co';

/// A four-hour goal off an 08:00 gun — a plan the runner already set on the
/// crew sheet, which is the ordinary case for every test not about the prompt.
const _defaultPlan = '{"goal_s":14400,"start_min":480,"model":"effort"}';

/// Course-only transport: the push writes chunks, nothing else is exercised.
class _FakeCourseTransport implements WatchBleTransport {
  final courseWrites = <List<int>>[];
  final roadbookWrites = <List<int>>[];
  final bool failWrite;

  /// The `PSH1` verdicts the watch answers `push_status` reads with, in order.
  /// Empty is a watch with no verdict to give — the push stays unconfirmed.
  final List<List<int>> pushStatusReads;
  int pushStatusReadCount = 0;
  int scans = 0;
  int disconnects = 0;

  _FakeCourseTransport({
    this.failWrite = false,
    this.pushStatusReads = const [],
  });

  @override
  Future<void> scan() async => scans++;
  @override
  Future<List<int>> readPushStatus() async {
    final at = pushStatusReadCount++;
    if (at >= pushStatusReads.length) {
      return pushStatusReads.isEmpty ? const [] : pushStatusReads.last;
    }
    return pushStatusReads[at];
  }
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

  ({int distM, int elapsedS}) checkpointAt(int i) {
    final view = ByteData.sublistView(roadbookFrame);
    final off = kRoadbookHeaderLen + i * kRoadbookCheckpointLen;
    return (
      distM: view.getUint32(off, Endian.little),
      elapsedS: view.getUint32(off + 8, Endian.little),
    );
  }

  ({int distM, int limitS}) cutoffAt(int i) {
    final view = ByteData.sublistView(roadbookFrame);
    final off = kRoadbookHeaderLen +
        checkpointCount * kRoadbookCheckpointLen +
        i * kRoadbookCutoffLen;
    return (
      distM: view.getUint32(off, Endian.little),
      limitS: view.getUint32(off + 4, Endian.little),
    );
  }

  /// The margin the watch will read at [distM]: the cut-off's limit less the
  /// arrival the same frame projects for that checkpoint.
  int wireMarginAt(int distM) {
    final cutoff = [
      for (var i = 0; i < cutoffCount; i++) cutoffAt(i),
    ].firstWhere((c) => c.distM == distM);
    final checkpoint = [
      for (var i = 0; i < checkpointCount; i++) checkpointAt(i),
    ].firstWhere((c) => c.distM == distM);
    return cutoff.limitS - checkpoint.elapsedS;
  }

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

/// A stored race plan, in the shape `roadbook_screen.dart` persists.
String _planJson({int goalS = 4 * 3600, int? startMin}) => jsonEncode({
      'goal_s': goalS,
      if (startMin != null) 'start_min': startMin,
      'model': 'effort',
    });

/// The margin string the crew sheet prints beside a cut-off. Written out here
/// rather than reached for in the screen, so the test's arithmetic is
/// independent of the code it is checking.
String _marginText(int seconds) {
  final sign = seconds < 0 ? '−' : '+';
  final a = seconds.abs();
  final h = a ~/ 3600;
  final m = (a % 3600) ~/ 60;
  final s = a % 60;
  final two = (int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$sign$h:${two(m)}:${two(s)}' : '$sign$m:${two(s)}';
}

Future<void> _pump(
  WidgetTester tester,
  cm.Route route, {
  required _FakeCourseTransport transport,
  String backendUrl = _localBackend,
  ApiClient? api,
  bool? isOwner,
  String? plan = _defaultPlan,
}) async {
  SharedPreferences.setMockInitialValues({
    if (plan != null) roadbookPlanPrefsKey(route.id): plan,
  });
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

/// Let real store I/O land: the schedule half reads the route's stored race
/// plan out of SharedPreferences, which a fake-async pump never delivers.
Future<void> _settleStore(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

Future<void> _sendToWatch(WidgetTester tester) async {
  await tester.tap(find.text('Send to watch'));
  await tester.pump();
  await _settleStore(tester);
  await tester.pump(const Duration(milliseconds: 400));
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
    });

    testWidgets('a refused push is reported as refused, never as sent',
        (tester) async {
      // The ATT write succeeds — it always does, the SoftDevice answers before
      // the firmware decides — so before the `push_status` verdict this said
      // "Course sent to the watch" while the watch kept the old one.
      final transport = _FakeCourseTransport(pushStatusReads: [
        [...'PSH1'.codeUnits, 1, 1, 1],
        [...'PSH1'.codeUnits, 2, 1, 0],
      ]);
      await _pump(tester, _route(waypoints: _loop(20)), transport: transport);
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(find.textContaining('refused the push'), findsOneWidget);
      expect(find.textContaining('Course sent to the watch'), findsNothing);
      expect(transport.disconnects, 1);
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
    });

    testWidgets('clock-only cut-offs are disclosed, never silently missing',
        (tester) async {
      // A plan with no start clock cannot resolve a clock-only cut-off into an
      // elapsed limit. It must be reported — a cut-off that quietly fails to
      // reach the watch is the exact failure this schedule prevents.
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
        plan: _planJson(),
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.roadbookWrites, isNotEmpty);
      expect(transport.cutoffCount, 0);
      expect(find.textContaining('need a race start time'), findsOneWidget);
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
    });
  });

  group("RouteDetailScreen — the schedule is built from the runner's plan", () {
    testWidgets('a wall-clock cut-off reaches the watch, and the margin '
        'matches the crew sheet', (tester) async {
      // A race whose barriers are all "closes at 11:00" is the ordinary ultra
      // case. Without a start clock every one of them resolves to nothing and
      // the frame carries zero cut-offs, so the watch's CutoffEta, SleepStation
      // and Roadbook pages have no limit to project against.
      final transport = _FakeCourseTransport();
      final markers = [
        _marker('a', positionM: 2000),
        _marker('b', positionM: 5000, kind: 'cutoff', cutoffClock: '11:00'),
      ];
      final route = _route(waypoints: _longLine(30));
      await _pump(
        tester,
        route,
        transport: transport,
        api: _MarkersApi(markers),
        isOwner: true,
        plan: _planJson(goalS: 4 * 3600, startMin: 8 * 60),
      );
      await _openShareMenu(tester);
      await _sendToWatch(tester);

      expect(transport.cutoffCount, 1);
      final wire = transport.cutoffAt(0);
      expect(wire.distM, 5000);
      // 08:00 gun, 11:00 barrier: three hours of elapsed race.
      expect(wire.limitS, 3 * 3600);
      final margin = transport.wireMarginAt(5000);

      // The crew sheet reads the same stored plan, so the margin printed for
      // the crew is the one the watch was handed.
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoadbookScreen(
          route: route,
          waypoints: route.waypoints,
          api: null,
          initialMarkers: markers,
        ),
      ));
      await _settleStore(tester);
      expect(find.text('Cut-off ${_marginText(margin)}'), findsOneWidget);
    });

    testWidgets('with no stored plan the push asks instead of assuming a pace',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          _marker('a', positionM: 2000),
          _marker('b', positionM: 5000, kind: 'cutoff', cutoffClock: '11:00'),
        ]),
        isOwner: true,
        plan: null,
      );
      await _openShareMenu(tester);
      await tester.tap(find.text('Send to watch'));
      await tester.pump();
      await _settleStore(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Race plan'), findsOneWidget);
      expect(transport.courseWrites, isEmpty,
          reason: 'the radio must not be held open behind a modal');

      await tester.tap(find.text('Start time'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('OK'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('06:00'), findsOneWidget);

      await tester.tap(find.text('Send'));
      await tester.pump();
      await _settleStore(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(transport.courseWrites, isNotEmpty);
      expect(transport.cutoffCount, 1);
      // 06:00 gun, 11:00 barrier.
      expect(transport.cutoffAt(0).limitS, 5 * 3600);

      // Answered once, remembered — the crew sheet opens on the same numbers.
      final stored = await tester.runAsync(() async =>
          (await SharedPreferences.getInstance())
              .getString(roadbookPlanPrefsKey('r1')));
      // The seed the runner accepted unchanged: the route's stored 8.5 km at
      // the sheet's own opening 6:30/km.
      expect(jsonDecode(stored!), {
        'goal_s': 3315,
        'start_min': 6 * 60,
        'model': 'effort',
      });
    });

    testWidgets('backing out of the prompt sends the course alone',
        (tester) async {
      // Declining is not consent to a canned pace: a schedule nobody chose
      // would put arrival times on the wrist that no surface on the phone
      // agrees with.
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          _marker('b', positionM: 5000, kind: 'cutoff', cutoffElapsedS: 3600),
        ]),
        isOwner: true,
        plan: null,
      );
      await _openShareMenu(tester);
      await tester.tap(find.text('Send to watch'));
      await tester.pump();
      await _settleStore(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Race plan'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await _settleStore(tester);
      await tester.pump(const Duration(milliseconds: 400));

      expect(transport.courseWrites, isNotEmpty);
      expect(transport.roadbookWrites, isEmpty);
      expect(find.textContaining('Course sent to the watch'), findsOneWidget);
      final stored = await tester.runAsync(() async =>
          (await SharedPreferences.getInstance())
              .getString(roadbookPlanPrefsKey('r1')));
      expect(stored, isNull);
    });

    testWidgets('an unparseable goal is refused in place, not sent',
        (tester) async {
      final transport = _FakeCourseTransport();
      await _pump(
        tester,
        _route(waypoints: _longLine(30)),
        transport: transport,
        api: _MarkersApi([
          _marker('b', positionM: 5000, kind: 'cutoff', cutoffElapsedS: 3600),
        ]),
        isOwner: true,
        plan: null,
      );
      await _openShareMenu(tester);
      await tester.tap(find.text('Send to watch'));
      await tester.pump();
      await _settleStore(tester);
      await tester.pump(const Duration(milliseconds: 400));

      await tester.enterText(find.byType(TextField), 'soon');
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Enter a goal time like 4:30:00'), findsOneWidget);
      expect(find.text('Race plan'), findsOneWidget);
      expect(transport.courseWrites, isEmpty);
    });
  });
}
