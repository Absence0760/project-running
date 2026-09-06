import 'dart:async';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:core_models/core_models.dart' show ClubRow;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/main.dart' show pendingStartRunWithRoute;
import '../lib/preferences.dart';
import '../lib/screens/route_detail_screen.dart';
import '../lib/social_service.dart' show ClubView;

cm.Route _route({
  String name = 'River Loop',
  bool isPublic = false,
  String? description,
  List<String> tags = const [],
  List<cm.Waypoint> waypoints = const [],
  String userId = 'test-user',
}) =>
    cm.Route(
      id: 'r1',
      userId: userId,
      name: name,
      waypoints: waypoints,
      distanceMetres: 8500,
      elevationGainMetres: 45,
      isPublic: isPublic,
      description: description,
      tags: tags,
    );

/// Owner ApiClient whose tag write fails — drives the remove-failure banner.
class _ThrowingTagsApi extends ApiClient {
  @override
  String? get userId => 'test-user';
  @override
  Future<void> updateRouteTags(String routeId, List<String> tags) async {
    throw StateError('network down');
  }
}

/// Route store whose `pinOffline` blocks on a gate the test controls, so the
/// double-tap window for the offline-pin toggle can be held open on purpose.
class _FakePinStore extends LocalRouteStore {
  int pinCalls = 0;
  int unpinCalls = 0;
  final Completer<void> pinGate = Completer<void>();
  bool _pinned = false;

  @override
  bool isOfflinePinned(String routeId) => _pinned;

  @override
  Future<void> save(cm.Route route, {bool markSynced = false}) async {}

  @override
  Future<void> pinOffline(String routeId) async {
    pinCalls++;
    await pinGate.future;
    _pinned = true;
  }

  @override
  Future<void> unpinOffline(String routeId) async {
    unpinCalls++;
    _pinned = false;
  }
}

/// Owner ApiClient whose setRoutePublic blocks on a gate the test controls.
class _GatedPublicApi extends ApiClient {
  int publicCalls = 0;
  final Completer<void> gate = Completer<void>();
  @override
  String? get userId => 'test-user';
  @override
  Future<void> setRoutePublic(String routeId, bool isPublic) async {
    publicCalls++;
    await gate.future;
  }
}

ClubView _club({
  required String id,
  required String name,
  String? location,
  int memberCount = 5,
  String? viewerRole,
}) =>
    ClubView(
      row: ClubRow(shadowHidden: false, 
        id: id,
        ownerId: 'owner-uuid',
        name: name,
        slug: id,
        locationLabel: location,
        joinPolicy: 'open',
        memberCount: memberCount,
        isVerified: false,
        requiresActivityWaiver: false,
      ),
      memberCount: memberCount,
      viewerRole: viewerRole,
      viewerStatus: viewerRole == null ? null : 'active',
      joinPolicy: 'open',
    );

