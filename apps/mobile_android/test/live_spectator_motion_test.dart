import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/live_spectator_screen.dart';
import 'realtime_drain.dart';

/// Drives the stopped-runner readout on `live_spectator_screen.dart`. The
/// failure this pins is the one the spectator personas care about: a runner
/// still pinging from one spot reads as a plain live dot, and the pace tile
/// — the only stat that would have exposed it — drops out on a zero distance
/// delta, so "not moving" and "no data" looked identical.
class _FakeApi extends ApiClient {
  final RunRow? run;
  final List<Map<String, dynamic>> pings;
  _FakeApi({this.run, this.pings = const []});

  @override
  Future<RunRow?> fetchPublicRunById(String runId) async => run;

  @override
  Future<List<Map<String, dynamic>>> fetchLiveRunPings(String runId) async =>
      pings;
}

RunRow _liveRun() => RunRow(
  id: 'r1',
  userId: 'u1',
  startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 20)),
  durationS: 0,
  distanceM: 5000,
  source: 'app',
  activityType: 'run',
  isDnf: false,
);

Map<String, dynamic> _ping({
  required DateTime at,
  required double distanceM,
  required int elapsedS,
}) => {
  'lat': 0.0,
  'lng': 0.018,
  'distance_m': distanceM,
  'elapsed_s': elapsedS,
  'at': at.toUtc().toIso8601String(),
};

/// [count] pings at 5 s cadence ending [endingAt], each advancing the
/// odometer by [stepM].
List<Map<String, dynamic>> _ramp({
  required DateTime endingAt,
  required int count,
  required double stepM,
  double startM = 5000,
}) {
  final first = endingAt.subtract(Duration(seconds: 5 * (count - 1)));
  return [
    for (var i = 0; i < count; i++)
      _ping(
        at: first.add(Duration(seconds: 5 * i)),
        distanceM: startM + i * stepM,
        elapsedS: 600 + 5 * i,
      ),
  ];
}

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

  group('LiveSpectatorScreen — stopped-runner readout', () {
    realtimeWidgetTest('a runner pinging from one spot is stated, not hidden', (
      tester,
    ) async {
      // Ten minutes of fresh, contiguous pings with the odometer frozen: the
      // runner is visible and healthy-looking, and only this chip says they
      // have not moved.
      final now = DateTime.now();
      final api = _FakeApi(
        run: _liveRun(),
        pings: _ramp(endingAt: now, count: 121, stepM: 0),
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('motion-stopped')), findsOneWidget);
        expect(find.textContaining('Not moving'), findsOneWidget);
        // The stop fills the whole buffer, so the duration is a floor.
        expect(find.textContaining('at least'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    });

    realtimeWidgetTest('a runner covering ground grows no chip', (tester) async {
      final now = DateTime.now();
      final api = _FakeApi(
        run: _liveRun(),
        pings: _ramp(endingAt: now, count: 121, stepM: 8),
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('motion-stopped')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    realtimeWidgetTest('a stale fix claims nothing about motion', (
      tester,
    ) async {
      // The same ten minutes of stationary pings, but they stop 10 min ago:
      // the runner may have walked out of signal, so the chip must not claim
      // they are standing where the last fix put them.
      final end = DateTime.now().subtract(const Duration(minutes: 10));
      final api = _FakeApi(
        run: _liveRun(),
        pings: _ramp(endingAt: end, count: 121, stepM: 0),
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('motion-stopped')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    realtimeWidgetTest('an outage is not reported as stillness', (tester) async {
      // Pings from the same place either side of an hour of silence. The
      // runner was never observed standing there — they could have run out
      // and back — so the surface must stay quiet rather than claim an hour
      // in one spot.
      final now = DateTime.now();
      final before = _ramp(
        endingAt: now.subtract(const Duration(minutes: 60)),
        count: 12,
        stepM: 0,
      );
      final api = _FakeApi(
        run: _liveRun(),
        pings: [
          ...before,
          _ping(at: now, distanceM: 5000, elapsedS: 4200),
        ],
      );
      await tester.runAsync(() async {
        await _pump(tester, api);
        await tester.pump();
        await tester.pump();
        expect(find.byKey(const Key('motion-stopped')), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
