import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';

List<cm.Route> _makeRoutes(int count) {
  return [
    for (int i = 0; i < count; i++)
      cm.Route(
        id: 'route-${i.toString().padLeft(3, '0')}',
        userId: 'test-user',
        name: 'Route $i',
        waypoints: const [
          cm.Waypoint(lat: 51.5, lng: -0.12),
          cm.Waypoint(lat: 51.51, lng: -0.13),
        ],
        distanceMetres: 5000,
        elevationGainMetres: 50,
      ),
  ];
}

Future<Preferences> _makePrefs() async {
  SharedPreferences.setMockInitialValues({});
  final p = Preferences();
  await p.init();
  return p;
}

Future<void> _pump(WidgetTester tester, {required Preferences prefs}) {
  return tester.pumpWidget(
    MaterialApp(
      home: RoutesScreen(
        apiClient: null,
        routeStore: LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  group('RoutesScreen — initial render', () {
    testWidgets('AppBar carries no "Routes" title (bottom-nav labels suffice)',
        (tester) async {
      // Bottom-nav already labels this tab "Routes". Pin the absence
      // of a duplicate AppBar title.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      expect(appBar.title, isNull);
    });

    testWidgets('renders the Explore action in the app bar',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.explore), findsOneWidget);
    });

    testWidgets('hides the cloud-sync icon when apiClient is null',
        (tester) async {
      // Reason: without a signed-in user the cloud_download icon must
      // not appear — there is nothing to sync.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byIcon(Icons.cloud_download), findsNothing);
    });

    testWidgets('renders the Import FAB with the upload icon',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(FloatingActionButton), findsOneWidget);
      // The empty-state hint now ALSO surfaces an "Import" label
      // inline (matching the FAB) so a first-time user can pair
      // the verbal CTA with the visual button. There are
      // therefore two "Import" texts on an empty screen — one in
      // the FAB, one in the hint row.
      expect(find.text('Import'), findsAtLeastNWidgets(1));
      expect(find.byIcon(Icons.upload_file), findsAtLeastNWidgets(1));
    });

    testWidgets('shows the empty state when there are no routes',
        (tester) async {
      // Empty-state copy now mentions BOTH the Build affordance and
      // the Import affordance so a first-time user finds both
      // FABs. The original copy said "Tap Import to add a GPX
      // or KML file" — Build wasn't surfaced at all, even though
      // it's the canonical "create from scratch" path on this
      // screen.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.text('No routes yet'), findsOneWidget);
      // Match the new copy.
      expect(
        find.textContaining('Tap Build to draw a route'),
        findsOneWidget,
      );
      expect(find.textContaining('Import a GPX'), findsOneWidget);
    });
  });

  group('RoutesScreen — per-card row polish', () {
    // Polish iteration after the original chip-pill strip — the
    // user noted the routes cards were visibly taller than the
    // History tab's run cards. Subtitle is now a single line
    // (`distance · elevation`) matching runs' `date · duration`,
    // and the state badges moved into the trailing row + a small
    // title-prefix glyph for public routes. Tests here pin the
    // new inline shape.
    testWidgets(
      'unsynced (locally-built) routes show the cloud-upload glyph '
      'in the trailing row',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // Seed WITHOUT marking synced — these are local-only.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1), markSynced: false);
        await tester.pumpWidget(
          MaterialApp(
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        // Inline glyph + tooltip — single-line row, no subtitle bloat.
        expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
        expect(find.byTooltip('Queued to sync'), findsOneWidget);
      },
    );

    testWidgets(
      'synced routes do NOT show the cloud-upload glyph',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // debugSeed defaults to markSynced=true.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.cloud_upload_outlined), findsNothing);
      },
    );

    testWidgets(
      'public routes show the globe glyph as a title prefix',
      (tester) async {
        final prefs = await _makePrefs();
        final publicRoute = cm.Route(
          id: 'public-route-1',
          userId: 'test-user',
          name: 'Open to all',
          waypoints: const [
            cm.Waypoint(lat: 51.5, lng: -0.12),
            cm.Waypoint(lat: 51.51, lng: -0.13),
          ],
          distanceMetres: 5000,
          elevationGainMetres: 50,
          isPublic: true,
        );
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed([publicRoute]);
        await tester.pumpWidget(
          MaterialApp(
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.public), findsOneWidget);
      },
    );

    testWidgets(
      'private routes do NOT show the globe glyph — keeps the '
      'title clean on the default-case route',
      (tester) async {
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // _makeRoutes defaults to isPublic=false.
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        expect(find.byIcon(Icons.public), findsNothing);
      },
    );

    testWidgets(
      'route subtitle is a single line (distance · elevation) — '
      'matches the History tab card height',
      (tester) async {
        // Pre-fix the routes-card subtitle had a two-row Column
        // (distance line + Wrap badge chips below) which made the
        // card visibly taller than the History tab's run-card.
        // Both are now single-line.
        final prefs = await _makePrefs();
        // ignore: invalid_use_of_visible_for_testing_member
        final routeStore = LocalRouteStore()
          // ignore: invalid_use_of_visible_for_testing_member
          ..debugSeed(_makeRoutes(1));
        await tester.pumpWidget(
          MaterialApp(
            home: RoutesScreen(
              apiClient: null,
              routeStore: routeStore,
              preferences: prefs,
            ),
          ),
        );
        await tester.pump();
        // 5 km / 50 m gain — pinned in `_makeRoutes`. Subtitle
        // text contains both pieces of metadata in the same Text.
        expect(
          find.textContaining('5.00 km'),
          findsOneWidget,
        );
        expect(
          find.textContaining('50 m ↑'),
          findsOneWidget,
        );
      },
    );
  });

  group('RoutesScreen pagination', () {
    test('shouldShowRoutesLoadMore — local rows beyond visibleCount', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 25,
          remoteHasMore: false,
          apiSignedIn: false,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + signed-in cloud', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: true,
        ),
        isTrue,
      );
    });

    test('shouldShowRoutesLoadMore — exhausted local + cloud says done', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: false,
          apiSignedIn: true,
        ),
        isFalse,
      );
    });

    test('shouldShowRoutesLoadMore — signed out, no local extras', () {
      expect(
        // ignore: invalid_use_of_visible_for_testing_member
        shouldShowRoutesLoadMore(
          visibleCount: 20,
          totalCount: 20,
          remoteHasMore: true,
          apiSignedIn: false,
        ),
        isFalse,
      );
    });

    testWidgets('shows first page + Load more when 25 routes cached',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      // First page = 20 routes; remaining 5 hidden behind the footer.
      // ListView.builder is lazy; scroll to materialise the footer.
      await tester.scrollUntilVisible(
        find.text('Load 20 more'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Load 20 more'), findsOneWidget);
    });

    testWidgets('Load more hidden when fewer routes than page size',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(5));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Load 20 more'), findsNothing);
    });

    testWidgets('tapping Load more reveals the next local page',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()..debugSeed(_makeRoutes(25));
      await tester.pumpWidget(
        MaterialApp(
          home: RoutesScreen(
            apiClient: null,
            routeStore: routeStore,
            preferences: prefs,
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
      // ensureVisible — the route-cards are taller after the
      // polish round (96×56 thumbnail vs the old 72×40), so the
      // load-more footer drifted a few pixels past the 600-px test
      // viewport. ensureVisible re-anchors the scroll so the tap
      // offset lands inside the renderbox.
      await tester.ensureVisible(find.text('Load 20 more'));
      await tester.pump();
      await tester.tap(find.text('Load 20 more'));
      await tester.pump();

      // 25 ≤ 40 (next page) + apiClient null → no further button.
      expect(find.text('Load 20 more'), findsNothing);
    });
  });

  group('RoutesScreen — selection mode (bulk delete)', () {
    testWidgets('long-press on a route enters selection mode + shows banner',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      // Pre-state: no selection banner.
      expect(find.textContaining(' selected'), findsNothing);

      await tester.longPress(find.text('Route 0'));
      await tester.pump();

      expect(find.text('1 selected'), findsOneWidget);
      // Banner controls — Cancel, Select all, Delete.
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byIcon(Icons.select_all), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
    });

    testWidgets('tap on another route in selection mode adds to the selection',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      await tester.tap(find.text('Route 1'));
      await tester.pump();

      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('Cancel button exits selection mode', (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(2));
      await tester.pumpWidget(MaterialApp(
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      expect(find.text('1 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(find.textContaining(' selected'), findsNothing);
    });

    testWidgets(
        'Delete button shows a pluralised confirm dialog; Cancel keeps the rows',
        (tester) async {
      // We exercise the UI plumbing through the dialog. The actual
      // disk-write path of `routeStore.deleteMany` is covered by the
      // local_route_store_test suite; mixing the two here forces us
      // to drive the showTopBanner Timer + dialog dismiss animation
      // which the flutter_test runner can't drain cleanly with a
      // ChangeNotifier overlay + ScaffoldMessenger banner stacked on
      // top. The Cancel branch covers the UI contract; the Confirm
      // branch is exercised via the store-level deleteMany tests.
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();

      await tester.longPress(find.text('Route 0'));
      await tester.pump();
      await tester.tap(find.text('Route 1'));
      await tester.pump();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();

      // Confirm dialog title — pluralised against the selection count.
      expect(find.text('Delete 2 routes?'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Cancel keeps everything in the store and exits the dialog.
      expect(routeStore.routes, hasLength(3));
      expect(find.text('Delete 2 routes?'), findsNothing);
    });
  });
}
