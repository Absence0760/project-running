import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_licenses_screen.dart';
import '../lib/screens/settings_preferences_screen.dart';
import '../lib/screens/settings_pro_screen.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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

  group('SettingsScreen (landing)', () {
    testWidgets('renders no AppBar (bottom-nav labels suffice)',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      expect(find.byType(AppBar), findsNothing);
      expect(find.byType(SafeArea), findsAtLeastNWidgets(1));
    });

    testWidgets('renders the three section headers', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      for (final label in const ['Profile', 'Apps & data', 'Account & legal']) {
        expect(find.text(label.toUpperCase()), findsOneWidget,
            reason: '$label section header must render');
      }
    });

    testWidgets('renders all seven tab tiles', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      final list = find.byType(Scrollable).first;
      for (final label in const [
        'Account',
        'Preferences',
        'Integrations',
        'Devices',
        'Gear',
        'Pro & support',
        'Licenses',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200,
            scrollable: list);
        expect(find.text(label), findsOneWidget,
            reason: '$label tab must render on the landing');
      }
    });

    testWidgets('Devices tile surfaces a sign-in subtitle when signed-out',
        (tester) async {
      // Devices is server-only (user_device_settings table); the tile
      // stays tappable but the subtitle tells the user sign-in is
      // needed. Gear, by contrast, now works fully offline via
      // LocalGearStore, so its subtitle stays neutral regardless of
      // sign-in state.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      final devices = tester.widget<ListTile>(find.ancestor(
        of: find.text('Devices'),
        matching: find.byType(ListTile),
      ));
      final gear = tester.widget<ListTile>(find.ancestor(
        of: find.text('Gear'),
        matching: find.byType(ListTile),
      ));
      expect(devices.onTap, isNotNull,
          reason: 'Devices tile must stay tappable when signed-out');
      expect(gear.onTap, isNotNull,
          reason: 'Gear tile must stay tappable when signed-out');
      expect(find.text('Sign in to manage your devices'), findsOneWidget);
      expect(find.text('Track shoes + bikes and per-item mileage'),
          findsOneWidget,
          reason:
              'Gear is offline-capable now — no sign-in copy on the tile.');
    });

    testWidgets('Account tile pushes SettingsAccountScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester,
          prefs: s.prefs, heartRate: s.heartRate, runStore: s.runStore);
      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsAccountScreen), findsOneWidget);
    });

    testWidgets('Preferences tile pushes SettingsPreferencesScreen',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.tap(find.text('Preferences'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsPreferencesScreen), findsOneWidget);
    });

    testWidgets('Pro & support tile pushes SettingsProScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.tap(find.text('Pro & support'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsProScreen), findsOneWidget);
    });

    testWidgets('Licenses tile pushes SettingsLicensesScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(
        find.text('Licenses'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Licenses'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsLicensesScreen), findsOneWidget);
    });
  });

  group('SettingsAccountScreen (offline affordances)', () {
    testWidgets(
        'Sentry opt-out + Guided runs render when signed-out (local data)',
        (tester) async {
      final s = await _makeStores();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsAccountScreen(
          apiClient: null,
          preferences: s.prefs,
          settingsSync: null,
        ),
      ));
      expect(find.text('Send error reports'), findsOneWidget,
          reason: 'Sentry opt-out is a local GDPR control — must be '
              'reachable without an account.');
      expect(find.text('Guided runs'), findsOneWidget,
          reason: 'Guided runs is a local screen with no API '
              'dependency — must not require sign-in.');
    });

    testWidgets('View profile + Privacy zones are hidden when signed-out',
        (tester) async {
      final s = await _makeStores();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SettingsAccountScreen(
          apiClient: null,
          preferences: s.prefs,
          settingsSync: null,
        ),
      ));
      expect(find.text('View profile'), findsNothing);
      expect(find.text('Privacy zones'), findsNothing);
    });
  });
}
