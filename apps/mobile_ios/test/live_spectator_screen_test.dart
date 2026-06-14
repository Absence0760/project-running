import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' hide Route;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/preferences.dart';
import '../lib/screens/live_spectator_screen.dart';
import '../lib/widgets/error_state.dart';

/// Test seam: returns a canned public-run row + ping backlog so the
/// terminal-state branch in `_hydrate` can be driven without a backend.
/// Subclassing the real type keeps it a drop-in for the screen's `api`.
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

RunRow _run({
  required int durationS,
  required DateTime startedAt,
  bool isDnf = false,
}) => RunRow(
  id: 'r1',
  userId: 'u1',
  startedAt: startedAt,
  durationS: durationS,
  distanceM: 5000,
  source: 'app',
  activityType: 'run',
  isDnf: isDnf,
);

Map<String, dynamic> _ping(DateTime at) => {
  'lat': -37.8136,
  'lng': 144.9631,
  'distance_m': 2000,
  'elapsed_s': 600,
  'at': at.toUtc().toIso8601String(),
};

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  // LiveRunMap reads dotenv for the tile-style key; an empty env makes
  // those reads return '' instead of throwing NotInitializedError when
  // the terminal-state tests mount the map with a hydrated trace.
  dotenv.loadFromString(isOptional: true);
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

Future<void> _pump(WidgetTester tester) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: LiveSpectatorScreen(
        api: ApiClient(),
        runId: 'fake-run-id',
      ),
    ),
  );
}

