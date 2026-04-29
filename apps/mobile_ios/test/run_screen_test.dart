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
  });
}
