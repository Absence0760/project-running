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
// tab (Clubs gets "New club", Challenges "Create challenge"; Feed /
// People / Discover have no create surface).

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

Future<SocialScreen> _socialScreen({SocialTab initialTab = SocialTab.feed}) async {
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

  testWidgets('all 5 labels render untruncated (#498)', (tester) async {
    // Five tabs (Feed/People/Clubs/Discover/Challenges) squeezed into equal
    // fixed-width slots ellipsized "Challenges"/"Discover" on typical phone
    // widths. `AppTabBar` scrolls the strip when the labels stop fitting, so
    // #498's outcome is now derived rather than asserted as a flag (#666 C6).
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();

    for (final label in ['Feed', 'People', 'Clubs', 'Discover', 'Challenges']) {
      final text = tester.widget<Text>(
          find.descendant(of: find.byType(TabBar), matching: find.text(label)));
      // A fixed TabBar clips overflow; a scrollable one lets the label lay
      // out at its natural size. No maxLines/ellipsis override means the
      // label is never truncated.
      expect(text.overflow, isNot(TextOverflow.ellipsis),
          reason: '$label must not be ellipsized');
    }
  });

  testWidgets('the strip scrolls once the labels stop fitting (#666 C6)',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();

    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.isScrollable, isTrue);
    // Flush, not Material's 52dp startOffset — the fitness hub's filled strip
    // puts its first tab at x=0 and switching destinations must not slide it.
    expect(tabBar.tabAlignment, TabAlignment.start);
  });

  testWidgets('initialTab SocialTab.discover selects the Discover tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.discover)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 3);
  });

  testWidgets('the default initialTab selects the Feed tab',
      (tester) async {
    // Bottom-nav default — fresh follower activity is the most-likely
    // reason a user taps Social, so Feed wins the default slot.
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 0);
  });

  testWidgets('initialTab SocialTab.clubs selects the Clubs tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.clubs)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 2);
  });

  testWidgets('initialTab SocialTab.people selects the People tab on first frame',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.people)));
    await tester.pump();
    final tabBar = tester.widget<TabBar>(find.byType(TabBar));
    expect(tabBar.controller!.index, 1);
  });

  // This replaces an out-of-range clamp test. `initialTab` was an int, and the
  // clamp is what HID the § 490 bug rather than catching it: a stale
  // `initialTab: 3` literal stayed IN RANGE after the tab set changed, so the
  // notification bell opened the wrong tab in silence. With an enum, out of
  // range is unrepresentable — so what is worth pinning instead is the
  // property a clamp could never give: every value has its own tab, and the
  // strip is exactly as long as the enum.
  testWidgets('every SocialTab opens its own tab, and the strip is exactly as '
      'long as the enum', (tester) async {
    for (final tab in SocialTab.values) {
      // Unmount first: pumping another SocialScreen straight over the previous
      // one reuses the element, so the TabController built in initState (and
      // with it initialIndex) survives and the next value silently reads as the
      // last one's tab.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(_wrap(await _socialScreen(initialTab: tab)));
      await tester.pump();
      final tabBar = tester.widget<TabBar>(find.byType(TabBar));
      expect(tabBar.controller!.index, tab.index,
          reason: '$tab did not open its own tab');
      expect(tabBar.tabs.length, SocialTab.values.length,
          reason: 'the strip and the enum disagree on how many tabs exist');
    }
    // Assert the population: an empty enum would satisfy the loop above.
    expect(SocialTab.values.length, greaterThan(1));
  });

  testWidgets('the default Feed tab shows no FAB', (tester) async {
    // Feed / People / Discover have no create surface — only the Clubs and
    // Challenges sub-tabs hoist a FAB. The default landing (Feed) shows none.
    await tester.pumpWidget(_wrap(await _socialScreen()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the Clubs tab hoists the "New club" FAB', (tester) async {
    // SocialScreen hoists the Clubs sub-tab's FAB. It resolves off the
    // ClubsScreen GlobalKey state, which binds via a post-frame rebuild.
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.clubs)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('New club'), findsOneWidget);
  });

  testWidgets('switching from Clubs to Discover drops the FAB',
      (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.clubs)));
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

  testWidgets('the Challenges tab hoists the "Create challenge" FAB',
      (tester) async {
    // Challenges is the second sub-tab with a create surface. It resolves off
    // the same GlobalKey + post-frame rebuild the Clubs FAB does.
    await tester.pumpWidget(
        _wrap(await _socialScreen(initialTab: SocialTab.challenges)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Create challenge'), findsOneWidget);
  });

  testWidgets('switching from Challenges to Feed drops the FAB',
      (tester) async {
    await tester.pumpWidget(
        _wrap(await _socialScreen(initialTab: SocialTab.challenges)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(FloatingActionButton), findsOneWidget);

    await tester.tap(find.text('Feed'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byType(FloatingActionButton), findsNothing);
  });

  testWidgets('the People tab shows no FAB', (tester) async {
    await tester.pumpWidget(_wrap(await _socialScreen(initialTab: SocialTab.people)));
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