Future<void> _pumpApi(WidgetTester tester, ApiClient api) {
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

  // ─────────────────────────── Initial render ────────────────────────
  //
  // The seed-line case from before the deepening pass. Kept because
  // it's the cheapest smoke test — confirms the screen mounts at all,
  // routes the constructor args, and wires the AppBar.
  group('LiveSpectatorScreen — initial render', () {
    testWidgets('renders the Live tracking app-bar title', (tester) async {
      await _pump(tester);
      expect(find.text('Live tracking'), findsOneWidget);
    });

    testWidgets('shows the spinner before _hydrate resolves', (tester) async {
      // initState calls _hydrate which awaits the network. The first
      // pump (no settle) catches the pre-resolution loading frame.
      // Without this guard, a refactor that flips _loading=false at
      // construction (e.g. lazy hydration) would silently strip the
      // spinner and surface ErrorState immediately.
      await _pump(tester);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('status badge reads "Connecting" while hydrating', (tester) async {
      // The badge's three states (Connecting / Idle / Live) are the
      // only visible signal of realtime channel health on this screen.
      // Pin the initial label so a refactor that re-orders the switch
      // arms (e.g. defaulting to 'idle' instead of 'connecting') can't
      // ship a "Live" badge to a spectator who hasn't actually been
      // connected yet.
      await _pump(tester);
      expect(find.text('Connecting'), findsOneWidget);
    });
  });

  // ───────────────────────── Hydrate-failure path ───────────────────
  //
  // Without a real local Supabase backing, `ApiClient.fetchLiveRunPings`
  // throws on the first call. The screen catches it in `_hydrate` and
  // routes to ErrorState. Three things matter:
  //   1. The empty-state ("Waiting for the runner…") does NOT render
  //      — that copy is reserved for the successful-hydrate-but-no-
  //      pings case, not for fetch failure.
  //   2. ErrorState renders with the canonical "Could not connect."
  //      message — pinned because changing the copy silently degrades
  //      the L4-resilience contract for a spectator who hit a backend
  //      hiccup mid-watch.
  //   3. ErrorState's Retry button is present + tappable. Without
  //      Retry the only recovery affordance is full app restart.
  group('LiveSpectatorScreen — hydrate failure', () {
    testWidgets('renders ErrorState after the network call fails', (tester) async {
      await _pump(tester);
      // Let _hydrate's Future resolve into the catch branch.
      await tester.pumpAndSettle();
      expect(find.byType(ErrorState), findsOneWidget);
      expect(find.text('Could not connect.'), findsOneWidget);
    });

    testWidgets('ErrorState exposes a Retry button', (tester) async {
      // The retry path is what flips a stale-link spectator out of
      // an error state if the runner reconnects. Pin the affordance
      // by name — a copy change ("Try again", "Reload") is the kind
      // of drive-by edit that breaks recovery flows silently.
      await _pump(tester);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
    });

    testWidgets(
      'does not show the spinner OR the waiting-for-pings copy after failure',
      (tester) async {
        // The three visible-body states are mutually exclusive (loading
        // / errored / hydrated). Confirm the failure-path doesn't leak
        // into the other two — a refactor that forgot to clear
        // `_loading=false` in the catch branch would render both the
        // spinner and ErrorState, and a hydrate that returned
        // gracefully on error would render the "Waiting for the
        // runner…" empty state on what was actually a backend outage.
        await _pump(tester);
        await tester.pumpAndSettle();
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(
          find.text('Waiting for the runner to send the first ping…'),
          findsNothing,
        );
      },
    );
  });

  // ──────────────────────── Formatter unit tests ────────────────────
  //
  // Hoisted out of `_LiveSpectatorScreenState` via @visibleForTesting
  // (see lib/screens/live_spectator_screen.dart). These are pure
  // functions but they light up on every realtime ingest — a regression
  // (always-H:MM:SS, off-by-one rounding) would silently mis-render
  // for every spectator. Boundary cases pinned:
  //   - sub-minute      → "0:42"
  //   - exactly 1m      → "1:00"
  //   - sub-hour        → "59:59"
  //   - exactly 1h      → "1:00:00" (the format flips at the hour mark)
  //   - multi-hour      → "2:30:45"
  //   - zero            → "0:00"
  group('formatLiveDuration', () {
    test('sub-minute renders M:SS without leading zero on minutes', () {
      expect(formatLiveDuration(const Duration(seconds: 42)), '0:42');
    });
    test('exactly one minute', () {
      expect(formatLiveDuration(const Duration(minutes: 1)), '1:00');
    });
    test('just-under one hour stays in M:SS', () {
      expect(formatLiveDuration(const Duration(minutes: 59, seconds: 59)), '59:59');
    });
    test('exactly one hour flips to H:MM:SS', () {
      expect(formatLiveDuration(const Duration(hours: 1)), '1:00:00');
    });
    test('multi-hour duration zero-pads minutes + seconds', () {
      expect(
        formatLiveDuration(const Duration(hours: 2, minutes: 30, seconds: 45)),
        '2:30:45',
      );
    });
    test('zero duration is "0:00"', () {
      expect(formatLiveDuration(Duration.zero), '0:00');
    });
  });

  // The pace formatter takes seconds-per-km and emits "M:SS /km". The
  // rounding is `.round()` on the (seconds % 60) fraction, so a pace of
  // 5:30.5/km should land on "5:31 /km" (not "5:30"). Pin every shape.
  group('formatLivePace', () {
    test('whole-minute pace zero-pads the seconds', () {
      expect(formatLivePace(300), '5:00 /km'); // 5:00 flat
    });
    test('mid-minute pace pads correctly', () {
      expect(formatLivePace(330), '5:30 /km'); // 5:30
    });
    test('sub-10s tail zero-pads on the right', () {
      expect(formatLivePace(305), '5:05 /km');
    });
    test('rounds the fractional second (canonical UnitFormat shape)', () {
      // Delegates to formatPaceForPref → UnitFormat.pace, which rounds the
      // whole-second total to match web's paceMinutesSeconds (decisions:
      // 1ec6f688). 330.5/km rounds up to "5:31 /km".
      expect(formatLivePace(330.5), '5:31 /km');
    });
    test('never emits an invalid 60th second', () {
      // 359.9/km rounds to 360 s, which rolls cleanly to "6:00 /km" — never
      // the invalid "5:60 /km". Rounding the total FIRST (not the seconds
      // field in isolation) is what makes the rollover safe.
      expect(formatLivePace(359.9), '6:00 /km');
    });
    test('handles very slow paces (>10 min/km)', () {
      expect(formatLivePace(720), '12:00 /km');
    });
    test('mi mode: renders pace + label in the user unit', () async {
      SharedPreferences.setMockInitialValues({'use_miles': true});
      final prefs = Preferences();
      await prefs.init();
      registerActivePreferences(prefs);
      addTearDown(resetActivePreferencesForTest);
      // 300 s/km → 300 * 1.609344 ≈ 482.8 s/mi → rounds to 483 → 8:03 /mi.
      expect(formatLivePace(300), '8:03 /mi');
    });
  });

  // ─────────────────────── runIsFinished unit ───────────────────────
  //
  // Mirror of the web `/live/[id]` runIsFinished: a run is finished only
  // once `started_at + duration_s` is > 2 min in the past. The 2 min
  // slack keeps a just-completed run "live" until the final row lands.
  group('runIsFinished', () {
    test('a zero-duration run is never finished', () {
      expect(
        runIsFinished(
          _run(durationS: 0, startedAt: DateTime.utc(2020)),
          now: DateTime.utc(2020, 1, 1, 1),
        ),
        isFalse,
      );
    });
    test('a run that ended > 2 min ago is finished', () {
      final start = DateTime.utc(2026, 1, 1, 10);
      // ends at 10:30; "now" is 10:40 → 10 min past the end.
      expect(
        runIsFinished(_run(durationS: 1800, startedAt: start),
            now: DateTime.utc(2026, 1, 1, 10, 40)),
        isTrue,
      );
    });
    test('a run inside the 2-min finishing slack is still live', () {
      final start = DateTime.utc(2026, 1, 1, 10);
      // ends at 10:30; "now" is 10:31 → only 1 min past, within slack.
      expect(
        runIsFinished(_run(durationS: 1800, startedAt: start),
            now: DateTime.utc(2026, 1, 1, 10, 31)),
        isFalse,
      );
    });
  });

  // ──────────────────── Terminal vs live vs stale ───────────────────
  //
  // The four states the spectator badge must distinguish are mutually
  // exclusive and must never collapse into each other:
  //   - Finished : run.duration places its end > 2 min ago (frozen)
  //   - DNF      : run.is_dnf (race-marked, frozen)
  //   - Live     : a fresh recent ping
  //   - Delayed  : a *live* run whose last ping went stale (signal loss)
  // Finished/DNF are terminal (no realtime, frozen totals) and outrank
  // the live/stale freshness axis; Delayed is NOT terminal.
  group('LiveSpectatorScreen — terminal vs live vs stale', () {
    testWidgets('a finished run shows the Finished badge, not Live', (tester) async {
      // Empty pings keep the map off the tree (no trace) so the assertion
      // is a clean badge check — the terminal verdict comes from the run
      // row, not the ping backlog. pumpAndSettle drains _hydrate.
      final api = _FakeApi(
        run: _run(
          durationS: 1800,
          startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
        ),
      );
      await _pumpApi(tester, api);
      await tester.pumpAndSettle();
      expect(find.text('Finished'), findsOneWidget);
      expect(find.text('Live'), findsNothing);
      expect(find.text('DNF'), findsNothing);
    });

    testWidgets('a race-marked DNF run shows the DNF badge', (tester) async {
      final api = _FakeApi(
        run: _run(
          durationS: 1800,
          startedAt: DateTime.now().toUtc().subtract(const Duration(hours: 2)),
          isDnf: true,
        ),
      );
      await _pumpApi(tester, api);
      await tester.pumpAndSettle();
      expect(find.text('DNF'), findsOneWidget);
      expect(find.text('Finished'), findsNothing);
      expect(find.text('Live'), findsNothing);
    });

    testWidgets('a still-running run with a fresh ping shows Live', (tester) async {
      // Run is not yet finished (started 5 min ago, no duration) and the
      // last ping is current → Live, distinct from the terminal states.
      // Wrapped in runAsync because the live (non-terminal) path opens the
      // Supabase realtime channel, whose heartbeat is a real Timer.periodic
      // that the fake-async pending-timer invariant would otherwise flag.
      final api = _FakeApi(
        run: _run(
          durationS: 0,
          startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        ),
        pings: [_ping(DateTime.now())],
      );
      await tester.runAsync(() async {
        await _pumpApi(tester, api);
        await tester.pump(); // resolve _hydrate
        await tester.pump();
        expect(find.text('Live'), findsOneWidget);
        expect(find.text('Finished'), findsNothing);
        expect(find.text('DNF'), findsNothing);
        expect(find.text('Delayed'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });

    testWidgets('a live run whose last ping is stale shows Delayed', (tester) async {
      // Same not-finished run, but the only ping is > 90 s old → the
      // position can't be trusted as current. Delayed is NOT terminal.
      final api = _FakeApi(
        run: _run(
          durationS: 0,
          startedAt: DateTime.now().toUtc().subtract(const Duration(minutes: 5)),
        ),
        pings: [_ping(DateTime.now().subtract(const Duration(minutes: 3)))],
      );
      await tester.runAsync(() async {
        await _pumpApi(tester, api);
        await tester.pump(); // resolve _hydrate
        await tester.pump();
        expect(find.text('Delayed'), findsOneWidget);
        expect(find.text('Live'), findsNothing);
        expect(find.text('Finished'), findsNothing);
        expect(find.text('DNF'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    });
  });
}
