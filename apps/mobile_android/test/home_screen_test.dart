import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_food_store.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_gym_store.dart';
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
  LocalGearStore gearStore,
  LocalGymStore gymStore,
  LocalFoodStore foodStore,
  Preferences prefs,
  SocialService social,
  TrainingService training,
  BleHeartRate heartRate,
  BleTreadmill treadmill,
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
  final gearStore = LocalGearStore();
  await gearStore.init(
      overrideDirectory:
          Directory.systemTemp.createTempSync('gear_store_test_'));
  final gymStore = LocalGymStore();
  await gymStore.init(
      overrideDirectory: Directory.systemTemp.createTempSync('gym_store_test_'));
  final foodStore = LocalFoodStore();
  await foodStore.init(
      overrideDirectory:
          Directory.systemTemp.createTempSync('food_store_test_'));
  final social = SocialService();
  final training = TrainingService();
  final heartRate = BleHeartRate();
  final treadmill = BleTreadmill();
  final audioCues = AudioCues();
  final raceController = RaceController(social);

  return (
    runStore: runStore,
    routeStore: routeStore,
    gearStore: gearStore,
    gymStore: gymStore,
    foodStore: foodStore,
    prefs: prefs,
    social: social,
    training: training,
    heartRate: heartRate,
    treadmill: treadmill,
    audioCues: audioCues,
    raceController: raceController,
  );
}

Future<void> _pump(WidgetTester tester, dynamic s) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(
        apiClient: null,
        runStore: s.runStore,
        routeStore: s.routeStore,
        gearStore: s.gearStore,
        gymStore: s.gymStore,
        foodStore: s.foodStore,
        preferences: s.prefs,
        audioCues: s.audioCues,
        social: s.social,
        raceController: s.raceController,
        training: s.training,
        heartRate: s.heartRate,
        treadmill: s.treadmill,
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

  group('HomeScreen multi-modal shell', () {
    testWidgets('uses a BottomAppBar + a centre Log FAB, not a NavigationBar',
        (tester) async {
      // Phase 4 reshape (multi_modal.md § Bottom nav): Run leaves the nav as
      // a top-level destination; the centre slot becomes the raised Log
      // action button.
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(BottomAppBar), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets(
        'shows Home/Fitness/Social/You nav labels; Run/History/Settings are not nav labels',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      final bar = find.byType(BottomAppBar);
      for (final label in ['Home', 'Fitness', 'Social', 'You']) {
        expect(
          find.descendant(of: bar, matching: find.text(label)),
          findsOneWidget,
          reason: 'expected "$label" nav label inside BottomAppBar',
        );
      }
      // History is absorbed into Fitness → All; Settings folds into You;
      // Run is captured via the Log button — none are bottom-nav labels.
      for (final gone in ['Run', 'History', 'Settings']) {
        expect(
          find.descendant(of: bar, matching: find.text(gone)),
          findsNothing,
          reason: '"$gone" is no longer a bottom-nav destination',
        );
      }
    });

    testWidgets('the centre Log action shows a visible text label (#256)',
        (tester) async {
      // Every nav tab carries a text label; the centre Log action used to be
      // an unlabelled "+" FAB with a tooltip only. It now caption's "Log"
      // inside the bar so the affordance is discoverable without a hover.
      final s = await _makeStores();
      await _pump(tester, s);
      final bar = find.byType(BottomAppBar);
      expect(
        find.descendant(of: bar, matching: find.text('Log')),
        findsOneWidget,
        reason: 'the centre Log action must carry a visible label in the bar',
      );
    });

    testWidgets('initial page is Home (welcome empty state)', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.pump();
      expect(find.text('Welcome!'), findsAtLeastNWidgets(1));
    });

    testWidgets('body is a PageView', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('tapping the Log FAB fans the capture speed-dial (default mode)',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Icon-only fan — the label is on the Tooltip, not visible text.
      expect(find.byTooltip('Log run'), findsOneWidget);
      expect(find.byTooltip('Log lift'), findsOneWidget);
      expect(find.byTooltip('Log food'), findsOneWidget);
    });

    testWidgets('keepRunPrimary: tapping the Log FAB starts a run, no menu',
        (tester) async {
      final s = await _makeStores();
      await s.prefs.setKeepRunPrimary(true);
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump();
      // No fan — the tap jumped straight to the Run page.
      expect(find.byTooltip('Log lift'), findsNothing);
    });

    testWidgets('picking Log lift lands on the Gym dwell-in page', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Log lift'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      // Not a modal composer — the Log action navigates the PageView to the
      // in-shell Gym page (same model as the run recorder), so the bottom nav
      // stays visible alongside the page's own "Gym" AppBar title.
      expect(find.text('Gym'), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });

    testWidgets('picking Log food lands on the Nutrition dwell-in page',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Log food'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Nutrition'), findsOneWidget);
      expect(find.byType(BottomAppBar), findsOneWidget);
    });
  });
}
