import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/screens/home_screen.dart';

late Directory _runsDir;

Future<({
  LocalRunStore runStore,
  LocalRouteStore routeStore,
  Preferences prefs,
  SocialService social,
  TrainingService training,
  BleHeartRate heartRate,
  AudioCues audioCues,
  RaceController raceController,
})> _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('home_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  final routeStore = LocalRouteStore();
  final social = SocialService();
  final training = TrainingService();
  final heartRate = BleHeartRate();
  final audioCues = AudioCues();
  final raceController = RaceController(social);

  return (
    runStore: runStore,
    routeStore: routeStore,
    prefs: prefs,
    social: social,
    training: training,
    heartRate: heartRate,
    audioCues: audioCues,
    raceController: raceController,
  );
}

Future<void> _pump(WidgetTester tester, dynamic s) async {
  await tester.pumpWidget(
    MaterialApp(
      home: HomeScreen(
        apiClient: null,
        runStore: s.runStore,
        routeStore: s.routeStore,
        preferences: s.prefs,
        audioCues: s.audioCues,
        social: s.social,
        raceController: s.raceController,
        training: s.training,
        heartRate: s.heartRate,
      ),
    ),
  );
  // Single pump — pumpAndSettle risks hanging when RunScreen's async
  // refresh tasks (fetchNextRsvpedEvent, fetchActiveOverview) fail against
  // an uninitialised Supabase instance and reschedule timers.
  await tester.pump();
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('HomeScreen', () {
    testWidgets('renders a NavigationBar with five destinations', (tester) async {
      // Routes was folded into Social as a sub-tab so the bottom nav
      // stays at five items — see `social_screen.dart`. The mobile_*
      // CLAUDE.md "Scope — read before writing code" rule that web is
      // canonical applies: keeping the top-level nav lean on mobile
      // saves the bottom row for the surfaces that get the most
      // mid-run / one-thumb taps (Home / Run / History / Social /
      // Settings).
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationDestination), findsNWidgets(5));
    });

    testWidgets('shows all five nav labels', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      // Scope each label search to descendants of the NavigationBar so
      // duplicate text elsewhere in the page body doesn't cause false failures.
      final navBar = find.byType(NavigationBar);
      for (final label in ['Home', 'Run', 'History', 'Social', 'Settings']) {
        expect(
          find.descendant(of: navBar, matching: find.text(label)),
          findsOneWidget,
          reason: 'expected "$label" nav label inside NavigationBar',
        );
      }
    });

    testWidgets('Routes label no longer in the bottom NavigationBar',
        (tester) async {
      // Routes is now a sub-tab of Social, not a top-level destination.
      // Catches a regression that adds Routes back to the bottom nav.
      final s = await _makeStores();
      await _pump(tester, s);
      final navBar = find.byType(NavigationBar);
      expect(
        find.descendant(of: navBar, matching: find.text('Routes')),
        findsNothing,
        reason: 'Routes must live inside SocialScreen, not on the bottom nav',
      );
    });

    testWidgets('initial selected tab is Run (index 1)', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 1);
    });

    testWidgets('tapping Home nav item changes selected index to 0', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.text('Home'));
      await tester.pump();
      final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
    });

    testWidgets('tapping Home tab mounts the Dashboard surface', (tester) async {
      // Updated to no longer pin "Dashboard" as a title text since
      // task #43 removed redundant AppBar titles. Instead pin a
      // dashboard-specific text that proves the screen mounted —
      // mock stores are empty so the welcome empty-state ("Welcome!")
      // renders.
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.text('Home'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Welcome!'), findsAtLeastNWidgets(1));
    });

    testWidgets('body is a PageView', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(PageView), findsOneWidget);
    });
  });
}
