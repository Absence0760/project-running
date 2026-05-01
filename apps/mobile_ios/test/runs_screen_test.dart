import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/runs_screen.dart';
import '../lib/screens/add_run_screen.dart';

// Initialised by every test that calls _makeStores; pure unit tests in
// the pagination group don't touch the filesystem so the directory may
// not exist on tearDown — tearDown checks before deleting.
Directory? _runsDir;

Future<({LocalRunStore runStore, LocalRouteStore routeStore, Preferences prefs})>
    _makeStores() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  // LocalRouteStore used without init() — routes returns [] by default.
  final routeStore = LocalRouteStore();

  return (runStore: runStore, routeStore: routeStore, prefs: prefs);
}

/// Build N synthetic runs spaced 30 minutes apart, all anchored within
/// the past few hours of "now" so the default `_RunsRange.week` filter
/// keeps every run visible — pagination tests don't need to open the
/// date-range popup (whose animation breaks pumpAndSettle in test).
List<Run> _makeRuns(int count) {
  final base = DateTime.now().subtract(const Duration(minutes: 5));
  return [
    for (int i = 0; i < count; i++)
      Run(
        id: 'run-${i.toString().padLeft(3, '0')}',
        startedAt: base.subtract(Duration(minutes: 30 * i)),
        duration: const Duration(minutes: 25),
        distanceMetres: 5000,
        track: const [],
        source: RunSource.app,
      ),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  required LocalRunStore runStore,
  required LocalRouteStore routeStore,
  required Preferences prefs,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: RunsScreen(
        apiClient: null,
        runStore: runStore,
        routeStore: routeStore,
        preferences: prefs,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  tearDown(() {
    final dir = _runsDir;
    if (dir != null && dir.existsSync()) dir.deleteSync(recursive: true);
    _runsDir = null;
  });

  group('RunsScreen', () {
    testWidgets('renders History app-bar title', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('shows empty state when store has no runs', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      // The _EmptyRuns widget is rendered; no run tiles.
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('FAB is present with Add run label', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add run'), findsOneWidget);
    });

    testWidgets('FAB tap navigates to AddRunScreen', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      expect(find.byType(AddRunScreen), findsOneWidget);
    });

    testWidgets('cloud_off icon shown when apiClient is null', (tester) async {
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);
    });
  });

  group('RunsScreen pagination', () {
    test('shouldShowLoadMore — local rows beyond visibleCount', () {
      // 30 filtered, only 20 shown → button reveals the next 10.
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 30,
          remoteHasMore: false,
          apiSignedIn: false,
        ),
        isTrue,
      );
    });

    test('shouldShowLoadMore — exhausted local + signed-in cloud', () {
      // All local rows visible, cloud still hints at more, user signed
      // in → button stays so the next tap pulls older runs.
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 20,
          remoteHasMore: true,
          apiSignedIn: true,
        ),
        isTrue,
      );
    });

    test('shouldShowLoadMore — exhausted local + cloud says done', () {
      // No more local, no more remote → hide.
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 20,
          remoteHasMore: false,
          apiSignedIn: true,
        ),
        isFalse,
      );
    });

    test('shouldShowLoadMore — signed out, no local extras', () {
      // No api → can't fetch from cloud, and nothing more local to show.
      // The signed-in flag is what guards a no-op tap that would just
      // bounce off the early return in _fetchOlderFromRemote.
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 20,
          remoteHasMore: true,
          apiSignedIn: false,
        ),
        isFalse,
      );
    });

    testWidgets('shows only first page of cached runs + Load more button',
        (tester) async {
      // Pre-stage 30 runs on disk before the store boots — see
      // _seedRunFiles for the rationale (awaited file writes hang
      // pumpAndSettle in test). All within the past ~15 h so the
      // default 'this week' range keeps every one visible.
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(30), dir: _runsDir);
      final routeStore = LocalRouteStore();
      final s = (runStore: runStore, routeStore: routeStore, prefs: prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: RunsScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
          ),
        ),
      );
      await tester.pump();

      // First page = 20 runs visible; remaining 10 hidden behind the
      // Load-more button. apiClient is null so the cloud branch is a
      // no-op — but the button must still surface to reveal local rows.
      // ListView.builder is lazy; scroll until the footer materialises
      // (or we exhaust the list, which would fail-fast).
      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
    });

    testWidgets('Load more button hidden when fewer rows than page size',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(5), dir: _runsDir);
      final routeStore = LocalRouteStore();
      final s = (runStore: runStore, routeStore: routeStore, prefs: prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: RunsScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
          ),
        ),
      );
      await tester.pump();

      // 5 runs fit on the first page; no api → no cloud-more guess.
      expect(find.text('Load 20 more'), findsNothing);
    });

    testWidgets('tapping Load more reveals the next local page',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(30), dir: _runsDir);
      final routeStore = LocalRouteStore();
      final s = (runStore: runStore, routeStore: routeStore, prefs: prefs);
      await tester.pumpWidget(
        MaterialApp(
          home: RunsScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
          ),
        ),
      );
      await tester.pump();

      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
      await tester.tap(find.text('Load 20 more'));
      await tester.pump();

      // 30 ≤ 40 (next page), apiClient is null → no further button.
      expect(find.text('Load 20 more'), findsNothing);
    });
  });
}
