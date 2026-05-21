import 'dart:convert';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, Supabase;

import '../lib/local_route_store.dart';
import '../lib/route_overlap.dart';
import '../lib/screens/route_builder_screen.dart';

class _FakePathProvider extends PathProviderPlatform with MockPlatformInterfaceMixin {
  final Directory _tmp;
  _FakePathProvider(this._tmp);
  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp.path;
  @override
  Future<String?> getApplicationSupportPath() async => _tmp.path;
  @override
  Future<String?> getTemporaryPath() async => _tmp.path;
}

Future<String> _stubOsrm(Uri url) async {
  if (url.path.contains('/nearest/')) {
    final segs = url.path.split('/');
    final coord = segs.last.split(',');
    final lng = double.parse(coord[0]);
    final lat = double.parse(coord[1]);
    return jsonEncode({
      'code': 'Ok',
      'waypoints': [
        {'location': [lng, lat]},
      ],
    });
  }
  final segs = url.path.split('/');
  final pairs = segs.last.split(';');
  final coords = [
    for (final pair in pairs)
      [
        double.parse(pair.split(',')[0]),
        double.parse(pair.split(',')[1]),
      ],
  ];
  final dist = (pairs.length - 1) * 100.0;
  return jsonEncode({
    'code': 'Ok',
    'routes': [
      {
        'distance': dist,
        'geometry': {'coordinates': coords},
      },
    ],
  });
}

Future<String> _stubElev(Uri url) async {
  // open-meteo response with one entry per lat point.
  final lats = (url.queryParameters['latitude'] ?? '').split(',');
  return jsonEncode({
    'elevation': [for (final _ in lats) 400.0],
  });
}

Future<String> _stubGeocoding(Uri url) async {
  // Return a single canned result.
  return jsonEncode({
    'features': [
      {
        'place_name': 'London, United Kingdom',
        'center': [-0.1278, 51.5074],
      },
    ],
  });
}

