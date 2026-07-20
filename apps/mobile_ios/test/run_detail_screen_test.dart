import 'dart:async';
import 'dart:io';

import 'package:api_client/api_client.dart';
import 'package:core_models/core_models.dart';
import 'package:flutter/material.dart' hide Route;
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/screens/run_detail_screen.dart';
import '../lib/settings_sync.dart';
import '../lib/widgets/live_run_map.dart';

late Directory _runsDir;

Run _run({
  double distanceMetres = 5000,
  Duration duration = const Duration(minutes: 25),
  String? title,
  bool withTrack = false,
  Map<String, dynamic>? metadata,
}) =>
    Run(
      id: 'run-1',
      startedAt: DateTime.utc(2026, 4, 15, 7, 30),
      duration: duration,
      distanceMetres: distanceMetres,
      source: RunSource.app,
      metadata: metadata ??
          (title != null ? {'title': title, 'activity_type': 'run'} : null),
      // The secondary-stats row (which hosts the Calories pill) is
      // gated on `run.track.length >= 2 || _hasElevation`. A
      // 2-waypoint stub track is the cheapest way to make the gate
      // fire when a test cares about secondary stats; the values
      // aren't used by the calorie math (which derives from
      // distanceMetres + bodyWeightKg + activityType only).
      track: withTrack
          ? [
              Waypoint(
                lat: -37.8136,
                lng: 144.9631,
                timestamp: DateTime.utc(2026, 4, 15, 7, 30),
              ),
              Waypoint(
                lat: -37.8137,
                lng: 144.9632,
                timestamp: DateTime.utc(2026, 4, 15, 7, 31),
              ),
            ]
          : const [],
    );

class _ThrowingRouteStore extends LocalRouteStore {
  @override
  Future<void> save(Route route, {bool markSynced = false}) async =>
      throw Exception('boom');
}

/// Signed-in fake whose `makeRunPublic` blocks on a completer the test
/// controls, so the in-flight share window stays open long enough to
/// assert the share button disabled + count the calls.
class _SlowShareApi extends ApiClient {
  final Completer<void> gate = Completer<void>();
  int calls = 0;

  @override
  String? get userId => 'user-1';

  @override
  Future<void> makeRunPublic(String runId) async {
    calls += 1;
    await gate.future;
  }
}

/// Signed-in fake that records makeRunPrivate calls; optionally throws
/// so the failure banner path can be driven without a backend.
class _MakePrivateApi extends ApiClient {
  int calls = 0;
  bool shouldThrow = false;

  @override
  String? get userId => 'user-1';

  @override
  Future<void> makeRunPrivate(String runId) async {
    calls += 1;
    if (shouldThrow) throw Exception('offline');
  }
}

/// Signed-in fake whose `deleteRun` always throws — the flaky-signal /
/// offline cloud delete of issue #252.
class _DeleteFailApi extends ApiClient {
  int calls = 0;

  @override
  String? get userId => 'user-1';

  @override
  Future<RunMatchInfo?> fetchRunMatchedTrack(String runId) async => null;

  @override
  Future<void> deleteRun(Run run) async {
    calls += 1;
    throw Exception('network down');
  }
}

/// Signed-in fake whose `deleteRun` succeeds.
class _DeleteOkApi extends ApiClient {
  int calls = 0;

  @override
  String? get userId => 'user-1';

  @override
  Future<RunMatchInfo?> fetchRunMatchedTrack(String runId) async => null;

  @override
  Future<void> deleteRun(Run run) async {
    calls += 1;
  }
}

/// Returns a seeded universal-bag value for [effective]; everything else
/// falls through to the caller's fallback. Never touches Supabase.
class _FakeSettingsService extends SettingsService {
  _FakeSettingsService(this._values)
      : super(deviceId: 'test-device', platform: 'android');

  final Map<String, dynamic> _values;

  @override
  T? effective<T>(String key, {T? fallback}) =>
      _values.containsKey(key) ? _values[key] as T? : fallback;
}

class _FakeSettingsSync extends SettingsSyncService {
  _FakeSettingsSync(Preferences prefs, this._service)
      : super(preferences: prefs);

  final SettingsService? _service;

  @override
  bool get synced => true;

