import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:core_models/core_models.dart' as cm show Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/live_spectator_screen.dart';

/// Drives the predictive next-cutoff card on `live_spectator_screen.dart`.
/// The fake api returns a live (non-terminal) run linked to a public route
/// carrying one cutoff marker, plus a backlog of pings, so the card's two
/// states can be asserted without a backend: a fresh runner shows the
/// coloured margin chip; a stale fixture suppresses the verdict.
class _FakeApi extends ApiClient {
  final RunRow? run;
  final List<Map<String, dynamic>> pings;
  final cm.Route? route;
  final List<RouteMarkerRow> markers;
  _FakeApi({
    this.run,
    this.pings = const [],
    this.route,
    this.markers = const [],
  });

  @override
  Future<RunRow?> fetchPublicRunById(String runId) async => run;

  @override
  Future<List<Map<String, dynamic>>> fetchLiveRunPings(String runId) async =>
      pings;

  @override
  Future<({cm.Route? route, String? ownerId})> fetchRouteById(
    String routeId,
  ) async =>
      (route: route, ownerId: route?.userId);

  @override
  Future<List<RouteMarkerRow>> fetchRouteMarkers(String routeId) async =>
      markers;
}

/// A live, never-finished run linked to [routeId] (started 5 min ago, no
/// saved duration) so the screen takes the predictive path, not a terminal
/// freeze.
RunRow _liveRun(String routeId) => RunRow(
      id: 'r1',
      userId: 'u1',
      startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
      durationS: 0,
      distanceM: 2000,
      source: 'app',
      activityType: 'run',
      isDnf: false,
      routeId: routeId,
    );

/// A ~6.6 km west→east line at the equator. 0.06° of longitude ≈ 6677 m, so
/// a position fix near 0.018° lng projects to ~2000 m along the route.
cm.Route _route(String id) => cm.Route(
      id: id,
      userId: 'u1',
      name: 'Cutoff course',
      distanceMetres: 6677,
      isPublic: true,
      waypoints: const [
        Waypoint(lat: 0, lng: 0),
        Waypoint(lat: 0, lng: 0.06),
      ],
    );

/// One cutoff marker placed 4000 m along the line, with an elapsed-from-start
/// limit of [limitS] seconds.
RouteMarkerRow _cutoff({required int limitS}) => RouteMarkerRow(
      id: 'm1',
      routeId: 'route-1',
      userId: 'u1',
      kind: 'cutoff',
      label: 'Aid 1',
      lat: 0,
      lng: 0.036,
      positionM: 4000,
      meta: {'cutoff_elapsed_s': limitS},
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

/// A ping ~2000 m along the route (lng 0.018), carrying distance/elapsed so
/// the recent-pace buffer can derive a pace. [at] drives the freshness clock.
Map<String, dynamic> _ping({
  required DateTime at,
  required double distanceM,
  required int elapsedS,
}) =>
    {
      'lat': 0.0,
      'lng': 0.018,
      'distance_m': distanceM,
      'elapsed_s': elapsedS,
      'at': at.toUtc().toIso8601String(),
    };

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  dotenv.loadFromString(isOptional: true);
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester, ApiClient api) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LiveSpectatorScreen(api: api, runId: 'fake-run-id'),
    ),
  );
}

void main() {
  setUpAll(_ensureSupabase);

  group('LiveSpectatorScreen — next-cutoff card', () {
    testWidgets('a fresh runner shows the cutoff card with a margin chip',
        (tester) async {
      // Two pings two minutes apart → recent pace derivable. The cutoff limit
      // is generous (3 h elapsed) so the projection lands comfortably "on",
      // surfacing the green "to spare" chip. runAsync because the live path
      // opens the Supabase realtime channel (a real heartbeat Timer).
      final now = DateTime.now();
      final api = _FakeApi(
        run: _liveRun('route-1'),
        route: _route('route-1'),
        markers: [_cutoff(limitS: 3 * 3600)],
        pings: [
          _ping(
            at: now.subtract(const Duration(minutes: 2)),
            distanceM: 1500,
            elapsedS: 480,
          ),
          _ping(at: now, distanceM: 2000, elapsedS: 600),
        ],
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.text('Aid 1'), findsOneWidget);
        expect(find.textContaining('to spare'), findsOneWidget);
        expect(find.textContaining('Waiting for a fresh signal'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a stale fixture suppresses the verdict', (tester) async {
      // The only ping is > 90 s old → freshness is stale → nextCutoffEta
      // returns `unknown`, so the card shows the checkpoint + distance but
      // the muted "waiting" line instead of a chip.
      final api = _FakeApi(
        run: _liveRun('route-1'),
        route: _route('route-1'),
        markers: [_cutoff(limitS: 3 * 3600)],
        pings: [
          _ping(
            at: DateTime.now().subtract(const Duration(minutes: 3)),
            distanceM: 2000,
            elapsedS: 600,
          ),
        ],
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.text('Aid 1'), findsOneWidget);
        expect(find.textContaining('Waiting for a fresh signal'),
            findsOneWidget);
        expect(find.textContaining('to spare'), findsNothing);
        expect(find.textContaining('behind'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('no card when the run is not linked to a route',
        (tester) async {
      // A live run without a route_id can't resolve cutoff legs, so the
      // predictive card never mounts — only the trace + freshness baseline.
      final api = _FakeApi(
        run: RunRow(
          id: 'r1',
          userId: 'u1',
          startedAt:
              DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
          durationS: 0,
          distanceM: 2000,
          source: 'app',
          activityType: 'run',
          isDnf: false,
        ),
        pings: [_ping(at: DateTime.now(), distanceM: 2000, elapsedS: 600)],
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.text('Aid 1'), findsNothing);
        expect(find.textContaining('to spare'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
