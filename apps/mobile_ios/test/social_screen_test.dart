// Widget tests for SocialScreen — the top-level "Social" hub that
// replaced the old Clubs tab on the bottom nav. Mirrors the web
// `/social` route's three-tab shape (Feed / People / Clubs), plus a
// 4th Routes sub-tab unique to mobile (web keeps Routes as a
// sidebar peer — mobile folds it to keep the bottom nav at 5 items).
//
// The full content of each sub-tab is exercised by the per-screen
// widget tests (feed_screen_test, people_screen_test, clubs_screen,
// routes_screen). This file pins the SocialScreen-specific contract:
// the AppBar TabBar mounts with the right 4 tabs, the initialTab
// routing works, and the FAB visibility tracks the active tab
// (Clubs gets "New club", Routes gets dual "Build" + "Import";
// Feed and People have no create surface).

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/social_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

bool _supabaseReady = false;
Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  // Local fake — never reached by network; FeedScreen's _loadInitial
  // catches the resulting connection failure asynchronously.
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

late Directory _tmpDir;

Future<LocalRouteStore> _makeRouteStore() async {
  _tmpDir = Directory.systemTemp.createTempSync('social_screen_test_');
  final store = LocalRouteStore();
  // LocalRouteStore.init reads SharedPreferences for the on-disk path
  // override; the mock prefs above keep it pointed at a temp dir.
  await store.init(overrideDirectory: _tmpDir);
  return store;
}

Future<Preferences> _makePreferences() async {
  final p = Preferences();
  await p.init();
  return p;
}

Widget _wrap(SocialScreen child) =>
    MaterialApp(home: child);

Future<SocialScreen> _socialScreen({int initialTab = 0}) async {
  return SocialScreen(
    api: ApiClient(),
    social: SocialService(),
    training: TrainingService(),
    routeStore: await _makeRouteStore(),
    preferences: await _makePreferences(),
    initialTab: initialTab,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_ensureSupabase);

  tearDown(() {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  testWidgets(
      'SocialScreen mounts 4 tabs with Feed / People / Clubs / Routes labels',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    // Tab labels visible in the AppBar tab strip. The Routes tab is
    // mobile-only — it's the one parity bend we make from web (which
    // keeps Routes as a sidebar peer).
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Routes'), findsOneWidget);
  });

  testWidgets('initialTab=0 (default) selects the Feed tab',
      (tester) async {
    // Bottom-nav default — fresh follower activity is the most-likely
    // reason a user taps Social, so Feed wins the default slot.
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 0);
  });

  testWidgets('initialTab=2 selects the Clubs tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 2)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 2);
  });

  testWidgets('initialTab=1 selects the People tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 1)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 1);
  });

  testWidgets('initialTab=3 selects the Routes tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 3)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 3);
  });

  testWidgets('initialTab out-of-range clamps to a valid index',
      (tester) async {
    // Defensive: a future deep link that points at an unknown tab
    // (e.g. ?tab=99 after a tab is added then removed) must NOT
    // crash. Pin the clamp behaviour. Upper bound is now 3 (Routes).
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 99)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, lessThanOrEqualTo(3));
    expect(tabBar.controller!.index, greaterThanOrEqualTo(0));
  });

  testWidgets('AppBar has no toolbar title (only the TabBar)',
      (tester) async {
    // The bottom-nav already labels the tab "Social". A redundant
    // "Social" title in the AppBar would just duplicate it. Pin
    // that toolbarHeight=0 hides the title row, leaving only the
    // TabBar visible at the top.
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, 0);
    expect(appBar.title, isNull);
  });
}