Future<Position> _stubLocate() async {
  return Position(
    latitude: 51.5074,
    longitude: -0.1278,
    timestamp: DateTime.now(),
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

// One-time Supabase bootstrap shared across this test file. Mirrors
// the pattern in coach_screen_test.dart / feed_screen_test.dart —
// initialise the SDK with placeholder URL + anon key so `ApiClient()`
// construction passes its `isInitialized` probe. The widget tree never
// makes a real network call (it uses `saveRouteFn` injection), so the
// loopback URL is fine.
bool _supabaseReady = false;
Future<void> _ensureSupabase() async {
  if (_supabaseReady) return;
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'http://127.0.0.1:54321',
    anonKey: 'eyJ.local.test',
  );
  _supabaseReady = true;
}

void main() {
  late Directory tmpDir;

  setUpAll(() async {
    dotenv.loadFromString(isOptional: true);
    await _ensureSupabase();
  });

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('rb_screen_test_');
    PathProviderPlatform.instance = _FakePathProvider(tmpDir);
  });

  tearDown(() {
    try {
      tmpDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Future<LocalRouteStore> _store() async {
    final s = LocalRouteStore();
    await s.init(overrideDirectory: Directory(p.join(tmpDir.path, 'routes')));
    return s;
  }

  Future<void> _pumpScreen(WidgetTester tester, LocalRouteStore store) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 800,
          child: RouteBuilderScreen(
            // The widget tree doesn't call any ApiClient methods —
            // the save path is intercepted by injecting `saveRouteFn`.
            // `_ensureSupabase` (setUpAll) has booted the SDK so the
            // `ApiClient.isInitialized` probe passes.
            apiClient: ApiClient(),
            routeStore: store,
            osrmFetcher: _stubOsrm,
            elevationFetcher: _stubElev,
            geocodingFetcher: _stubGeocoding,
            locateFn: _stubLocate,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(Duration.zero);
  }

  testWidgets('initial state — "Tap the map" hint, Save disabled',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    // Hint suffixes the current routing mode (Trail/Road/Straight)
    // so flipping the toggle gives immediate feedback even before
    // the user places two waypoints. Default mode is Trail.
    expect(
      find.textContaining('Tap the map to place waypoints'),
      findsOneWidget,
    );
    expect(find.textContaining('Trail'), findsAtLeastNWidgets(1));
    final save = find.widgetWithText(TextButton, 'Save');
    expect(save, findsOneWidget);
    expect(tester.widget<TextButton>(save).onPressed, isNull);
  });

  testWidgets('AppBar hosts the place-search field + locate FAB',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Search places…'), findsOneWidget);
    expect(find.byIcon(Icons.my_location), findsOneWidget);
  });

  testWidgets('mode toggle has Trail / Road / Straight segments',
      (tester) async {
    final store = await _store();
    await _pumpScreen(tester, store);
    expect(find.text('Trail'), findsOneWidget);
    expect(find.text('Road'), findsOneWidget);
    expect(find.text('Straight'), findsOneWidget);
  });

  group('formatSaveRouteError', () {
    // Pure-function unit coverage for the catch path in `_save`. The
    // widget tree itself is hard to drive (real map interactions),
    // so the catch logic was hoisted into this helper specifically
    // for testability. Pairs with the rate-limit arch guard in
    // architecture_guards_test.dart.
    test('rate-limit P0001 → friendly "creating routes too quickly"', () {
      final msg = formatSaveRouteError(PostgrestException(
        message: 'rate limit exceeded for create_route, retry in 1234s',
        code: 'P0001',
      ));
      expect(
        msg,
        "You're creating routes too quickly — please wait 21 minutes and try again.",
      );
    });

    test('rate-limit P0001 on the clubs bucket still works (bucket-aware verb)', () {
      // Defensive: if a future migration adds another bucket like
      // create_event, the helper's unknown-bucket fallback kicks in.
      // We sanity-check that the bucket parameter flows through.
      final msg = formatSaveRouteError(PostgrestException(
        message: 'rate limit exceeded for create_club, retry in 42s',
        code: 'P0001',
      ));
      expect(msg, contains('creating clubs too quickly'));
    });

    test('RLS denial (42501) surfaces verbatim — debugging info preserved',
        () {
      final msg = formatSaveRouteError(PostgrestException(
        message: 'permission denied for table routes',
        code: '42501',
      ));
      expect(msg, 'Save failed: PostgrestException(message: '
          'permission denied for table routes, code: 42501, '
          'details: null, hint: null)');
      expect(msg, isNot(contains('too quickly')));
    });

    test('non-PostgrestException (network etc.) surfaces verbatim', () {
      final msg = formatSaveRouteError(Exception('connection refused'));
      expect(msg, 'Save failed: Exception: connection refused');
    });

    test('a non-rate-limit P0001 still surfaces verbatim', () {
      // The helper is strict about both the SQLSTATE AND the message
      // format. A P0001 raised by some other trigger with a different
      // shape must NOT pretend to be the rate-limit one.
      final msg = formatSaveRouteError(PostgrestException(
        message: 'some other trigger said no',
        code: 'P0001',
      ));
      expect(msg, contains('Save failed:'));
      expect(msg, contains('some other trigger said no'));
      expect(msg, isNot(contains('too quickly')));
    });

    test(
        'LateInitializationError → friendly "can\'t reach the server" '
        'message (defence against the Supabase SDK\'s late client field)',
        () {
      // Reproduces the exact symptom of the reported bug:
      //   "Save Failed: LateInitializationError: Field 'client' has
      //    not been initialized"
      // The defence is `formatSaveRouteError`; the primary fix is the
      // `ApiClient.isInitialized` gate in main.dart that stops us
      // reaching this catch branch at all. We test the defence here
      // so a future regression that bypasses the main.dart gate still
      // gives the user actionable copy.
      //
      // `LateInitializationError` is not a public type in `dart:core`
      // — the SDK throws a private `Error` subclass whose toString()
      // begins with the literal `"LateInitializationError:"`. We
      // provoke a real one via an instance field (analyzer can't
      // prove "definitely unassigned" on field access) so the test
      // exercises the actual SDK code path rather than a synthetic.
      final box = _LateBox();
      Object? captured;
      try {
        box.value.length;
      } catch (e) {
        captured = e;
      }
      expect(captured, isA<Error>());
      expect(captured.toString(), startsWith('LateInitializationError'));
      final msg = formatSaveRouteError(captured!);
      expect(msg, contains("Can't reach the server"));
      expect(msg, contains('Sign in'));
      expect(msg, isNot(contains('LateInitializationError')));
    });

    test(
        'StateError from the ApiClient bootstrap guard → friendly message',
        () {
      // Mirrors the exception thrown by ApiClient._client when called
      // before Supabase.initialize resolves. The string match in
      // formatSaveRouteError keys off "Supabase.initialize" so a
      // future rename has to land in lockstep on both sides.
      final msg = formatSaveRouteError(StateError(
        'ApiClient method called before Supabase.initialize() resolved.',
      ));
      expect(msg, contains("Can't reach the server"));
      expect(msg, isNot(contains('StateError')));
    });

    test(
        'unrelated StateError still surfaces verbatim — only the bootstrap '
        'signature is translated, so debugging info isn\'t hidden', () {
      // Make sure we don't over-translate: a StateError unrelated to
      // the Supabase bootstrap (e.g. someone calling a method on a
      // closed stream) should still hit the debug-friendly fallback.
      final msg =
          formatSaveRouteError(StateError('Bad state: stream is closed'));
      expect(msg, contains('Save failed:'));
      expect(msg, isNot(contains("Can't reach the server")));
    });
  });

  test('straightLineDistance sums haversine legs', () {
    final pts = [
      const cm.Waypoint(lat: 0, lng: 0),
      const cm.Waypoint(lat: 0, lng: 0.00899),
      const cm.Waypoint(lat: 0, lng: 0.01798),
    ];
    final d = straightLineDistance(pts);
    expect(d, closeTo(2000, 5),
        reason: 'two consecutive ~1 km legs should sum to ~2 km');
  });

  test('straightLineDistance is zero for <2 points', () {
    expect(straightLineDistance(const []), 0);
    expect(
      straightLineDistance(const [cm.Waypoint(lat: 0, lng: 0)]),
      0,
    );
  });

  group('overlapLatLngsFor', () {
    test('empty list for empty spans', () {
      expect(
        overlapLatLngsFor(const [], const []),
        isEmpty,
      );
    });

    test('slices the polyline by span indices, skipping <2-point spans',
        () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
        const cm.Waypoint(lat: 0.002, lng: 0),
        const cm.Waypoint(lat: 0.003, lng: 0),
        const cm.Waypoint(lat: 0.004, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 1, endIndex: 3),
        const OverlapSpan(startIndex: 4, endIndex: 4), // single-point, skipped
      ];
      final slices = overlapLatLngsFor(polyline, spans);
      expect(slices, hasLength(1));
      expect(slices.first, hasLength(3));
      expect(slices.first.first.latitude, closeTo(0.001, 1e-9));
      expect(slices.first.last.latitude, closeTo(0.003, 1e-9));
    });

    test('clamps endIndex when it overflows the polyline', () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 0, endIndex: 99),
      ];
      final slices = overlapLatLngsFor(polyline, spans);
      expect(slices.first, hasLength(2));
    });

    test('skips spans whose startIndex is out of range', () {
      final polyline = [
        const cm.Waypoint(lat: 0, lng: 0),
        const cm.Waypoint(lat: 0.001, lng: 0),
      ];
      final spans = [
        const OverlapSpan(startIndex: 5, endIndex: 6),
      ];
      expect(overlapLatLngsFor(polyline, spans), isEmpty);
    });
  });

  group('layout invariants', () {
    // Source-level guard: the bottom mode toggle's right inset must
    // clear the Scaffold's floatingActionButton column or the Straight
    // segment becomes untappable — the FAB renders above body Stack
    // children. Pin both the magic number AND the rationale so a
    // future tweak that drops the inset back to "right: 16" fails
    // loud rather than silently breaking Straight-segment taps. See
    // user-reported bug: "the straight button is covered by the
    // locate position button".
    test('mode toggle Positioned.right clears the FAB column', () {
      final source =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      expect(
        source.contains('right: 16 + 56 + 12'),
        isTrue,
        reason:
            "Mode toggle's right edge must leave room for the 56-dp FAB "
            "(plus 16 margin + 12 gap) so the Straight segment isn't "
            "covered by the Locate FAB.",
      );
    });

    test('empty-state hint suffixes the current mode', () {
      // Pin both the empty hint and the one-waypoint hint so flipping
      // the mode toggle has visible feedback before the user has
      // placed enough waypoints to trigger a re-route.
      final source =
          File('lib/screens/route_builder_screen.dart').readAsStringSync();
      expect(
        source.contains(
            r"'Tap the map to place waypoints · ${_modeLabel(mode)}'"),
        isTrue,
        reason: 'Empty-state hint must surface the mode label.',
      );
      expect(
        source.contains(
            r"'Place another to draw the line · ${_modeLabel(mode)}'"),
        isTrue,
        reason: 'Single-waypoint hint must surface the mode label.',
      );
    });
  });

  // ─── SaveRouteDialog ────────────────────────────────────────────────
  //
  // The Save modal hosts the name input, description input, and the
  // Make-public switch — and the actions row at the bottom (Cancel +
  // Save). The bug fixed in 903c5c0 was that AlertDialog clipped the
  // switch behind the actions strip on short screens (the field
  // report read "the save route -> save button is hiding the make
  // public toggle"). The fix wraps the content Column in a
  // SingleChildScrollView. These tests pin the contract end-to-end
  // beyond the source-level guard in architecture_guards_test.dart.

  group('SaveRouteDialog', () {
    // Pump a tiny harness whose only job is to host a Builder context
    // for `showDialog`. Returns the in-flight result Future so callers
    // can await it AFTER driving the dialog. The Builder + button
    // pattern is required because showDialog needs a BuildContext with
    // a Navigator above it — pumping the SaveRouteDialog directly
    // can't pop a Navigator that doesn't exist.
    Future<Future<SaveDialogResult?>> openDialog(
      WidgetTester tester, {
      Size viewport = const Size(360, 700),
      List<RouteClubChoice> clubChoices = const [],
      String? initialClubId,
    }) async {
      late Future<SaveDialogResult?> resultFuture;
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: viewport),
            child: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      resultFuture = showDialog<SaveDialogResult>(
                        context: ctx,
                        builder: (_) => SaveRouteDialog(
                          clubChoices: clubChoices,
                          initialClubId: initialClubId,
                        ),
                      );
                    },
                    child: const Text('Open dialog'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open dialog'));
      await tester.pumpAndSettle();
      return resultFuture;
    }

    testWidgets('renders Name, Description, and Make public controls',
        (tester) async {
      await openDialog(tester);

      expect(find.text('Save route'), findsOneWidget); // title
      expect(find.widgetWithText(TextField, ''), findsAtLeastNWidgets(2));
      expect(find.text('Name'), findsOneWidget); // label
      expect(find.text('Description (optional)'), findsOneWidget);
      expect(find.text('Make public'), findsOneWidget);
      expect(
        find.text('Others can find it on Explore'),
        findsOneWidget,
        reason: 'Subtitle copy must accompany the public toggle.',
      );
      // Make-public switch defaults to off.
      final switchTile =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(switchTile.value, isFalse);
    });

    testWidgets('Make public toggle is reachable on a short viewport',
        (tester) async {
      // The original bug: on a short viewport (or with the IME open),
      // the SwitchListTile was clipped behind the actions strip. Pump
      // the dialog into a deliberately tight viewport and assert the
      // switch is still findable. With the SingleChildScrollView wrap,
      // the user can scroll within the content area to reach it.
      await openDialog(tester, viewport: const Size(320, 480));

      final switchFinder = find.byType(SwitchListTile);
      expect(switchFinder, findsOneWidget,
          reason: 'Switch must be in the widget tree even when clipped — '
              'SingleChildScrollView guarantees this.');
      // Toggle reachable via ensureVisible (proves it lives inside a
      // scrollable, not behind opaque actions chrome).
      await tester.ensureVisible(switchFinder);
      await tester.pumpAndSettle();
      // Tappable now that it's scrolled into view.
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();
      final after = tester.widget<SwitchListTile>(switchFinder);
      expect(after.value, isTrue,
          reason: 'Switch must respond to a tap after being scrolled into '
              'view — proves the actions strip is not absorbing the tap.');
    });

    testWidgets('Save with name + toggle ON pops the right SaveDialogResult',
        (tester) async {
      final resultFuture = await openDialog(tester);
      await tester.enterText(find.byType(TextField).first, 'River loop');
      await tester.enterText(
          find.byType(TextField).at(1), 'Out-and-back along the canal');

      final sw = find.byType(SwitchListTile);
      await tester.ensureVisible(sw);
      await tester.pumpAndSettle();
      await tester.tap(sw);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.name, 'River loop');
      expect(result.isPublic, isTrue);
      expect(result.description, 'Out-and-back along the canal');
    });

    testWidgets('Save with empty name is a no-op — dialog stays open',
        (tester) async {
      await openDialog(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      // Dialog still visible, no result popped.
      expect(find.text('Save route'), findsOneWidget);
    });

    testWidgets('Save trims whitespace; description=empty pops as null',
        (tester) async {
      final resultFuture = await openDialog(tester);
      await tester.enterText(find.byType(TextField).first, '  Loop  ');
      // Leave description empty.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.name, 'Loop');
      expect(result.description, isNull,
          reason: 'Empty / whitespace-only description should pop as null so '
              'the DB column stays NULL, not "" (keeps the "had description" '
              'filter accurate later).');
    });

    testWidgets('Cancel pops null', (tester) async {
      final resultFuture = await openDialog(tester);
      await tester.enterText(find.byType(TextField).first, 'Loop');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNull);
    });

    testWidgets('club picker is hidden when clubChoices is empty', (tester) async {
      // Users not in any clubs see the same lean dialog as before —
      // the picker only appears when there's something to pick.
      await openDialog(tester);
      expect(
        find.byKey(const Key('save-route-dialog-club-picker')),
        findsNothing,
        reason: 'Save-to picker must be hidden when the user is in '
            'no clubs.',
      );
    });

    testWidgets('Save with empty clubChoices pops clubId=null', (tester) async {
      // Pin the existing behaviour for users without clubs — defaults
      // to Personal (clubId=null) so the route lands in the user's
      // own library, matching the pre-picker contract.
      final resultFuture = await openDialog(tester);
      await tester.enterText(find.byType(TextField).first, 'Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, isNull);
    });

    testWidgets(
        'club picker renders when clubChoices is non-empty and defaults to '
        'Personal', (tester) async {
      // The "Save to" picker shows with Personal as the default option
      // so users in a club don't accidentally publish to it; they have
      // to actively pick a club to set club_id.
      await openDialog(tester, clubChoices: const [
        RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
        RouteClubChoice(id: 'club-b', name: 'Vic Park Runners'),
      ]);
      expect(
        find.byKey(const Key('save-route-dialog-club-picker')),
        findsOneWidget,
      );
      expect(find.text('Save to'), findsOneWidget);
      expect(find.text('Personal'), findsOneWidget,
          reason: 'Personal must be the default selected option.');
    });

    testWidgets(
        'Save without changing the picker selection pops clubId=null '
        '(Personal default holds)', (tester) async {
      final resultFuture = await openDialog(tester, clubChoices: const [
        RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
      ]);
      await tester.enterText(find.byType(TextField).first, 'Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, isNull,
          reason: 'User who never opens the picker keeps the Personal '
              'default — `club_id` must be null on the saved row.');
    });

    testWidgets(
        'selecting a club then Save pops clubId set to that club\'s id',
        (tester) async {
      final resultFuture = await openDialog(tester, clubChoices: const [
        RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
        RouteClubChoice(id: 'club-b', name: 'Vic Park Runners'),
      ]);
      await tester.enterText(find.byType(TextField).first, 'Loop');

      // Open the dropdown + pick the second club.
      await tester
          .tap(find.byKey(const Key('save-route-dialog-club-picker')));
      await tester.pumpAndSettle();
      // The dropdown menu now contains both options; tap the last
      // matching "Vic Park Runners" entry (the menu rendering creates
      // a second copy of the selected text).
      await tester.tap(find.text('Vic Park Runners').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, 'club-b');
      expect(result.name, 'Loop');
    });

    testWidgets(
        'selecting a club then switching back to Personal pops clubId=null',
        (tester) async {
      // Belt-and-braces: ensure the picker is fully reversible. A user
      // who toggles around then settles on Personal must get a Personal
      // save, not a stuck club_id.
      final resultFuture = await openDialog(tester, clubChoices: const [
        RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
      ]);
      await tester.enterText(find.byType(TextField).first, 'Loop');

      await tester
          .tap(find.byKey(const Key('save-route-dialog-club-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Hackney Half').last);
      await tester.pumpAndSettle();

      await tester
          .tap(find.byKey(const Key('save-route-dialog-club-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, isNull);
    });

    testWidgets(
        'initialClubId seeds the picker — Save without changing the picker '
        'pops that clubId (web `/routes/new?club=<id>` parity)',
        (tester) async {
      // Entry from the club-detail "Build route" CTA: the dialog
      // should open with the club already selected so the user can
      // hit Save and land the route in the club library without
      // touching the picker.
      final resultFuture = await openDialog(
        tester,
        clubChoices: const [
          RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
          RouteClubChoice(id: 'club-b', name: 'Vic Park Runners'),
        ],
        initialClubId: 'club-b',
      );
      await tester.enterText(find.byType(TextField).first, 'Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, 'club-b');
    });

    testWidgets(
        'initialClubId is still overridable — user can flip to Personal '
        'before saving (nothing is locked)', (tester) async {
      final resultFuture = await openDialog(
        tester,
        clubChoices: const [
          RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
        ],
        initialClubId: 'club-a',
      );
      await tester.enterText(find.byType(TextField).first, 'Loop');

      await tester
          .tap(find.byKey(const Key('save-route-dialog-club-picker')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, isNull,
          reason: 'initialClubId is a default, not a lock — the user '
              'must be able to switch to Personal even when launched '
              'from a club context.');
    });

    testWidgets(
        'initialClubId pointing at an unknown id falls back to Personal '
        '(stale deep-link safety)', (tester) async {
      // If the caller passes a club id that isn't in `clubChoices`
      // (left over from a stale invitation, or the user lost
      // membership between tap and load), the picker must NOT enter
      // a non-selectable state. Falling back to Personal is the safe
      // default.
      final resultFuture = await openDialog(
        tester,
        clubChoices: const [
          RouteClubChoice(id: 'club-a', name: 'Hackney Half'),
        ],
        initialClubId: 'club-ghost',
      );
      await tester.enterText(find.byType(TextField).first, 'Loop');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
      expect(result!.clubId, isNull);
    });
  });
}

/// Helper used by the LateInitializationError defence test. The
/// analyzer can prove a local `late` variable is definitely
/// unassigned (and rejects the read at compile time); a `late` field
/// on an instance is opaque to that analysis, so accessing it at
/// runtime is the only way to provoke a real LateInitializationError
/// from the Dart runtime.
class _LateBox {
  late String value;
}
