import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/preferences.dart';
import '../lib/screens/routes_screen.dart';

/// Signed-out fake — non-null so the api-gated Discover entries render,
/// null userId so no fetch paths fire.
class _FakeApi extends ApiClient {}

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

/// Routes named exactly as given, so a search / sort case can name them back.
List<cm.Route> _namedRoutes(List<String> names) {
  return [
    for (int i = 0; i < names.length; i++)
      cm.Route(
        id: 'route-${i.toString().padLeft(3, '0')}',
        userId: 'test-user',
        name: names[i],
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

Future<void> _pump(WidgetTester tester,
    {required Preferences prefs,
    ApiClient? api,
    LocalRouteStore? routeStore,
    double textScale = 1.0}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: RoutesScreen(
        apiClient: api,
        routeStore: routeStore ?? LocalRouteStore(),
        preferences: prefs,
      ),
    ),
  );
}

void main() {
  group('RoutesScreen — initial render', () {
    testWidgets('AppBar carries the "Routes" title', (tester) async {
      // Routes is a pushed full-screen destination (Fitness → Runs →
      // Routes), no longer a bottom-nav tab — the AppBar names it.
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Routes'), findsOneWidget);
    });

    testWidgets('renders the labelled Public-routes entry in the Discover strip',
        (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Public routes'),
          findsOneWidget);
    });

    testWidgets(
        'the Discover strip surfaces both heatmap entries when an api '
        'client is wired, and hides them when it is not', (tester) async {
      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs, api: _FakeApi());
      await tester.pump();
      // Community routes heatmap + the user's own run heatmap, both as
      // labelled buttons — the routes page is the single home of the
      // map/discovery entry points. Both labels carry their qualifier
      // since the siblings sit side by side.
      expect(find.widgetWithText(OutlinedButton, 'Routes heatmap'),
          findsOneWidget);
      expect(
          find.widgetWithText(OutlinedButton, 'Run heatmap'), findsOneWidget);

      await _pump(tester, prefs: prefs);
      await tester.pump();
      expect(find.widgetWithText(OutlinedButton, 'Routes heatmap'),
          findsNothing);
      expect(
          find.widgetWithText(OutlinedButton, 'Run heatmap'), findsNothing);
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
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
    testWidgets('the long-press hint is shown, then yields to the app bar',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      // A long press is the only route into multi-select, so it is announced
      // while there is something to select.
      expect(find.text(l10n.routesSelectionHint), findsOneWidget);

      await tester.longPress(find.text('Route 0'));
      await tester.pump();

      // Once selecting, the app bar carries the affordances and the hint is
      // spent — leaving it would restate a mode the user is already in.
      expect(find.text(l10n.routesSelectionHint), findsNothing);
    });

    testWidgets('no long-press hint when nothing on screen is selectable',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore();
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RoutesScreen(
          apiClient: null,
          routeStore: routeStore,
          preferences: prefs,
        ),
      ));
      await tester.pump();
      final l10n = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l10n.routesSelectionHint), findsNothing);
    });

    testWidgets('long-press on a route enters selection mode + shows banner',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        // ignore: invalid_use_of_visible_for_testing_member
        ..debugSeed(_makeRoutes(3));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
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

  group('RoutesScreen — narrow-width overflow (issue #666 V7)', () {
    testWidgets(
        'renders at 320 logical width with the Discover strip label bounded '
        'so a long localized label ellipsizes instead of striping',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final prefs = await _makePrefs();
      await _pump(tester, prefs: prefs);
      await tester.pump();

      expect(
        find.ancestor(
            of: find.text('Discover'), matching: find.byType(Expanded)),
        findsWidgets,
      );
    });
  });

  group('RoutesScreen — OS text scaling (issue #666 V12)', () {
    testWidgets(
        'the filter chip rail takes its height from the chips, not a literal '
        '40 px lane', (tester) async {
      final prefs = await _makePrefs();
      // The filter header is the first row of the populated list — the
      // zero-routes empty state renders instead of it.
      // ignore: invalid_use_of_visible_for_testing_member
      final store = LocalRouteStore()..debugSeed(_makeRoutes(1));

      await _pump(tester, prefs: prefs, routeStore: store);
      await tester.pump();
      final chip = find.byType(FilterChip).first;
      final small = tester.getSize(chip).height;
      // A Material chip's own tap target is 48; the old 40 px lane squeezed it.
      expect(small, greaterThanOrEqualTo(48));

      await _pump(tester, prefs: prefs, routeStore: store, textScale: 2.0);
      await tester.pump();
      // Pre-fix the chip measured exactly 40.0 here while needing 58, so its
      // label was cropped inside the rail.
      expect(tester.getSize(chip).height, greaterThan(small));
    });
  });

  // ── Search + sort fold (decisions § 1337) ─────────────────────────────
  //
  // Both used to run through `toLowerCase()`, whose answer differs between
  // this runtime and a browser's at 466 code points, and the `az` sort
  // additionally compared code units where web collated — two orderings that
  // disagree about 31.75 % of all pairs of Unicode letters. Both now go
  // through `catalogue_browse`'s generated fold, so the phone and the web
  // answer the same question the same way.
  group('RoutesScreen — search and sort fold', () {
    testWidgets('typing an unaccented query finds the accented route',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(['İstanbul Loop', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'istanbul');
      await tester.pump();

      // A browser's `toLowerCase` renders İ as i + a combining dot, so
      // `istanbul` did NOT match there while it did here. Folding makes the
      // two agree — and the assertion holds on either runtime.
      expect(find.text('İstanbul Loop'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);
    });

    testWidgets('the query folds accents, so zurich reaches Zürich',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(['Zürich Lakeside', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      await tester.enterText(find.byType(TextField).first, 'zurich');
      await tester.pump();

      expect(find.text('Zürich Lakeside'), findsOneWidget);
      expect(find.text('Riverside Way'), findsNothing);
    });

    testWidgets('A–Z orders on the folded name, not on raw code units',
        (tester) async {
      final prefs = await _makePrefs();
      // ignore: invalid_use_of_visible_for_testing_member
      final routeStore = LocalRouteStore()
        ..debugSeed(_namedRoutes(
            ['Zaragoza Loop', 'Åre Trail', 'Riverside Way']));
      await _pump(tester, prefs: prefs, routeStore: routeStore);
      await tester.pump();

      // Open the sort chip and pick A–Z.
      await tester.tap(find.text('Newest first'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('A–Z').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      double y(String name) => tester.getTopLeft(find.text(name)).dy;
      // Folded: "are trail" < "riverside way" < "zaragoza loop". A raw
      // code-unit order would put Å (U+00C5) after Z (U+005A) and end the
      // list with Åre — which is what this side used to do.
      expect(y('Åre Trail'), lessThan(y('Riverside Way')));
      expect(y('Riverside Way'), lessThan(y('Zaragoza Loop')));
    });
  });

}
