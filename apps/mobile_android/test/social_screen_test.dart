// Widget tests for SocialScreen — the top-level "Social" hub that
// replaced the old Clubs tab on the bottom nav. Mirrors the web
// `/social` route's four-tab shape (Feed / People / Clubs / Discover).
//
// Routes used to live here as a sub-tab; the Fitness-hub redesign
// relocated it to Fitness → Runs (a run-modality surface). This file
// pins that relocation: Social hosts Feed / People / Clubs / Discover
// and has no Routes tab or route FAB.
//
// The full content of each sub-tab is exercised by the per-screen
// widget tests (feed_screen_test, people_screen_test, clubs_screen,
// discover_screen_test). This file pins the SocialScreen-specific
// contract: the AppBar TabBar mounts with the right 4 tabs, the
// initialTab routing works, and the FAB visibility tracks the active
// tab (Clubs gets "New club"; Feed / People / Discover have no create
// surface).

import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
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

Widget _wrap(SocialScreen child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Future<SocialScreen> _socialScreen({int initialTab = 0}) async {
  return SocialScreen(
    api: ApiClient(),
    social: SocialService(),
    training: TrainingService(),
    routeStore: await _makeRouteStore(),
    initialTab: initialTab,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await _ensureSupabase();
    // ClubsScreen (the Clubs sub-tab) reads dotenv['MAPTILER_KEY'] on load.
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(() {
    if (_tmpDir.existsSync()) _tmpDir.deleteSync(recursive: true);
  });

  testWidgets(
      'SocialScreen mounts Feed / People / Clubs / Discover — no Routes',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.tabs.length, 5);
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
    expect(find.text('Discover'), findsOneWidget);
    expect(find.text('Challenges'), findsOneWidget);
    // Routes relocated to Fitness → Runs; it must not reappear here.
    expect(find.descendant(of: find.byType(TabBar), matching: find.text('Routes')),
        findsNothing);
  });

  testWidgets('initialTab=3 selects the Discover tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 3)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 3);
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

  testWidgets('initialTab out-of-range clamps to a valid index',
      (tester) async {
    // Defensive: a future deep link that points at an unknown tab
    // (e.g. ?tab=99 after a tab is added then removed) must NOT
    // crash. Pin the clamp behaviour. Upper bound is now 4 (Challenges).
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 99)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, lessThanOrEqualTo(4));
    expect(tabBar.controller!.index, greaterThanOrEqualTo(0));
  });

  testWidgets('the default Feed tab shows no FAB', (tester) async {
    // Feed / People / Discover have no create surface — only the Clubs
    // sub-tab hoists a FAB. The default landing (Feed) must show none.
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the Clubs tab hoists the "New club" FAB', (tester) async {
    // The Clubs sub-tab (index 2) is the only one with a create surface;
    // SocialScreen hoists its FAB. The FAB resolves off the ClubsScreen
    // GlobalKey state, which binds via a scheduled post-frame rebuild.
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('New club'), findsOneWidget);
  });

  testWidgets('switching from Clubs to Discover drops the FAB',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 2)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsOneWidget);

    // Tap the Discover tab and let the controller + Scaffold FAB
    // exit-animation settle (the Scaffold animates the FAB out).
    await tester.tap(find.text('Discover'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the People tab shows no FAB', (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: 1)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsNothing);
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
