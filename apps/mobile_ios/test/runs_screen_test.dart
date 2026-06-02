// ignore_for_file: avoid_relative_lib_imports
import 'dart:convert';
import 'dart:io';

import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
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
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
    testWidgets(
        'AppBar carries the date-range label + run-count (claiming the '
        'previously-empty title slot)',
        (tester) async {
      // Pre-polish the AppBar had no title and the date-range label
      // lived on its own row below — half a row of dead vertical
      // real estate. Now the range label anchors the AppBar title
      // and the body row drops.
      final s = await _makeStores();
      await _pump(tester, runStore: s.runStore, routeStore: s.routeStore, prefs: s.prefs);
      expect(find.byType(AppBar), findsOneWidget);
      // Default range is "This week" — pinned in the AppBar.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('This week'),
        ),
        findsOneWidget,
      );
      // "0 runs" count chip (empty seed store) sits next to the
      // title.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('0 runs'),
        ),
        findsOneWidget,
      );
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

    testWidgets('header shows aggregate "X km · Y h Z m" for the filtered set',
        (tester) async {
      // Seed three runs that all sit comfortably inside the
      // default-week range. Aggregate: 3 × 5000 m = 15 km, 3 × 25 m =
      // 75 m total time → "75m". The chip text must include both
      // distance + total time.
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({'range': 'all', 'sort': 'newest'}),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_summary_');
      final now = DateTime.now();
      final threeRuns = [
        for (int i = 0; i < 3; i++)
          Run(
            id: 'r-$i',
            startedAt: now.subtract(Duration(days: i)),
            duration: const Duration(minutes: 25),
            distanceMetres: 5000,
            source: RunSource.app,
          ),
      ];
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(threeRuns, dir: _runsDir);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 3 runs × 5 km = 15 km; 3 × 25m = 75m. Pin the formatted output.
      // UnitFormat.distance(15000, km) → "15.00 km" (toStringAsFixed(2)).
      expect(find.textContaining('15.00 km'), findsOneWidget);
      expect(find.textContaining('1h 15m'), findsOneWidget);
    });

    testWidgets('renders month section headers between runs from different months',
        (tester) async {
      // Seed two runs in different calendar months so the History
      // grouping must emit two headers. Range is pinned to 'all' so
      // the default 'this week' filter doesn't drop the older run.
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({'range': 'all', 'sort': 'newest'}),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_month_hdr_');
      final now = DateTime.now();
      final priorMonth = DateTime(
        now.month == 1 ? now.year - 1 : now.year,
        now.month == 1 ? 12 : now.month - 1,
        15,
      );
      final twoRuns = [
        Run(
          id: 'r-current',
          // Anchor to mid-month, not `now - 1 day`: on the 1st of a month
          // that subtraction rolls into the previous month and collides
          // with `priorMonth`, leaving a single header (wall-clock flake).
          startedAt: DateTime(now.year, now.month, 15),
          duration: const Duration(minutes: 25),
          distanceMetres: 5000,
          source: RunSource.app,
        ),
        Run(
          id: 'r-prior',
          startedAt: priorMonth,
          duration: const Duration(minutes: 25),
          distanceMetres: 5000,
          source: RunSource.app,
        ),
      ];
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(twoRuns, dir: _runsDir);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Exactly two month-section headers — one per distinct month.
      // The labels are uppercased inside `_MonthHeaderRow`. The exact
      // text varies with wall-clock month; assert the count by
      // looking for the `_MonthHeaderRow` widget shape directly via
      // its all-caps style would be brittle, so we walk Text widgets
      // and assert two short uppercase labels appear.
      // Cheap proxy: both run IDs render — i.e. the list works —
      // AND there are exactly 2 widgets in the list whose text matches
      // a typical month-header pattern (an all-caps month name
      // followed optionally by " YYYY").
      final monthHeaderRe = RegExp(r'^[A-Z]+( \d{4})?$');
      final headerCount = find
          .byWidgetPredicate((w) =>
              w is Text &&
              w.data != null &&
              monthHeaderRe.hasMatch(w.data!))
          .evaluate()
          .length;
      expect(headerCount, 2,
          reason: 'list must emit one section header per distinct month');
    });

    test('sync badge uses Badge.count + trailing padding so the label never overflows', () {
      // Reason: the badge sits in the rightmost AppBar action slot. With
      // a three-digit count ("150 unsynced"), `Badge(label: Text('$count'))`
      // clips against the screen edge. `Badge.count` caps at "99+" so the
      // label is at most three glyphs wide; the wrapping `Padding` keeps
      // the badge inside the AppBar's actions area. Source-level guard —
      // populating the store with 100+ runs to drive this through the
      // widget tree blew past the per-test timeout in CI.
      final source = File('lib/screens/runs_screen.dart').readAsStringSync();
      // The guard pins both pieces of the fix in place: a future refactor
      // that drops either one re-introduces the off-screen overflow.
      expect(
        source.contains('Badge.count('),
        isTrue,
        reason: 'Use Badge.count (caps at "99+") instead of Badge(label: Text(\$count)).',
      );
      expect(
        RegExp(r"Padding\(\s*padding:\s*const\s+EdgeInsets\.only\(right:\s*\d").hasMatch(source),
        isTrue,
        reason: 'Wrap the unsynced badge in a trailing Padding so it stays inside the AppBar.',
      );
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

    test('shouldShowLoadMore — date filter past oldest local hides cloud branch',
        () {
      // "Today" filter on a cache whose oldest run is yesterday: the
      // cloud cursor only fetches strictly older than oldestLocal, so no
      // cloud page can land inside [today, ∞). Hide instead of inviting
      // a tap that does nothing.
      final today = DateTime(2026, 5, 1);
      final yesterday = DateTime(2026, 4, 30, 8, 0);
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 1,
          remoteHasMore: true,
          apiSignedIn: true,
          filterCutoff: today,
          oldestLocalStartedAt: yesterday,
        ),
        isFalse,
      );
    });

    test('shouldShowLoadMore — date filter inside local window keeps cloud branch',
        () {
      // "Year" filter, oldest local is 30 days ago, cloud has older.
      // The cloud could still hold runs from earlier this year that we
      // haven't pulled — keep the button.
      final yearStart = DateTime(2026, 1, 1);
      final thirtyDaysAgo = DateTime(2026, 4, 1);
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 12,
          remoteHasMore: true,
          apiSignedIn: true,
          filterCutoff: yearStart,
          oldestLocalStartedAt: thirtyDaysAgo,
        ),
        isTrue,
      );
    });

    test('shouldShowLoadMore — null filterCutoff (all-time) keeps cloud branch',
        () {
      // Range = "all" sets filterCutoff to null; the predicate has
      // nothing to compare against, so it must not suppress the button.
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRunsLoadMore(
          visibleCount: 20,
          filteredCount: 20,
          remoteHasMore: true,
          apiSignedIn: true,
          filterCutoff: null,
          oldestLocalStartedAt: DateTime(2026, 4, 30),
        ),
        isTrue,
      );
    });

    testWidgets('shows only first page of cached runs + Load more button',
        (tester) async {
      // Pre-stage 30 runs on disk before the store boots — see
      // _seedRunFiles for the rationale (awaited file writes hang
      // pumpAndSettle in test). Pin the range filter to 'all' via
      // SharedPreferences so the visible count is independent of which
      // weekday CI runs on — the default 'this week' range clips runs
      // older than Monday 00:00 local and dropped half the synthetic
      // entries when CI ran early on a Monday morning (the synthetic
      // runs are 30 min apart × 30 entries = ~15 h, which crosses the
      // week boundary if "now" is < 15 h after Monday 00:00).
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({'range': 'all', 'sort': 'newest'}),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(30), dir: _runsDir);
      final routeStore = LocalRouteStore();
      final s = (runStore: runStore, routeStore: routeStore, prefs: prefs);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
          ),
        ),
      );
      // First pump = initial paint with defaults. Second pump = post-
      // hydration setState from _hydrateFilters resolves and the screen
      // rebuilds with the persisted 'all' range applied.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
      // See the sibling test above for why we hydrate range='all' here.
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({'range': 'all', 'sort': 'newest'}),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(30), dir: _runsDir);
      final routeStore = LocalRouteStore();
      final s = (runStore: runStore, routeStore: routeStore, prefs: prefs);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

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

  group('RunsScreen filter persistence', () {
    testWidgets('hydrates custom date range from SharedPreferences on mount',
        (tester) async {
      // Pre-seed the mock SharedPreferences with a custom-range filter
      // pinned to "yesterday" only. Then plant two runs — one yesterday
      // (in window) and one today (outside) — and verify the screen's
      // visible-count chip reflects the hydrated filter.
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterdayStart = today.subtract(const Duration(days: 1));
      final yesterdayEnd = today.subtract(const Duration(milliseconds: 1));

      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({
          'range': 'custom',
          'sort': 'newest',
          'customFromMs': yesterdayStart.millisecondsSinceEpoch,
          'customToMs': yesterdayEnd.millisecondsSinceEpoch,
        }),
      });

      final prefs = Preferences();
      await prefs.init();

      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      final runs = [
        Run(
          id: 'yesterday',
          startedAt: yesterdayStart.add(const Duration(hours: 8)),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          track: const [],
          source: RunSource.app,
        ),
        Run(
          id: 'today',
          startedAt: today.add(const Duration(hours: 8)),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          track: const [],
          source: RunSource.app,
        ),
      ];
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(runs, dir: _runsDir);
      final routeStore = LocalRouteStore();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      // First pump = initial paint with defaults. Second pump = post-
      // hydration setState from _hydrateFilters resolves and the screen
      // rebuilds with the persisted custom range applied.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Header chip reads "1 run" — the yesterday entry. The today entry
      // is filtered out by the upper cutoff.
      expect(find.text('1 run'), findsOneWidget);
    });

    testWidgets('ignores a malformed filter blob and keeps defaults',
        (tester) async {
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': '{not valid json',
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      // ignore: invalid_use_of_visible_for_testing_member
      final runStore = LocalRunStore()..debugSeed(_makeRuns(3), dir: _runsDir);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Default range = this week → all 3 seeded runs (anchored within
      // the past 90 minutes by _makeRuns) survive.
      expect(find.text('3 runs'), findsOneWidget);
    });
  });

  // ─── Manual-add → History sync ───────────────────────────────────
  //
  // Field report: "I added a run manually on the mobile app and it
  // is not showing in the history. It is showing on the dashboard
  // -> this week modal." The two surfaces share the same LocalRunStore,
  // so a divergence implies either (a) the listener-driven
  // _onStoreChanged path on RunsScreen is missing the save, or
  // (b) the filter on RunsScreen drops the new row that the dashboard
  // accepts. These tests pin both halves of the contract so neither
  // can quietly regress.

  group('RunsScreen ← LocalRunStore live updates', () {
    testWidgets(
        'a run saved via runStore.save AFTER mount appears in the list',
        (tester) async {
      final s = await _makeStores();
      // Start with an empty store so we can pin "the new run shows up"
      // unambiguously — no risk of confusing it with a seeded entry.
      await _pump(
        tester,
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Sanity: empty state visible.
      expect(find.text('No runs yet'), findsOneWidget);

      // Save a run shaped exactly like AddRunScreen produces: source
      // RunSource.app, metadata carrying activity_type='run' +
      // manual_entry=true, startedAt converted to UTC (mirrors
      // `_startedAt.toUtc()` in add_run_screen.dart#_save). This is
      // the exact path the field bug runs into.
      //
      // `runAsync` is required around `runStore.save` because the
      // underlying File.writeAsString uses the real dart:io event
      // loop, which the test scheduler doesn't pump under the
      // default fake-async clock. Without it, `await save(...)`
      // blocks forever and the test framework eventually times out.
      final now = DateTime.now();
      final manual = Run(
        id: 'manual-1',
        startedAt: DateTime(now.year, now.month, now.day, now.hour).toUtc(),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        metadata: const {
          'activity_type': 'run',
          'manual_entry': true,
          'title': 'Morning loop',
        },
      );
      await tester.runAsync(() => s.runStore.save(manual));
      // Listener-driven setState + a frame to settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The manually-saved run must materialise in the filtered list.
      // We assert via the summary chip (1 run total) — the exact row
      // text is brittle (depends on UnitFormat + month header), but
      // the count is invariant.
      expect(find.text('1 run'), findsOneWidget,
          reason: 'A manual save must propagate through the LocalRunStore '
              'listener into _filterAndSort on RunsScreen — the dashboard '
              'reads the same store and shows the run in This Week, so the '
              'history must agree.');
    });

    testWidgets(
        'manual run with default "this week" filter falls inside the range',
        (tester) async {
      // Pin the comparator semantics directly: a run.startedAt that
      // matches add_run_screen's defaults (today, top-of-hour, .toUtc())
      // must compare as >= weekStartLocal(now). If the comparator ever
      // regresses (e.g. someone swaps `isBefore` for a naive numeric
      // compare against a local timestamp), this test will fail.
      final s = await _makeStores();
      final now = DateTime.now();
      final manualLocal = DateTime(now.year, now.month, now.day, now.hour);
      // ignore: invalid_use_of_visible_for_testing_member
      s.runStore.debugSeed([
        Run(
          id: 'manual-1',
          startedAt: manualLocal.toUtc(),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          source: RunSource.app,
          metadata: const {'activity_type': 'run', 'manual_entry': true},
        ),
      ], dir: _runsDir!);
      await _pump(
        tester,
        runStore: s.runStore,
        routeStore: s.routeStore,
        prefs: s.prefs,
      );
      await tester.pump(const Duration(milliseconds: 50));
      // Default range = "this week". A run dated today must show.
      expect(find.text('1 run'), findsOneWidget);
    });

    testWidgets(
        'saving a Run while activity=Walk filter is sticky auto-clears the filter',
        (tester) async {
      // Reproduces the most likely field cause: SharedPreferences
      // restored `activity=walk` from a prior session; the user
      // adds a "Run" via the FAB; without the auto-clear the new
      // entry is hidden behind the "No runs match these filters"
      // empty state and the user reports "my run didn't save".
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({
          'range': 'week',
          'sort': 'newest',
          'activity': 'walk',
        }),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      final runStore = LocalRunStore();
      await runStore.init(overrideDirectory: _runsDir);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      // Drain SharedPreferences hydration + first listener tick that
      // seeds _previousRunIds.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Save a Run-typed entry — should not match the sticky Walk
      // filter, but the auto-clear must rescue the visibility.
      final now = DateTime.now();
      final manual = Run(
        id: 'manual-1',
        startedAt: DateTime(now.year, now.month, now.day, now.hour).toUtc(),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        metadata: const {
          'activity_type': 'run',
          'manual_entry': true,
        },
      );
      await tester.runAsync(() => runStore.save(manual));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The summary chip reflects 1 run — auto-clear worked.
      expect(find.text('1 run'), findsOneWidget,
          reason: 'A run that does NOT match the sticky filter must '
              'still surface — the screen auto-clears activity/source '
              'filters when a fresh save would otherwise be hidden.');
    });

    testWidgets(
        'auto-clear does NOT trigger when the new run already matches the filter',
        (tester) async {
      // Pin the inverse contract — if the user IS filtering by
      // activity=Run and they save a Run, the filter must stick.
      // Without this guard a refactor that always clears on save
      // would surprise users who set the filter intentionally.
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({
          'range': 'week',
          'sort': 'newest',
          'activity': 'run',
        }),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      final runStore = LocalRunStore();
      await runStore.init(overrideDirectory: _runsDir);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final now = DateTime.now();
      final manual = Run(
        id: 'manual-1',
        startedAt: DateTime(now.year, now.month, now.day, now.hour).toUtc(),
        duration: const Duration(minutes: 30),
        distanceMetres: 5000,
        source: RunSource.app,
        metadata: const {
          'activity_type': 'run',
          'manual_entry': true,
        },
      );
      await tester.runAsync(() => runStore.save(manual));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 1 run visible AND the filter chip remains on Run. We don't
      // assert chip presence (the chip rendering moves around), but
      // we DO check that the persisted SharedPreferences entry still
      // carries activity=run — proves we didn't reset it.
      expect(find.text('1 run'), findsOneWidget);
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('runs_filters_v1');
      expect(raw, isNotNull);
      final j = jsonDecode(raw!) as Map<String, dynamic>;
      expect(j['activity'], 'run',
          reason: 'A new run that ALREADY matches the active filter '
              'must not trigger the auto-clear — preserving the user\'s '
              "deliberate filter is more important than clearing it.");
    });

    testWidgets(
        'a saved run survives a SharedPreferences-restored "this week" filter',
        (tester) async {
      // Pin the specific scenario the user hit: SharedPreferences
      // restores the previously-picked range (the screen does this
      // in _hydrateFilters). If "this week" is the restored value,
      // the manual run must still pass. If a future refactor adds
      // a stricter default (e.g. "this hour"), or breaks the local-
      // time comparator, this fails.
      SharedPreferences.setMockInitialValues({
        'runs_filters_v1': jsonEncode({'range': 'week', 'sort': 'newest'}),
      });
      final prefs = Preferences();
      await prefs.init();
      _runsDir = Directory.systemTemp.createTempSync('runs_screen_test_');
      final runStore = LocalRunStore();
      await runStore.init(overrideDirectory: _runsDir);

      final now = DateTime.now();
      // ignore: invalid_use_of_visible_for_testing_member
      runStore.debugSeed([
        Run(
          id: 'manual-1',
          startedAt:
              DateTime(now.year, now.month, now.day, now.hour).toUtc(),
          duration: const Duration(minutes: 30),
          distanceMetres: 5000,
          source: RunSource.app,
          metadata: const {'activity_type': 'run', 'manual_entry': true},
        ),
      ], dir: _runsDir!);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunsScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: LocalRouteStore(),
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('1 run'), findsOneWidget);
    });
  });
}