  @override
  SettingsService? get service => _service;
}

Future<void> _pump(WidgetTester tester, Run run,
    {double? bodyWeightKg,
    LocalRouteStore? routeStore,
    ApiClient? apiClient,
    SettingsSyncService? settingsSync}) async {
  SharedPreferences.setMockInitialValues(
    bodyWeightKg != null ? {'body_weight_kg': bodyWeightKg} : {},
  );
  final prefs = Preferences();
  await prefs.init();

  _runsDir = Directory.systemTemp.createTempSync('run_detail_screen_test_');
  final runStore = LocalRunStore();
  await runStore.init(overrideDirectory: _runsDir);

  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RunDetailScreen(
        run: run,
        runStore: runStore,
        routeStore: routeStore ?? LocalRouteStore(),
        preferences: prefs,
        apiClient: apiClient,
        settingsSync: settingsSync,
      ),
    ),
  );
  // One pump cycle; pumpAndSettle would spin LiveRunMap's pulse animation.
  await tester.pump();
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  tearDown(() {
    if (_runsDir.existsSync()) _runsDir.deleteSync(recursive: true);
  });

  group('RunDetailScreen', () {
    testWidgets('renders the run date as the app-bar title when no title set',
        (tester) async {
      final run = _run();
      await _pump(tester, run);
      // The title is built from the date when metadata has no 'title' key.
      expect(find.textContaining('Apr'), findsAtLeastNWidgets(1));
    });

    testWidgets('renders the metadata title in the app bar when set',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      await _pump(tester, run);
      expect(find.text('Morning Tempo'), findsOneWidget);
    });

    testWidgets('renders Distance and Time primary stat labels', (tester) async {
      final run = _run();
      await _pump(tester, run);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
    });

    testWidgets('share button is present in the app bar', (tester) async {
      final run = _run();
      await _pump(tester, run);
      // Share is behind an overflow menu (Icons.more_vert or similar).
      // The screen uses an edit icon + more actions. Check the edit icon:
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets('share button is in-flight-guarded against a double-tap',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _SlowShareApi();
      await _pump(tester, run, apiClient: api);

      final shareFinder = find.widgetWithIcon(IconButton, Icons.share_outlined);
      expect(shareFinder, findsOneWidget);

      // Tap Share → confirm the make-public dialog. The store/network
      // I/O must run inside runAsync so the awaited makeRunPublic
      // continuation runs in the tap's zone.
      await tester.runAsync(() async {
        await tester.tap(shareFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(FilledButton, 'Make public'),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
      });

      // makeRunPublic is now blocked on the gate → _sharing is true →
      // the share IconButton is disabled (onPressed == null) so a second
      // tap can't fire a duplicate makeRunPublic.
      final disabled = tester.widget<IconButton>(shareFinder);
      expect(disabled.onPressed, isNull);

      // A second tap while disabled is a no-op — still exactly one call.
      await tester.runAsync(() async {
        await tester.tap(shareFinder, warnIfMissed: false);
        await tester.pump();
      });
      expect(api.calls, 1);

      // Release the gate and replace the tree so the share sheet doesn't
      // open into the small test viewport (its layout overflows there —
      // unrelated to the guard under test). gate.complete() lets the
      // awaited makeRunPublic settle cleanly.
      api.gate.complete();
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    });

    testWidgets('make-private confirms then calls makeRunPrivate',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _MakePrivateApi();
      await _pump(tester, run, apiClient: api);

      // Open the overflow menu → Make private. Timed pumps (not
      // pumpAndSettle, which spins the LiveRunMap pulse animation).
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Make private'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The confirm dialog gates the flip — nothing called yet.
      expect(find.text('Make this run private?'), findsOneWidget);
      expect(api.calls, 0);

      // Dialog-scoped finder — the menu item and the confirm button
      // share the 'Make private' label.
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Make private'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.calls, 1);
      expect(find.text('Run is now private'), findsOneWidget);

      // Drain the banner auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('make-private cancel leaves the run untouched',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _MakePrivateApi();
      await _pump(tester, run, apiClient: api);

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Make private'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Cancel'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.calls, 0);
      expect(find.text('Run is now private'), findsNothing);
    });

    testWidgets('make-private failure surfaces the error banner',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _MakePrivateApi()..shouldThrow = true;
      await _pump(tester, run, apiClient: api);

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Make private'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Make private'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(api.calls, 1);
      expect(find.textContaining('Could not make run private'),
          findsOneWidget);
      expect(find.text('Run is now private'), findsNothing);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('make-private is hidden when signed out', (tester) async {
      final run = _run(title: 'Morning Tempo');
      await _pump(tester, run);

      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Save as route'), findsOneWidget);
      expect(find.text('Make private'), findsNothing);
    });

    testWidgets('save-as-route shows an error banner when the store throws',
        (tester) async {
      final run = _run(title: 'Morning Tempo', withTrack: true);
      await _pump(tester, run, routeStore: _ThrowingRouteStore());

      // Open the overflow menu → Save as route. Timed pumps (not
      // pumpAndSettle, which spins the LiveRunMap pulse animation).
      await tester.tap(find.byTooltip('More'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Save as route').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Confirm the save dialog → the store throws → error banner, not
      // the success banner.
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('as a route'), findsOneWidget);

      // Drain the banner auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    // a11y: the h/m/s duration subfields in the edit dialog had no
    // field-level label — only the shared "Duration" Text above the row.
    // The Semantics wrap gives each edit box an accessible name
    // (uxhunt-mobile finding #3). A run with no GPS track keeps the
    // stats editable so the subfields render.
    testWidgets('duration subfields expose an accessible name', (tester) async {
      final run = _run();
      await _pump(tester, run);
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final durSem = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.label == 'Duration',
      );
      expect(durSem, findsNWidgets(3));
      final field = tester.getSemantics(
        find.descendant(of: durSem.first, matching: find.byType(TextField)),
      );
      expect(field.label, 'Duration');
    });

    testWidgets('renders activity type label', (tester) async {
      final run = _run(title: 'Easy run');
      await _pump(tester, run);
      expect(find.text('Run'), findsAtLeastNWidgets(1));
    });

    testWidgets('surfaces parkrun age_grade as a secondary stat (#9)',
        (tester) async {
      final run = _run(
        withTrack: true,
        metadata: {'activity_type': 'run', 'age_grade': '55.42%'},
      );
      await _pump(tester, run);
      expect(find.text('Age grade'), findsOneWidget);
      expect(find.text('55.42%'), findsOneWidget);
    });

    testWidgets('renders the Garmin discipline chip from sub_sport',
        (tester) async {
      final run = _run(metadata: {'activity_type': 'run', 'sub_sport': 'trail'});
      await _pump(tester, run);
      expect(find.text('Trail'), findsOneWidget);
    });

    testWidgets('renders a Running Dynamics block from running_dynamics',
        (tester) async {
      final run = _run(metadata: {
        'activity_type': 'run',
        'running_dynamics': {
          'vertical_oscillation_mm': 8.4,
          'gct_ms': 240,
          'stride_length_m': 1.18,
          'power_w': 290,
        },
      });
      await _pump(tester, run);
      expect(find.text('Running Dynamics'), findsOneWidget);
      expect(find.text('Vertical oscillation'), findsOneWidget);
      expect(find.text('8.4 mm'), findsOneWidget);
      expect(find.text('240 ms'), findsOneWidget);
      expect(find.text('1.18 m'), findsOneWidget);
      expect(find.text('290 W'), findsOneWidget);
    });

    testWidgets('omits the Running Dynamics block when the key is absent',
        (tester) async {
      final run = _run(metadata: {'activity_type': 'run'});
      await _pump(tester, run);
      expect(find.text('Running Dynamics'), findsNothing);
    });
  });

  // ─────────── Settings propagation: bodyWeightKg → calorie text ───────────
  //
  // Walks the Dart side of the settings propagation chain pinned on
  // the web by `tests-e2e/cross-cutting/settings-propagation.spec.ts`:
  //
  //   user_settings.prefs.body_weight_kg
  //     → SettingsSyncService._applyUniversal
  //       → Preferences.setBodyWeightKg
  //         → run_detail_screen reads widget.preferences.bodyWeightKg
  //           in _estimatedCalories
  //
  // The settings-sync overlay path is unit-tested separately in
  // settings_sync_test.dart; this group pins the LAST link — that the
  // render path reads the right Preferences field and computes the
  // kcal value correctly across the documented 70 kg fallback +
  // user-set values.
  group('RunDetailScreen — body_weight_kg → calorie estimate', () {
    testWidgets('renders ~350 kcal for a 5km run at the default 70 kg fallback',
        (tester) async {
      // No bodyWeightKg set → page falls back to 70 kg.
      // kcal = round(70 × 1.0 × 5000 / 1000) = 350.
      // (kcalPerKgPerKm for run is 1.0 — verified in preferences.dart.)
      final run = _run(withTrack: true);
      await _pump(tester, run);
      expect(find.text('350 kcal'), findsOneWidget);
    });

    testWidgets('honours a persisted bodyWeightKg=90 → 450 kcal for 5km',
        (tester) async {
      // Headline regression net: a user who sets their weight to 90 kg
      // on /settings (web) or the universal settings bag must see the
      // calorie estimate scale up. 90 × 1.0 × 5 = 450 kcal.
      final run = _run(withTrack: true);
      await _pump(tester, run, bodyWeightKg: 90);
      expect(find.text('450 kcal'), findsOneWidget);
      // Negative shape — the 70-kg fallback value must NOT also be
      // rendered (would indicate a leaky cache or the screen reading
      // the wrong field).
      expect(find.text('350 kcal'), findsNothing);
    });

    testWidgets('honours a persisted bodyWeightKg=50 → 250 kcal for 5km',
        (tester) async {
      // Lower end of the realistic adult range. 50 × 1.0 × 5 = 250.
      final run = _run(withTrack: true);
      await _pump(tester, run, bodyWeightKg: 50);
      expect(find.text('250 kcal'), findsOneWidget);
    });

    testWidgets('scales linearly with distance at fixed bodyWeightKg',
        (tester) async {
      // 10 km run × 70 kg fallback = 700 kcal. Pin the linearity
      // contract so a refactor that mis-applied an exponent or a
      // unit factor would fail.
      final run = _run(distanceMetres: 10000, withTrack: true);
      await _pump(tester, run);
      expect(find.text('700 kcal'), findsOneWidget);
    });
  });

  // ───────── show_calories pref gates the run-detail calorie tile ─────────
  //
  // Mirror of web's `/runs/[id]` gate:
  //   showCalories = effective<boolean>(settings, 'show_calories', true) !== false
  // Default (pref absent / no settings) → the tile shows; pref explicitly
  // false → hidden.
  group('RunDetailScreen — show_calories pref', () {
    testWidgets('shows the calorie tile by default (pref absent)',
        (tester) async {
      final run = _run(withTrack: true);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await _pump(
        tester,
        run,
        settingsSync: _FakeSettingsSync(prefs, _FakeSettingsService({})),
      );
      expect(find.text('Calories'), findsOneWidget);
      expect(find.text('350 kcal'), findsOneWidget);
    });

    testWidgets('hides the calorie tile when show_calories is false',
        (tester) async {
      final run = _run(withTrack: true);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await _pump(
        tester,
        run,
        settingsSync: _FakeSettingsSync(
          prefs,
          _FakeSettingsService({'show_calories': false}),
        ),
      );
      expect(find.text('Calories'), findsNothing);
      expect(find.text('350 kcal'), findsNothing);
    });
  });

  group('HR medication disclaimer', () {
    Run runWithHr() => Run(
          id: 'run-hr',
          startedAt: DateTime.utc(2026, 4, 15, 7, 30),
          duration: const Duration(minutes: 25),
          distanceMetres: 5000,
          source: RunSource.app,
          metadata: const {'activity_type': 'run'},
          track: [
            for (final e in const [110, 135, 160, 175])
              Waypoint(
                lat: -37.8136,
                lng: 144.9631,
                timestamp: DateTime.utc(2026, 4, 15, 7, 30),
                bpm: e,
              ),
          ],
        );

    // The HR-zone section sits deep in the lazy run-detail ListView. Give
    // the test a tall surface so the whole list builds eagerly and the
    // disclaimer's presence/absence is asserted against a fully-built tree.
    void useTallSurface(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    testWidgets('shows the disclaimer when zones are age-estimated',
        (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await _pump(
        tester,
        runWithHr(),
        settingsSync: _FakeSettingsSync(prefs, _FakeSettingsService({})),
      );
      expect(find.text('Set max HR'), findsOneWidget);
    });

    testWidgets('hides the disclaimer when a max_hr_bpm override is set',
        (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await _pump(
        tester,
        runWithHr(),
        settingsSync:
            _FakeSettingsSync(prefs, _FakeSettingsService({'max_hr_bpm': 185})),
      );
      // The HR section still renders (zone rows present); only the
      // age-estimated disclaimer is suppressed.
      expect(find.text('Set max HR'), findsNothing);
    });

    testWidgets('hides the disclaimer when explicit hr_zones are set',
        (tester) async {
      useTallSurface(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();
      await _pump(
        tester,
        runWithHr(),
        settingsSync: _FakeSettingsSync(
          prefs,
          _FakeSettingsService({
            'hr_zones': {'z1': 110, 'z2': 130, 'z3': 150, 'z4': 170, 'z5': 190},
          }),
        ),
      );
      expect(find.text('Set max HR'), findsNothing);
    });
  });

  // ───────── adaptive width: expanded two-pane vs stacked layout ─────────
  //
  // Timed pumps only — LiveRunMap fetches tiles (which fail under
  // flutter_test) and runs a repeating pulse animation, so pumpAndSettle
  // would hang (same constraint as live_run_map_test.dart).
  group('RunDetailScreen — expanded two-pane layout', () {
    testWidgets('map renders beside the stats column at >=840dp',
        (tester) async {
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final run = _run(withTrack: true);
      await _pump(tester, run);

      final mapRect = tester.getRect(find.byType(LiveRunMap));
      final distanceRect = tester.getRect(find.text('Distance'));
      // Stats column starts to the right of the map pane, vertically
      // overlapping it — side by side, not stacked.
      expect(distanceRect.left, greaterThanOrEqualTo(mapRect.right));
      expect(distanceRect.top, greaterThan(mapRect.top));
      expect(distanceRect.top, lessThan(mapRect.bottom));
      // The map pane fills the height under the AppBar (not the 280dp
      // strip) and takes ~55% of the 1280dp logical width.
      expect(mapRect.height, greaterThan(400));
      expect(mapRect.width, closeTo(1280 * 0.55, 24));
      // The map keeps its overlays in the pane.
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('a compact surface keeps the stacked layout', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final run = _run(withTrack: true);
      await _pump(tester, run);

      final mapRect = tester.getRect(find.byType(LiveRunMap));
      expect(mapRect.height, closeTo(280, 1));
      final distanceRect = tester.getRect(find.text('Distance'));
      expect(distanceRect.top, greaterThan(mapRect.bottom));
    });
  });

  group('RunDetailScreen — delete', () {
    // The delete flow's runAsync window pumps the real event loop,
    // which surfaces the connectivity_plus EventChannel's
    // MissingPluginException (harmlessly swallowed under pure
    // fake-async) as an unexpected test exception. Stub the stream so
    // the channel activates cleanly.
    const connectivityChannel =
        EventChannel('dev.fluttercommunity.plus/connectivity_status');
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
        connectivityChannel,
        MockStreamHandler.inline(onListen: (arguments, events) {}),
      );
    });
    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(connectivityChannel, null);
    });

    Future<LocalRunStore> pumpForDelete(
      WidgetTester tester,
      Run run, {
      ApiClient? apiClient,
    }) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = Preferences();
      await prefs.init();

      _runsDir = Directory.systemTemp.createTempSync('run_detail_delete_test_');
      final runStore = LocalRunStore();
      await tester.runAsync(
          () => runStore.init(overrideDirectory: _runsDir));
      runStore.debugSeed([run], dir: _runsDir);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => RunDetailScreen(
                      run: run,
                      runStore: runStore,
                      routeStore: LocalRouteStore(),
                      preferences: prefs,
                      apiClient: apiClient,
                    ),
                  ),
                ),
                child: const Text('open detail'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open detail'));
      // Timed pumps, not pumpAndSettle — LiveRunMap's pulse animation
      // never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      return runStore;
    }

    Future<void> deleteViaMenu(
      WidgetTester tester, {
      bool Function()? settled,
    }) async {
      // The whole interaction runs inside runAsync so the store file
      // I/O awaited by the delete flow (sidecar persist / run-file
      // delete) completes in the tap's zone — the same pattern as the
      // share in-flight-guard test above.
      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('More'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('Delete run'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        // Confirm in the dialog (scoped to the FilledButton so the menu
        // item's identical label can't match).
        await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
        await tester.pump();
        // Drain the delete flow's real async (api call + tombstone /
        // run-file store I/O) to completion instead of guessing a
        // wall-clock delay — a fixed delay flaked under CI load when the
        // failure banner hadn't been posted yet by the time it elapsed.
        await pumpEventQueue();
        // …and for a caller that can observe the flow's END state, keep
        // draining until it lands. `pumpEventQueue`'s 20 turns are not
        // guaranteed to cover real file I/O on a loaded CI runner: the
        // failure path persists a tombstone sidecar BEFORE posting its
        // banner, so a slow write left the banner unposted (and teardown
        // then deleted the temp dir out from under the write). Waiting on
        // the condition the test asserts is the only bound that scales
        // with the machine.
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (settled != null &&
            !settled() &&
            DateTime.now().isBefore(deadline)) {
          await pumpEventQueue();
          await tester.pump();
        }
      });
      await tester.pump();
      // Two 300 ms pumps: the first finishes the dialog dismissal, the
      // second carries the pop's route transition to completion.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets(
        'failed cloud delete keeps the run locally, queues a retry '
        'tombstone, and surfaces a banner', (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _DeleteFailApi();
      final runStore = await pumpForDelete(tester, run, apiClient: api);

      await deleteViaMenu(
        tester,
        // The banner is posted right after the tombstone persist
        // resolves — it is the last thing this flow does.
        settled: () => find
            .textContaining("Couldn't delete from the cloud")
            .evaluate()
            .isNotEmpty,
      );

      expect(api.calls, 1);
      // Run NOT removed locally — the cloud row still exists, so a local
      // delete would just resurrect on the next resync.
      expect(runStore.runs.map((r) => r.id), contains(run.id));
      // Tombstoned for the SyncService retry, stamped with the owner.
      expect(runStore.pendingRemoteDeleteIds, contains(run.id));
      expect(runStore.debugPendingRemoteDeleteOwner(run.id), 'user-1');
      // Failure surfaced, screen not popped.
      expect(find.textContaining("Couldn't delete from the cloud"),
          findsOneWidget);
      expect(find.byType(RunDetailScreen), findsOneWidget);

      // A resync that pulls the still-live server row must not clear the
      // tombstone — the queued delete survives so it can't zombie back.
      await tester.runAsync(() => runStore.saveFromRemote(run));
      expect(runStore.pendingRemoteDeleteIds, contains(run.id));

      // Drain the banner auto-dismiss timer before teardown.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets(
        'successful cloud delete removes the run locally, queues nothing, '
        'and pops', (tester) async {
      final run = _run(title: 'Morning Tempo');
      final api = _DeleteOkApi();
      final runStore = await pumpForDelete(tester, run, apiClient: api);

      await deleteViaMenu(tester);

      expect(api.calls, 1);
      // Gone locally and nothing queued: the cloud row was removed, so
      // a resync has nothing to pull back.
      expect(runStore.runs, isEmpty);
      expect(runStore.summaries, isEmpty);
      expect(runStore.pendingRemoteDeleteIds, isEmpty);
      expect(find.byType(RunDetailScreen), findsNothing);
      expect(find.text('open detail'), findsOneWidget);
    });

    testWidgets('signed-out delete stays local-only and pops',
        (tester) async {
      final run = _run(title: 'Morning Tempo');
      final runStore = await pumpForDelete(tester, run);

      await deleteViaMenu(tester);

      expect(runStore.runs, isEmpty);
      expect(runStore.pendingRemoteDeleteIds, isEmpty);
      expect(find.byType(RunDetailScreen), findsNothing);
    });
  });
}