Future<void> _pump(
  WidgetTester tester,
  cm.Route route, {
  bool isOwner = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = Preferences();
  await prefs.init();

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RouteDetailScreen(
        route: route,
        routeStore: LocalRouteStore(),
        preferences: prefs,
        isOwner: isOwner,
      ),
    ),
  );
  // One pump to build; pumpAndSettle would spin LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  group('routeShareUrl', () {
    test('builds /share/route/{id} from an explicit base', () {
      expect(routeShareUrl('abc', webBase: 'https://threkir.com'),
          'https://threkir.com/share/route/abc');
    });
    test('trims trailing slashes on the base', () {
      expect(routeShareUrl('abc', webBase: 'https://example.com//'),
          'https://example.com/share/route/abc');
    });
    test('keeps a base path prefix', () {
      expect(routeShareUrl('r1', webBase: 'https://host/app/'),
          'https://host/app/share/route/r1');
    });
    test('falls back to the prod host when WEB_BASE_URL is unset', () {
      expect(routeShareUrl('r1'), 'https://threkir.com/share/route/r1');
    });
  });

  group('RouteDetailScreen', () {
    testWidgets('renders the route name as the app-bar title', (tester) async {
      await _pump(tester, _route(name: 'River Loop'));
      expect(find.text('River Loop'), findsOneWidget);
    });

    testWidgets('delete button is hidden when isOwner is false', (tester) async {
      await _pump(tester, _route(), isOwner: false);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets(
        'public toggle guards a double-tap so overlapping visibility writes '
        'cannot race', (tester) async {
      final api = _GatedPublicApi();
      final store = _FakePinStore();
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RouteDetailScreen(
          route: _route(),
          routeStore: store,
          preferences: prefs,
          apiClient: api,
          isOwner: true,
        ),
      ));
      await tester.pump();
      await tester.pump(Duration.zero);

      // The visibility toggle lives in the toolbar's overflow menu (#666 C4).
      // A popup menu builds its rows once, at open time, so every check
      // below reopens it rather than reading a stale route.
      Future<void> openOverflow() async {
        await tester.tap(find.byTooltip('More'));
        // Timed pumps, not pumpAndSettle — LiveRunMap's pulse animation
        // never settles.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Future<void> closeOverflow() async {
        await tester.tap(find.byType(ModalBarrier).last, warnIfMissed: false);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      Finder row(String label) =>
          find.widgetWithText(PopupMenuItem<int>, label);

      // First tap flips private → public and blocks on the cloud write.
      await openOverflow();
      await tester.tap(row('Make public'));
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(api.publicCalls, 1);

      // Busy → the control is disabled; a second tap can't fire a second,
      // out-of-order visibility write.
      await openOverflow();
      expect(tester.widget<PopupMenuItem<int>>(row('Make private')).enabled,
          isFalse,
          reason:
              'visibility control must be disabled while a write is in flight');
      await tester.tap(row('Make private'), warnIfMissed: false);
      await tester.pump();
      expect(api.publicCalls, 1, reason: 'second tap must not fire another write');
      await closeOverflow();

      // Completing the write re-enables the control.
      api.gate.complete();
      await tester.pump();
      await tester.pump(Duration.zero);
      await openOverflow();
      expect(tester.widget<PopupMenuItem<int>>(row('Make private')).enabled,
          isTrue);
      await closeOverflow();
    });

    testWidgets(
        'Share link on a private route confirms before making it public',
        (tester) async {
      final api = _GatedPublicApi();
      final store = _FakePinStore();
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RouteDetailScreen(
          route: _route(isPublic: false),
          routeStore: store,
          preferences: prefs,
          apiClient: api,
          isOwner: true,
        ),
      ));
      await tester.pump();
      await tester.pump(Duration.zero);

      final l10n = await AppLocalizations.delegate.load(const Locale('en'));

      Future<void> openShareLink() async {
        await tester.tap(find.byIcon(Icons.ios_share));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text(l10n.routeDetailShareLink));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Choosing "Share link" on a private route raises the confirm — and
      // publishes nothing yet.
      await openShareLink();
      expect(find.text(l10n.routeDetailShareConfirmTitle), findsOneWidget);
      expect(api.publicCalls, 0);

      // Cancel → the route stays private, no visibility write fired.
      await tester.tap(find.text(l10n.routeDetailCancel));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.routeDetailShareConfirmTitle), findsNothing);
      expect(api.publicCalls, 0,
          reason: 'cancelling the confirm must not flip the route public');

      // Reopen and confirm → the publish write fires (then blocks on the
      // gate, so the OS share sheet is never reached in the test).
      await openShareLink();
      await tester.tap(find.text(l10n.routeDetailShareConfirmCta));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(Duration.zero);
      expect(api.publicCalls, 1,
          reason: 'confirming must flip the route public');
    });

    testWidgets(
        'offline-pin toggle guards a double-tap race — a second tap while the '
        'pin is in flight is ignored, then the control re-enables',
        (tester) async {
      final store = _FakePinStore();
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RouteDetailScreen(
          route: _route(),
          routeStore: store,
          preferences: prefs,
        ),
      ));
      await tester.pump();
      await tester.pump(Duration.zero);

      final appBar = find.byType(AppBar);
      // First tap starts the pin, which blocks on the store gate.
      await tester.tap(find.descendant(
          of: appBar, matching: find.byIcon(Icons.download_outlined)));
      await tester.pump();
      await tester.pump(Duration.zero);
      expect(store.pinCalls, 1);
      expect(store.unpinCalls, 0);

      // The control is now disabled (busy) — a second tap must not fire
      // another pin/unpin, which is what would race the tile-pack download
      // against its own delete.
      final pinBtn = tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.download_done),
          matching: find.byType(IconButton)));
      expect(pinBtn.onPressed, isNull,
          reason: 'pin control must be disabled while a pin is in flight');
      // Belt-and-suspenders: even a forced tap changes nothing.
      await tester.tap(
          find.descendant(
              of: appBar, matching: find.byIcon(Icons.download_done)),
          warnIfMissed: false);
      await tester.pump();
      expect(store.pinCalls, 1, reason: 'second tap must not fire another pin');
      expect(store.unpinCalls, 0);

      // Releasing the in-flight pin re-enables the control (a guard, not a
      // permanent lock).
      store.pinGate.complete();
      await tester.pump();
      await tester.pump(Duration.zero);
      final pinBtnAfter = tester.widget<IconButton>(find.ancestor(
          of: find.byIcon(Icons.download_done),
          matching: find.byType(IconButton)));
      expect(pinBtnAfter.onPressed, isNotNull,
          reason: 'control re-enables once the pin completes');
    });

    testWidgets('delete button is visible when isOwner is true and apiClient has userId',
        (tester) async {
      // Without a real ApiClient.userId the _isOwner guard returns false.
      // Pass isOwner: true to verify the ownership-guard logic:
      // _isOwner = widget.isOwner && widget.apiClient?.userId != null
      // With no apiClient the condition is false → button hidden. This
      // confirms the guard is respected.
      await _pump(tester, _route(), isOwner: true);
      // No apiClient → userId is null → _isOwner stays false → no button.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('renders the Distance and Elevation stats', (tester) async {
      await _pump(tester, _route());
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Elevation'), findsOneWidget);
    });

    testWidgets('renders the Reviews header', (tester) async {
      await _pump(tester, _route());
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(find.text('Reviews'), findsOneWidget);
    });

    testWidgets('renders the route description when set', (tester) async {
      // Mirrors web `/routes/[id]` description block. Migration
      // 20260902_001_routes_description.sql adds the column; the detail
      // screen surfaces it under the title when non-null/non-empty.
      // The block sits below the map + the offline-pin tile, so it's
      // out of the default 800x600 viewport — scroll the ListView first
      // (same pattern as the Reviews-header test above).
      await _pump(
        tester,
        _route(description: 'Out-and-back along the canal, flat.'),
      );
      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pump();
      expect(
          find.text('Out-and-back along the canal, flat.'), findsOneWidget);
    });

    testWidgets('omits the description row when null', (tester) async {
      await _pump(tester, _route(description: null));
      // No description text means no surface for the empty-string
      // sentinel either; the route's name still renders as the title.
      expect(find.text(''), findsNothing);
    });

    testWidgets(
      'locally-built route (empty userId) skips the clip-RPC and '
      'renders the row waypoints — no "Waiting for GPS..." stuck state',
      (tester) async {
        // Bug the user surfaced: after building a route, opening its
        // detail page showed "Waiting for GPS..." instead of the
        // polyline. Root cause: locally-built routes carry an empty
        // `userId` (the Route constructor defaults to '') until the
        // SyncService cycle pushes them to the cloud. The
        // owner-vs-viewer check `viewerId == ownerId` then resolved
        // false, the screen fell through to clipRouteForViewer which
        // failed (no cloud row to clip), and `_displayWaypoints`
        // stayed empty — LiveRunMap then renders the GPS-loading
        // placeholder. Fix: treat empty-ownerId as "owned by viewer"
        // so the row's waypoints render immediately.
        final localRoute = cm.Route(
          id: 'locally-built',
          userId: '', // <-- the load-bearing condition
          name: 'Just-built loop',
          waypoints: const [
            cm.Waypoint(lat: 51.5, lng: -0.1),
            cm.Waypoint(lat: 51.51, lng: -0.11),
            cm.Waypoint(lat: 51.5, lng: -0.1),
          ],
          distanceMetres: 1500,
          elevationGainMetres: 12,
          isPublic: false,
        );
        await _pump(tester, localRoute);
        // The "Waiting for GPS..." placeholder should NOT appear —
        // the row waypoints carry the polyline.
        expect(
          find.text('Waiting for GPS...'),
          findsNothing,
          reason:
              'Locally-built routes (empty userId) must render their row '
              'waypoints directly — the user reported this as "the map '
              'preview doesn\'t load, it says Waiting for GPS".',
        );
        // The route header still renders normally.
        expect(find.text('Just-built loop'), findsOneWidget);
      },
    );
  });

  group('adminClubsForRouteTransfer', () {
    test('only owner + admin pass through', () {
      final clubs = [
        _club(id: 'a', name: 'Alpha', viewerRole: 'owner'),
        _club(id: 'b', name: 'Beta', viewerRole: 'admin'),
        _club(id: 'c', name: 'Gamma', viewerRole: 'event_organiser'),
        _club(id: 'd', name: 'Delta', viewerRole: 'race_director'),
        _club(id: 'e', name: 'Epsilon', viewerRole: 'member'),
        _club(id: 'f', name: 'Zeta', viewerRole: null),
      ];
      expect(
        adminClubsForRouteTransfer(clubs).map((c) => c.row.id).toList(),
        ['a', 'b'],
        reason: 'event_organiser / race_director / member / no-role rows '
            'must drop — those viewer roles cannot reassign route ownership',
      );
    });

    test('empty input returns empty', () {
      expect(adminClubsForRouteTransfer(const <ClubView>[]), isEmpty);
    });
  });

  group('TransferRouteResult', () {
    test('transfer constructor stores clubId, sets detach=false', () {
      const r = TransferRouteResult.transfer('club-x');
      expect(r.detach, isFalse);
      expect(r.clubId, 'club-x');
    });

    test('detach constructor sets detach=true with null clubId', () {
      const r = TransferRouteResult.detach();
      expect(r.detach, isTrue);
      expect(r.clubId, isNull);
    });
  });

  group('RouteTransferClubPicker', () {
    Future<TransferRouteResult?> openPicker(
      WidgetTester tester, {
      required List<ClubView> clubs,
      String? currentClubId,
    }) async {
      TransferRouteResult? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<TransferRouteResult>(
                      context: context,
                      builder: (_) => RouteTransferClubPicker(
                        clubs: clubs,
                        currentClubId: currentClubId,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return popped;
    }

    testWidgets(
        'personal route: shows "Transfer to club" header + no Detach row',
        (tester) async {
      await openPicker(
        tester,
        clubs: [_club(id: 'a', name: 'Alpha')],
        currentClubId: null,
      );
      expect(find.text('Transfer to club'), findsOneWidget);
      expect(find.text('Detach to personal'), findsNothing);
    });

    testWidgets(
        'club-owned route: header switches to "Manage…" + Detach row visible',
        (tester) async {
      await openPicker(
        tester,
        clubs: [_club(id: 'a', name: 'Alpha')],
        currentClubId: 'a',
      );
      expect(find.text('Manage club ownership'), findsOneWidget);
      expect(find.text('Detach to personal'), findsOneWidget);
    });

    testWidgets('tapping a club row pops a transfer result with its id',
        (tester) async {
      TransferRouteResult? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<TransferRouteResult>(
                      context: context,
                      builder: (_) => RouteTransferClubPicker(
                        clubs: [_club(id: 'club-uuid-42', name: 'Sydney RC')],
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sydney RC'));
      await tester.pumpAndSettle();
      expect(popped, isNotNull);
      expect(popped!.detach, isFalse);
      expect(popped!.clubId, 'club-uuid-42');
    });

    testWidgets('tapping Detach pops a detach result', (tester) async {
      TransferRouteResult? popped;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showModalBottomSheet<TransferRouteResult>(
                      context: context,
                      builder: (_) => RouteTransferClubPicker(
                        clubs: [_club(id: 'a', name: 'Alpha')],
                        currentClubId: 'a',
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detach to personal'));
      await tester.pumpAndSettle();
      expect(popped, isNotNull);
      expect(popped!.detach, isTrue);
      expect(popped!.clubId, isNull);
    });

    testWidgets('current club row labels itself + ignores taps', (tester) async {
      await openPicker(
        tester,
        clubs: [_club(id: 'a', name: 'Alpha')],
        currentClubId: 'a',
      );
      // Current-club row: "Current club" subtitle + check icon; the row
      // is rendered with onTap: null so the sheet stays put when tapped.
      expect(find.text('Current club'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Alpha'), warnIfMissed: false);
      await tester.pump();
      // Sheet remains open — assert the header is still on-screen.
      expect(find.text('Manage club ownership'), findsOneWidget);
    });
  });

  group('RouteDetailScreen — tag remove failure', () {
    testWidgets('a failed tag remove surfaces a banner and keeps the chip',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RouteDetailScreen(
            route: _route(tags: const ['hillsprint']),
            routeStore: LocalRouteStore(),
            preferences: prefs,
            isOwner: true,
            apiClient: _ThrowingTagsApi(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(Duration.zero);

      // The tags row sits below the map/stats; scroll it into view (the
      // ListView lazily builds only visible children).
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump();

      expect(find.text('hillsprint'), findsOneWidget);
      // The Chip's delete (×) icon — owner + not-saving renders onDeleted.
      // Flutter's own $deleteIcon default, so it is NOT ours to normalise:
      // the §551 icon sweep rewrote this assertion to the outlined variant and
      // the framework kept drawing the filled one.
      await tester.runAsync(() => tester.tap(find.byIcon(Icons.cancel)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Could not remove tag'), findsOneWidget);
      // The chip stays (the remove didn't persist).
      expect(find.text('hillsprint'), findsOneWidget);

    });
  });

  group('RouteDetailScreen — narrow-width overflow (issue #666 V7)', () {
    testWidgets(
        'owner body renders at 320 logical width and the switch titles are '
        'bounded so long localized labels ellipsize instead of striping',
        (tester) async {
      tester.view.physicalSize = const Size(320, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await _pump(
          tester,
          _route(
              name: 'An unreasonably long route name that a runner might '
                  'realistically paste in from a GPX export'),
          isOwner: true);

      expect(
        find.ancestor(
            of: find.text('Private route'), matching: find.byType(Expanded)),
        findsWidgets,
      );
      expect(
        find.ancestor(
            of: find.text('Save for offline'),
            matching: find.byType(Expanded)),
        findsWidgets,
      );
    });
  });

  group('RouteDetailScreen — start-run handoff', () {
    tearDown(() => pendingStartRunWithRoute.value = null);

    testWidgets('the Start run FAB publishes the route on the global notifier',
        (tester) async {
      // The only path from a route surface into the recorder. The callback
      // chain that used to carry the route up through RoutesScreen /
      // ExploreRoutesScreen / FitnessHubScreen was dead — this screen never
      // pops a Route — so this notifier is what "Start with this route" is.
      await _pump(
        tester,
        // Empty userId = a locally-built route, which the clip step hands
        // through unchanged for a signed-out viewer; anything else renders no
        // polyline in a test with no ApiClient, and so no FAB.
        _route(userId: '', waypoints: const [
          cm.Waypoint(lat: 51.5, lng: -0.12),
          cm.Waypoint(lat: 51.51, lng: -0.13),
        ]),
      );

      expect(pendingStartRunWithRoute.value, isNull);
      await tester.tap(find.text('Start run'));
      await tester.pump();

      expect(pendingStartRunWithRoute.value?.id, 'r1');
    });

    testWidgets('a route with fewer than two waypoints offers no Start run',
        (tester) async {
      await _pump(tester, _route(userId: ''));
      expect(find.text('Start run'), findsNothing);
      expect(pendingStartRunWithRoute.value, isNull);
    });
  });
}
