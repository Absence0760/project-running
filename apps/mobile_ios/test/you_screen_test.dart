// ignore_for_file: avoid_relative_lib_imports
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_gear_store.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/profile_screen.dart';
import '../lib/screens/you_screen.dart';

/// Signed-in fake so the profile header renders. The pushed ProfileScreen's
/// own load fails gracefully against the uninitialised Supabase client (caught
/// into its error state) — the screen still mounts, which is what we assert.
class _FakeApi extends ApiClient {
  @override
  String? get userId => 'u1';

  @override
  String? get userEmail => 'runner@test.com';
}

void main() {
  final tmpDirs = <Directory>[];
  tearDown(() {
    for (final d in tmpDirs) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
    tmpDirs.clear();
  });

  Directory tmp(String prefix) {
    final d = Directory.systemTemp.createTempSync(prefix);
    tmpDirs.add(d);
    return d;
  }

  Future<void> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();
    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: tmp('you_runs_'));
    final routeStore = LocalRouteStore();
    await routeStore.init(overrideDirectory: tmp('you_routes_'));
    final gearStore = LocalGearStore();
    await gearStore.init(overrideDirectory: tmp('you_gear_'));

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: YouScreen(
        apiClient: _FakeApi(),
        preferences: prefs,
        runStore: runStore,
        routeStore: routeStore,
        gearStore: gearStore,
        heartRate: BleHeartRate(),
        treadmill: BleTreadmill(),
      ),
    ));
    await tester.pump();
  }

  testWidgets('hosts the profile entry + the existing Settings tiles',
      (tester) async {
    await pump(tester);
    // Profile header at the top.
    expect(find.text('Your profile'), findsOneWidget);
    // Settings section tiles fold in below (the unchanged SettingsScreen body).
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Preferences'), findsOneWidget);
  });

  testWidgets('tapping the profile entry pushes ProfileScreen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Your profile'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(ProfileScreen), findsOneWidget);
  });

  testWidgets('a settings tile drills into its sub-screen', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Preferences'));
    // Let the push route transition complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The Preferences sub-screen pushed over You — its own AppBar (with a
    // back button) is up, which a top-level tab screen never shows.
    expect(find.byType(BackButton), findsOneWidget);
  });
}
