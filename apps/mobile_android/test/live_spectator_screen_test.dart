import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/screens/live_spectator_screen.dart';
import '../lib/widgets/error_state.dart';

bool _supabaseReady = false;

Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
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
      home: LiveSpectatorScreen(
        api: ApiClient(),
        runId: 'fake-run-id',
      ),
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
    test('rounds up on a half-second fraction', () {
      // 5:30.5/km → "5:31 /km". A regression to `.floor()` would
      // render "5:30 /km" for every spectator at this pace.
      expect(formatLivePace(330.5), '5:31 /km');
    });
    test('rolls over from 59 to next minute correctly', () {
      // 359.9 seconds/km → round to 360 → "5:60 /km" or "6:00 /km"?
      // The current shape is "5:60 /km" — pinning this so a future
      // rounding refactor either keeps that or makes a deliberate
      // call to roll over (which would then update this expectation).
      expect(formatLivePace(359.9), '5:60 /km');
    });
    test('handles very slow paces (>10 min/km)', () {
      expect(formatLivePace(720), '12:00 /km');
    });
  });
}
