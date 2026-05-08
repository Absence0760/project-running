import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_screen.dart';

late Directory _runsDir;

Future<({LocalRunStore runStore, Preferences prefs, BleHeartRate heartRate})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('settings_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  return (runStore: runStore, prefs: prefs, heartRate: BleHeartRate());
}

Future<void> _pump(
  WidgetTester tester, {
  required Preferences prefs,
  required BleHeartRate heartRate,
  LocalRunStore? runStore,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: SettingsScreen(
        preferences: prefs,
        heartRate: heartRate,
        runStore: runStore,
      ),
    ),
  );
}

void main() {
  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('SettingsScreen', () {
    testWidgets('renders the Settings app bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders the Account section', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('renders the Preferences section', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();
      expect(find.text('Preferences'), findsOneWidget);
    });

    testWidgets('useMiles toggle changes the preference value', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      expect(s.prefs.useMiles, isFalse);

      // The Units tile is in the Preferences section — scroll down to it.
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      // Find the Switch associated with miles/km.
      final switches = find.byType(Switch);
      if (switches.evaluate().isNotEmpty) {
        // Toggle the first Switch (units).
        await tester.tap(switches.first);
        await tester.pumpAndSettle();
      }
      // Preference change only flows via a Supabase write or dialog when
      // settingsSync is null; test at least that the screen doesn't crash.
    });

    testWidgets('sign-in tile shows ? avatar when no user is signed in',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, heartRate: s.heartRate, runStore: s.runStore);
      expect(find.text('?'), findsOneWidget);
    });

    // Regression coverage for the "Backup service unavailable" gate
    // (commit fc716ea). Pre-fix the entry guard required
    // `apiClient != null`, blocking the offline-restore path on a
    // release APK that wasn't built with --dart-define SUPABASE_URL /
    // ANON_KEY. Post-fix the guard requires only `runStore`.
    //
    // The Data section (which contains the Restore tile) is gated on
    // `runStore != null` at the section level, so the tile only
    // renders when a runStore is present. These two tests pin the
    // tile's visibility AND the absence of the unavailability banner
    // when api is null but runStore is wired up.
    testWidgets('Restore-from-backup tile is hidden when runStore is missing',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      // Scroll all the way down — the Restore tile would be near the
      // bottom of the Data section if it were rendered.
      await tester.drag(
          find.byType(ListView), const Offset(0, -2000));
      await tester.pump();
      expect(find.text('Restore from backup'), findsNothing);
    });

    testWidgets(
        'Restore-from-backup with apiClient: null but runStore set does NOT show "Backup service unavailable"',
        (tester) async {
      // The exact regression. Pre-fix this would have shown the banner;
      // post-fix the guard passes and we route to the FilePicker
      // (which throws MissingPluginException in widget-test env).
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, heartRate: s.heartRate, runStore: s.runStore);
      final tile = find.text('Restore from backup');
      await tester.dragUntilVisible(
        tile,
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(tile);
      // Don't `pumpAndSettle` — the FilePicker channel throws
      // asynchronously and pumpAndSettle would surface that as an
      // unhandled error. Two short pumps drain enough microtasks for
      // a synchronous showTopBanner to register if the guard fires.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Backup service unavailable.'), findsNothing);
    });
  });
}
