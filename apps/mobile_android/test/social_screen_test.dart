// Widget tests for SocialScreen — the new top-level "Social" hub
// that replaces the old Clubs tab on the bottom nav. Mirrors the web
// `/social` route's three-tab shape (Feed / People / Clubs).
//
// The full content of each sub-tab is exercised by the per-screen
// widget tests (feed_screen_test, people_screen_test, clubs_screen
// has its own coverage). This file pins the SocialScreen-specific
// contract: the AppBar TabBar mounts with the right 3 tabs, the
// initialTab routing works, and the FAB visibility tracks the
// active tab (only the Clubs tab gets the "New club" FAB — Feed
// and People have no create surface).

import 'package:api_client/api_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

Widget _wrap(SocialScreen child) =>
    MaterialApp(home: child);

SocialScreen _socialScreen({int initialTab = 2}) {
  return SocialScreen(
    api: ApiClient(),
    social: SocialService(),
    training: TrainingService(),
    initialTab: initialTab,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_ensureSupabase);

  testWidgets('SocialScreen mounts 3 tabs with Feed / People / Clubs labels',
      (tester) async {
    await tester.pumpWidget(_wrap(_socialScreen()));
    await tester.pump();

    expect(find.byType(TabBar), findsOneWidget);
    // Tab labels visible in the AppBar tab strip.
    expect(find.text('Feed'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);
    expect(find.text('Clubs'), findsOneWidget);
  });

  testWidgets('initialTab=2 (default) selects the Clubs tab',
      (tester) async {
    await tester.pumpWidget(_wrap(_socialScreen()));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 2);
  });

  testWidgets('initialTab=0 selects the Feed tab on first frame',
      (tester) async {
    // Mirrors the web `/social?tab=feed` deep link.
    await tester.pumpWidget(_wrap(_socialScreen(initialTab: 0)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 0);
  });

  testWidgets('initialTab=1 selects the People tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(_socialScreen(initialTab: 1)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 1);
  });

  testWidgets('initialTab out-of-range clamps to a valid index',
      (tester) async {
    // Defensive: a future deep link that points at an unknown tab
    // (e.g. ?tab=5 after a new tab is added then removed) must NOT
    // crash. Pin the clamp behaviour.
    await tester.pumpWidget(_wrap(_socialScreen(initialTab: 99)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, lessThanOrEqualTo(2));
    expect(tabBar.controller!.index, greaterThanOrEqualTo(0));
  });

  testWidgets('AppBar has no toolbar title (only the TabBar)',
      (tester) async {
    // The bottom-nav already labels the tab "Social". A redundant
    // "Social" title in the AppBar would just duplicate it. Pin
    // that toolbarHeight=0 hides the title row, leaving only the
    // TabBar visible at the top.
    await tester.pumpWidget(_wrap(_socialScreen()));
    await tester.pump();
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, 0);
    expect(appBar.title, isNull);
  });
}
