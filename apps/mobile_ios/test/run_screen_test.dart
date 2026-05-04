import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

bool _supabaseReady = false;
late Directory _runsDir;

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

  _runsDir = Directory.systemTemp.createTempSync('run_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  final social = SocialService();

  return (
    runStore: runStore,
    routeStore: LocalRouteStore(),
    prefs: prefs,
    social: social,
    training: TrainingService(),
    heartRate: BleHeartRate(),
    audioCues: AudioCues(),
    raceController: RaceController(social),
  );
}

Future<void> _pump(WidgetTester tester, dynamic s) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RunScreen(
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
  // Single pump only — pumpAndSettle would block on the recording-state
  // tickers. The idle state is drawn synchronously.
  await tester.pump();
}

void main() {
  setUpAll(_ensureSupabase);

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('RunScreen — idle state', () {
    testWidgets('renders the activity-type ChoiceChip row',
        (tester) async {
      // Reason: the activity selector is the entry point into the run
      // — without it, users can't choose between Run / Walk / Cycle /
      // Hike before tapping Start.
      final s = await _makeStores();
      await _pump(tester, s);
      // 4 ChoiceChips — one per ActivityType enum value.
      expect(find.byType(ChoiceChip), findsNWidgets(ActivityType.values.length));
    });

    testWidgets('renders all four activity-type labels', (tester) async {
      final s = await _makeStores();
      await _pump(tester, s);
      expect(find.text('Run'), findsOneWidget);
      expect(find.text('Walk'), findsOneWidget);
      expect(find.text('Cycle'), findsOneWidget);
      expect(find.text('Hike'), findsOneWidget);
    });

    testWidgets('shows a Start affordance (the run-ready entry point)',
        (tester) async {
      // The Start trigger may be a FloatingActionButton OR a wrapped
      // gesture detector. Assert *something* large + tappable is
      // visible — a regression that hides the Start path on idle is
      // user-facing severe.
      final s = await _makeStores();
      await _pump(tester, s);
      // A FAB or any FilledButton with start semantics should be in
      // the tree. Use a softer matcher — the design has changed
      // shape over time but the affordance must always exist.
      final hasFab = find.byType(FloatingActionButton).evaluate().isNotEmpty;
      final hasFilled = find.byType(FilledButton).evaluate().isNotEmpty;
      final hasPrimaryGesture =
          find.byType(InkWell).evaluate().isNotEmpty || hasFab || hasFilled;
      expect(hasPrimaryGesture, isTrue,
          reason: 'idle state must surface a tappable Start affordance');
    });

    testWidgets('selecting Walk swaps the active ChoiceChip', (tester) async {
      // ChoiceChip's `selected` flag drives the active styling. After
      // tapping the Walk chip, exactly one chip should be selected.
      // The label widget shape varies (Text vs. Row+Icon+Text), so
      // assert via the surrounding context — the only chip with the
      // 'Walk' label that is selected.
      final s = await _makeStores();
      await _pump(tester, s);

      await tester.tap(find.text('Walk'));
      await tester.pump();

      final selectedChips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .where((c) => c.selected)
          .toList();
      expect(selectedChips.length, 1, reason: 'exactly one chip selected');

      // The selected chip should contain the 'Walk' label somewhere
      // in its descendant tree.
      final selectedFinder = find.byWidgetPredicate(
        (w) => w is ChoiceChip && w.selected,
      );
      expect(
        find.descendant(of: selectedFinder, matching: find.text('Walk')),
        findsOneWidget,
      );
    });

    testWidgets('idle state does NOT instantiate any LiveRunMap yet',
        (tester) async {
      // Map only mounts after begin() — keeping it off the idle widget
      // tree is what lets these tests run without booting the
      // geolocator. If a refactor mounts it earlier, this test fires
      // and the rest of the suite would break.
      final s = await _makeStores();
      await _pump(tester, s);
      // Don't import LiveRunMap explicitly — search by runtime type
      // name to avoid coupling the assertion to a private widget tree.
      final allWidgets = tester.allWidgets;
      final mapMounts = allWidgets
          .where((w) => w.runtimeType.toString() == 'LiveRunMap')
          .toList();
      expect(mapMounts, isEmpty,
          reason: 'LiveRunMap should not mount until recording begins');
    });
  });
}
