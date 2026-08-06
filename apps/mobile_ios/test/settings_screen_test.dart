import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/settings_account_screen.dart';
import '../lib/screens/settings_about_screen.dart';
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
  LocalGearStore? gearStore,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(
        preferences: prefs,
        heartRate: heartRate,
        treadmill: BleTreadmill(),
        runStore: runStore,
        gearStore: gearStore,
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
        await tester.scrollUntilVisible(find.text(label.toUpperCase()), 200,
            scrollable: find.byType(Scrollable).first);
        expect(find.text(label.toUpperCase()), findsOneWidget,
            reason: '$label section header must render');
      }
    });

    testWidgets('renders every tab tile', (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      final list = find.byType(Scrollable).first;
      for (final label in const [
        'Account',
        'Preferences',
        'Coaching',
        'Guided runs',
        'Integrations',
        'Signed-in devices',
        'Gear',
        'Pro & support',
        'About & updates',
      ]) {
        await tester.scrollUntilVisible(find.text(label), 200,
            scrollable: list);
        expect(find.text(label), findsOneWidget,
            reason: '$label tab must render on the landing');
      }
    });

    testWidgets('Signed-in devices tile surfaces a sign-in subtitle when signed-out',
        (tester) async {
      // Devices is server-only (user_device_settings table); the tile
      // stays tappable but the subtitle tells the user sign-in is
      // needed. Gear, by contrast, now works fully offline via
      // LocalGearStore, so its subtitle stays neutral regardless of
      // sign-in state.
      // A gear store must be wired for this test to say anything about
      // sign-out: without one the tile is disabled for a different reason
      // entirely (#666 I16), and the pre-I16 code hid that by leaving `onTap`
      // non-null while doing nothing when tapped.
      final s = await _makeStores();
      await _pump(
        tester,
        prefs: s.prefs,
        heartRate: s.heartRate,
        gearStore: LocalGearStore(),
      );
      await tester.scrollUntilVisible(find.text('Signed-in devices'), 200,
          scrollable: find.byType(Scrollable).first);
      final devices = tester.widget<ListTile>(find.ancestor(
        of: find.text('Signed-in devices'),
        matching: find.byType(ListTile),
      ));
      expect(devices.onTap, isNotNull,
          reason: 'Devices tile must stay tappable when signed-out');
      expect(find.text("Sign in to see where you're signed in"), findsOneWidget);

      await tester.scrollUntilVisible(find.text('Gear'), 200,
          scrollable: find.byType(Scrollable).first);
      final gear = tester.widget<ListTile>(find.ancestor(
        of: find.text('Gear'),
        matching: find.byType(ListTile),
      ));
      expect(gear.onTap, isNotNull,
          reason: 'Gear tile must stay tappable when signed-out');
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
      await tester.scrollUntilVisible(
        find.text('Pro & support'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Pro & support'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsProScreen), findsOneWidget);
    });

    testWidgets('About & updates tile pushes SettingsAboutScreen',
        (tester) async {
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(
        find.text('About & updates'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('About & updates'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsAboutScreen), findsOneWidget);
    });
  });

  group('SettingsAccountScreen (offline affordances)', () {
    testWidgets('Sentry opt-out renders when signed-out (local data)',
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
    });

    testWidgets('Guided runs stays reachable signed-out from the landing',
        (tester) async {
      // The tile moved off the account screen to sit beside Coaching on the
      // landing (#666 I7), but the invariant it used to pin here is
      // unchanged: the library is local TTS scripts with no API dependency,
      // so it must not acquire a sign-in gate on the way.
      final s = await _makeStores();
      await _pump(tester, prefs: s.prefs, heartRate: s.heartRate);
      await tester.scrollUntilVisible(find.text('Guided runs'), 200,
          scrollable: find.byType(Scrollable).first);
      final tile = tester.widget<ListTile>(find.ancestor(
        of: find.text('Guided runs'),
        matching: find.byType(ListTile),
      ));
      expect(tile.onTap, isNotNull,
          reason: 'Guided runs is a local screen with no API '
              'dependency — must not require sign-in.');
    });
  });
}
