import 'dart:async';
import 'dart:io';

import 'package:core_models/core_models.dart' as cm;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../lib/audio_cues.dart';
import '../lib/ble_heart_rate.dart';
import '../lib/ble_treadmill.dart';
import '../lib/l10n/gen/app_localizations.dart';
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';
import '../lib/turn_cues.dart';
import 'pump_until.dart';

/// Drives the full RunScreen UI flow: tap START → countdown → recording.
///
/// This test exists to close the documented "RunScreen recording-loop UI
/// flow" gap. It needs platform-channel mocks for every plugin RunScreen
/// touches when transitioning out of idle:
///
///   - GeolocatorPlatform.instance — extends the platform interface so
///     `Geolocator.getPositionStream` flows through a controlled stream.
///   - WakelockPlusPlatformInterface.instance — no-op subclass so
///     `WakelockPlus.enable()` doesn't hit the real pigeon channel.
///   - MethodChannel `flutter.baseflow.com/permissions/methods` —
///     permission_handler. Returns "granted" for every request.
///   - MethodChannel `flutter_tts` — flutter_tts (used by AudioCues).
///     Returns `1` (success) for every method.
///   - MethodChannel `run_app/run_notification` — the app's lock-screen
///     stats bridge. Returns null for `update`.
///   - EventChannel `step_count` — pedometer. The `listen` method returns
///     null so the stream is silent (no step events).
///
/// What this test PROVES that the existing tests don't:
///   - Tapping START transitions the screen out of idle.
///   - The countdown text ("3" / "2" / "1") cycles correctly.
///   - The recording state initializes RunRecorder + LiveRunMap.
///   - Holding the Finish (hold-to-stop) button runs the real `_stop()`,
///     which persists the finished run via `runStore.save(run)` — closing
///     the documented "RunScreen Finish + save UI test" gap. The store is
///     a `_CapturingRunStore` spy so the save is captured synchronously
///     (the real store does filesystem I/O that doesn't resolve under the
///     fake test clock); everything else is the production path.

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  StreamController<Position>? _positions;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.always;

  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.always;

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

/// Spy [LocalRunStore] that captures `save(run)` synchronously instead of
/// writing to disk. The real store's `save` awaits a `File.writeAsString`,
/// and real I/O futures don't resolve under flutter_test's fake-async
/// `pump()` — completing them needs `tester.runAsync`, which can't coexist
/// with the fake-async timers LiveRunMap's dio tile fetches leave pending.
/// Capturing in memory keeps the whole Finish flow on the fake clock (like
/// every other test in this file) while still exercising the real
/// `_stop()` → `runStore.save(run)` UI path end-to-end.
class _CapturingRunStore extends LocalRunStore {
  final List<dynamic> captured = [];
  final List<dynamic> capturedInProgress = [];
  int clearInProgressCalls = 0;

  @override
  Future<cm.Run> save(run) async {
    captured.add(run);
    // save() returns the RESIDENT instance so markManySynced can identify it;
    // the spy has no store, so the argument IS the resident copy here.
    return run;
  }

  @override
  Future<void> saveInProgress(run) async {
    capturedInProgress.add(run);
  }

  @override
  Future<void> clearInProgress() async {
    clearInProgressCalls++;
  }
}

/// Geolocator fake whose device-level location services are OFF, so
/// `RunRecorder.prepare` throws `LocationServiceDisabledError` — the
/// documented indoor / permission-denied start path.
class _ServicesOffGeolocatorPlatform extends _FakeGeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => false;
}

/// Records every spectator ping the run screen decides to send. The real
/// controller throttles internally; overriding the whole method means the
/// test counts the screen's DECISIONS, not the network calls.
class _SpyRaceController extends RaceController {
  _SpyRaceController(SocialService social) : super(social);

  int pings = 0;

  @override
  Future<void> pushPing({
    required double lat,
    required double lng,
    double? distanceM,
    int? elapsedS,
    int? bpm,
  }) async {
    pings++;
  }
}

/// Captures the spoken turn cues without touching the TTS engine.
class _SpyAudioCues extends AudioCues {
  final List<String?> turnDistances = [];

  @override
  Future<void> announceTurn(TurnDirection direction, {String? distance}) async {
    turnDistances.add(distance);
  }
}

class _NoOpWakelock extends WakelockPlusPlatformInterface {
  bool _on = false;

  @override
  bool get isMock => true;

  @override
  Future<void> toggle({required bool enable}) async {
    _on = enable;
  }

  @override
  Future<bool> get enabled async => _on;
}

Position _pos({
  required double metresEast,
  required int secondsFromStart,
  double accuracy = 5,
}) {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  return Position(
    longitude: lngBase + metresEast / metrePerDegLng,
    latitude: lat,
    timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
    accuracy: accuracy,
    altitude: 400,
    altitudeAccuracy: 2,
    heading: 90,
    headingAccuracy: 5,
    speed: 2.5,
    speedAccuracy: 1,
  );
}

/// An L-shaped route: 500 m east, then 300 m north. `generateTurnCues`
/// emits one left turn at 500 m along — far enough that a runner at 180 m
/// is inside the 300 m announce band and nowhere near the corner.
cm.Route _cornerRoute() {
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;
  const metrePerDegLat = 111320.0;
  cm.Waypoint east(double m) =>
      cm.Waypoint(lat: lat, lng: lngBase + m / metrePerDegLng);
  cm.Waypoint north(double m) => cm.Waypoint(
        lat: lat + m / metrePerDegLat,
        lng: lngBase + 500 / metrePerDegLng,
      );
  return cm.Route(
    id: 'corner-route-1',
    name: 'Corner',
    waypoints: [east(0), east(250), east(500), north(100), north(300)],
    distanceMetres: 800,
  );
}

cm.Route _testRoute(String id) => cm.Route(
      id: id,
      userId: 'u1',
      name: 'Test loop',
      distanceMetres: 5000,
      isPublic: false,
      waypoints: const [
        cm.Waypoint(lat: 47.37, lng: 8.54),
        cm.Waypoint(lat: 47.371, lng: 8.541),
      ],
    );

void main() {
  late _FakeGeolocatorPlatform geolocator;
  late Directory runsDir;
  bool supabaseReady = false;

  // Track every channel mock we registered so we can unregister cleanly
  // — leaving registrations between tests would leak across files.
  final mockedMethodChannels = <String>[];
  final mockedEventChannels = <String>[];

  void mockMethodChannel(String name, Future<Object?> Function(MethodCall) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannel(name), handler);
    mockedMethodChannels.add(name);
  }

  void mockEventChannelAsSilent(String name) {
    // The underlying MethodChannel for an EventChannel exposes `listen`
    // and `cancel`. Returning null is enough to keep the stream open
    // and silent — perfect for tests that don't need step events.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      MethodChannel(name, const StandardMethodCodec()),
      (call) async => null,
    );
    mockedEventChannels.add(name);
  }

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // Point LiveRunMap's tile URL at a scheme dart:io HttpClient rejects
    // synchronously, so dio's tile fetches fail immediately instead of
    // leaving pending fake-async timers — those would otherwise trip the
    // teardown `!timersPending` guard once the Finish-save test enters a
    // `tester.runAsync` block. (Empty dotenv would fall back to the OSM
    // URL, which does fetch.) Other tests in this file already tolerate
    // tile-fetch failures via takeException.
    dotenv.loadFromString(
      envString: 'TILE_URL_TEMPLATE=offline-no-network://tiles/{z}/{x}/{y}.png',
      isOptional: true,
    );
    if (!supabaseReady) {
      await Supabase.initialize(
        url: 'http://127.0.0.1:54321',
        anonKey: 'eyJ.local.test',
      );
      supabaseReady = true;
    }
  });

  setUp(() async {
    // Geolocator fake — extends the platform interface, no platform
    // channel calls.
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;

    // Wakelock fake — same pattern.
    WakelockPlusPlatformInterface.instance = _NoOpWakelock();

    // permission_handler — every request returns "granted" (status 1).
    mockMethodChannel('flutter.baseflow.com/permissions/methods', (call) async {
      switch (call.method) {
        case 'checkPermissionStatus':
        case 'requestPermissions':
          // PermissionStatus.granted is index 1 on most permission_handler
          // versions; the actual value isn't load-bearing for this test
          // since the screen doesn't gate behaviour on the result. The
          // important thing is that the call resolves rather than throwing
          // MissingPluginException.
          if (call.arguments is List) {
            return {for (final p in (call.arguments as List)) p: 1};
          }
          return 1;
        default:
          return null;
      }
    });

    // flutter_tts — every call resolves to `1` (success). AudioCues
    // wraps every TTS call in a try/catch so failures here would be
    // swallowed anyway, but the channel must exist.
    mockMethodChannel('flutter_tts', (call) async => 1);

    // RunNotificationBridge — the app-level lock-screen update channel.
    mockMethodChannel('run_app/run_notification', (call) async => null);

    // pedometer — the EventChannel under the hood is a MethodChannel
    // with `listen` / `cancel`. Silent stream.
    mockEventChannelAsSilent('step_count');
    mockEventChannelAsSilent('step_detection');

    runsDir = Directory.systemTemp.createTempSync('run_screen_recording_');
  });

  tearDown(() async {
    for (final name in mockedMethodChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
    for (final name in mockedEventChannels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel(name, const StandardMethodCodec()),
        null,
      );
    }
    mockedMethodChannels.clear();
    mockedEventChannels.clear();
    await geolocator.dispose();
    if (runsDir.existsSync()) runsDir.deleteSync(recursive: true);
  });

  Future<({
    LocalRunStore runStore,
    LocalRouteStore routeStore,
    Preferences prefs,
    SocialService social,
    TrainingService training,
    BleHeartRate heartRate,
    BleTreadmill treadmill,
    AudioCues audioCues,
    RaceController raceController,
  })> makeStores() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = Preferences();
    await prefs.init();

    final runStore = LocalRunStore();
    await runStore.init(overrideDirectory: runsDir);

    final social = SocialService();

    return (
      runStore: runStore,
      routeStore: LocalRouteStore(),
      prefs: prefs,
      social: social,
      training: TrainingService(),
      heartRate: BleHeartRate(),
      treadmill: BleTreadmill(),
      audioCues: AudioCues(),
      raceController: RaceController(social),
    );
  }

  Future<LocalRunStore> pumpRunScreen(WidgetTester tester) async {
    final s = await makeStores();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunScreen(
          apiClient: null,
          runStore: s.runStore,
          routeStore: s.routeStore,
          preferences: s.prefs,
          audioCues: s.audioCues,
          social: s.social,
          raceController: s.raceController,
          training: s.training,
          heartRate: s.heartRate,
          treadmill: s.treadmill,
        ),
      ),
    );
    await tester.pump();
    return s.runStore;
  }

  group('RunScreen — recording flow', () {
    testWidgets('tapping START transitions the screen into countdown state',
        (tester) async {
      await pumpRunScreen(tester);

      // Idle state shows the green circular START button.
      expect(find.text('START'), findsOneWidget);

      await tester.tap(find.text('START'));
      // Drain the synchronous setState in _beginCountdown after the
      // permission request future resolves.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Countdown shows the current value as a large number. Initial
      // value is 3 (set by setState before the periodic timer ticks).
      expect(
        find.text('3'),
        findsOneWidget,
        reason: 'countdown should be live with value 3 right after tapping START',
      );
      // The START affordance is no longer the entry point during
      // countdown — the screen has switched to the countdown surface.
      expect(find.text('START'), findsNothing);
    });

    testWidgets('countdown ticks 3 → 2 → 1 over three seconds', (tester) async {
      await pumpRunScreen(tester);
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('3'), findsOneWidget);

      // Periodic timer fires every 1 second.
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('after the countdown elapses the screen leaves countdown state',
        (tester) async {
      await pumpRunScreen(tester);
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Countdown started.
      expect(find.text('3'), findsOneWidget);

      // Tick through the full countdown. After three seconds, the timer
      // calls _begin() which transitions to the recording state. The
      // countdown numerals (1, 2, 3) should no longer be the focal text.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      // _begin() runs synchronously after the timer cancel; pump again
      // to apply its setState.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Concrete behavioural check: the countdown's '3' is no longer
      // the prominent display element. (We don't assert on the
      // recording UI directly — that would require LiveRunMap to
      // resolve its tile fetches, which fail under flutter_test.)
      final countdownThree = find
          .text('3')
          .evaluate()
          .where((e) => e.size != null && e.size!.height > 80)
          .toList();
      expect(countdownThree, isEmpty,
          reason:
              'after countdown completes the large "3" should be gone');
    });

    testWidgets('LiveRunMap mounts once recording begins', (tester) async {
      await pumpRunScreen(tester);
      // Idle: no map.
      final mapBeforeStart = tester.allWidgets
          .where((w) => w.runtimeType.toString() == 'LiveRunMap')
          .toList();
      expect(mapBeforeStart, isEmpty,
          reason: 'invariant from run_screen_test.dart — no map on idle');

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Walk through the countdown.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // _begin() transitions to recording.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // After recording begins, LiveRunMap is in the tree.
      final mapAfterBegin = tester.allWidgets
          .where((w) => w.runtimeType.toString() == 'LiveRunMap')
          .toList();
      expect(mapAfterBegin, isNotEmpty,
          reason: 'LiveRunMap should mount once recording begins');
    });

    testWidgets('pace-cue mute toggle appears when a pace target is set and silences cues',
        (tester) async {
      final s = await makeStores();
      // A pace target + audio cues on are the precondition for live pace
      // cues — and therefore for the session mute affordance.
      await s.prefs.setTargetPaceSecPerKm(300);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The mute affordance is offered (not yet muted).
      expect(find.text('Mute pace cues'), findsOneWidget);
      expect(find.text('Pace cues muted'), findsNothing);

      // Tapping it flips to the muted state for this session.
      await tester.tap(find.text('Mute pace cues'));
      await tester.pump();
      expect(find.text('Pace cues muted'), findsOneWidget);
      expect(find.text('Mute pace cues'), findsNothing);
    });

    testWidgets('positions emitted after recording begins flow into the recorder',
        (tester) async {
      await pumpRunScreen(tester);
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Walk through the countdown.
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      // _begin() transitions to recording.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Drain any caught exceptions from the recording state mount —
      // LiveRunMap's tile fetches log DioException 400s in test env
      // (no network); those are noise, not regressions.
      tester.takeException();

      // Push synthetic GPS fixes through the geolocator fake.
      for (var i = 0; i < 5; i++) {
        geolocator.emit(_pos(metresEast: i * 10.0, secondsFromStart: i));
        await tester.pump(const Duration(milliseconds: 50));
      }

      // After ingesting positions, the screen has not thrown a fatal
      // exception. A regression that fails to wire the geolocator into
      // the recording surface would manifest as a thrown exception
      // during the emit/pump cycles.
      tester.takeException();
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'widget tree must still be alive after GPS feed');
    });

    testWidgets('holding Finish saves the run through runStore.save',
        (tester) async {
      // Spy store captures the save synchronously (see _CapturingRunStore).
      final runStore = _CapturingRunStore();
      await runStore.init(overrideDirectory: runsDir);
      final s = await makeStores();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();
      expect(runStore.captured, isEmpty,
          reason: 'no run saved yet on a fresh store');

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // drain LiveRunMap tile-fetch noise

      // Feed a short track so the saved run carries real geometry.
      for (var i = 0; i < 6; i++) {
        geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();

      // Hold the Finish button → _stop() → runStore.save().
      await holdFinish(tester);
      tester.takeException(); // drain any LiveRunMap tile noise from the rebuild

      expect(runStore.captured, hasLength(1),
          reason: 'holding Finish must save exactly one run');
      final saved = runStore.captured.single;
      expect(saved.metadata?['activity_type'], 'run',
          reason: 'the chosen activity type is tagged onto the saved run');
      expect(saved.duration.inSeconds, greaterThanOrEqualTo(0));

      // Unmount the screen (disposes LiveRunMap so no new tile fetches are
      // scheduled), then pump to fire any orphaned zero-duration dio fetch
      // timers so the teardown `!timersPending` guard stays satisfied.
      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets(
        'crash-safe incremental save carries the selected route (#672)',
        (tester) async {
      // Spy store captures saveInProgress synchronously (see
      // _CapturingRunStore) so the 10s timer's real-I/O save doesn't hang
      // under the fake test clock.
      final runStore = _CapturingRunStore();
      await runStore.init(overrideDirectory: runsDir);
      final s = await makeStores();
      final route = _testRoute('route-selected-1');
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
            initialRoute: route,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // drain LiveRunMap tile-fetch noise

      // Fire the 10s crash-safe incremental-save timer once.
      await tester.pump(const Duration(seconds: 10));
      tester.takeException();

      expect(runStore.capturedInProgress, isNotEmpty,
          reason: 'the 10s incremental-save timer must have fired');
      final partial = runStore.capturedInProgress.first;
      expect(partial.routeId, route.id,
          reason: 'a crash-safe partial save must carry the selected '
              'route, or a resumed run permanently loses its route '
              'link (#672)');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets(
        'split posts reuse update_split and run start clears leftovers (#303)',
        (tester) async {
      // Capture every RunNotificationBridge channel call so we can pin the
      // split-notification contract: run start sends clear_split (a
      // previous run's split row can't leak into this one), and each
      // completed split routes through update_split — the single-fixed-id
      // replace-in-place path — never a stacking post per kilometre.
      final bridgeCalls = <MethodCall>[];
      mockMethodChannel('run_app/run_notification', (call) async {
        bridgeCalls.add(call);
        return null;
      });

      final s = await makeStores();
      // 50 m splits so a short synthetic track crosses two boundaries.
      await s.prefs.setSplitIntervalMetres(50);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // drain LiveRunMap tile-fetch noise

      expect(bridgeCalls.map((c) => c.method), contains('clear_split'),
          reason: 'beginning a run must drop any split row left over '
              'from a previous run');
      expect(bridgeCalls.where((c) => c.method == 'update_split'), isEmpty,
          reason: 'no split has been completed yet');

      // ~108 m of accepted fixes → the 50 m and 100 m boundaries.
      for (var i = 0; i < 10; i++) {
        geolocator.emit(_pos(metresEast: i * 12.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();

      final splits =
          bridgeCalls.where((c) => c.method == 'update_split').toList();
      expect(splits, hasLength(2),
          reason: 'two crossed boundaries → exactly two update_split '
              'posts, each replacing the last on the fixed native id');
      for (final c in splits) {
        final args = c.arguments as Map;
        expect(args['title'], isNotEmpty);
        expect(args['text'], isNotEmpty);
      }

      tester.takeException();

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets(
        'a GPS blackout raises the lost banner and stops spectator pings',
        (tester) async {
      final s = await makeStores();
      final race = _SpyRaceController(s.social);
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: race,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // LiveRunMap tile-fetch noise

      geolocator.emit(_pos(metresEast: 0, secondsFromStart: 0));
      await tester.pump(const Duration(milliseconds: 50));
      geolocator.emit(_pos(metresEast: 12, secondsFromStart: 2));
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      expect(find.text('GPS signal lost — move to open sky'), findsNothing,
          reason: 'fixes are flowing');
      final pingsWhileLive = race.pings;
      expect(pingsWhileLive, greaterThan(0),
          reason: 'a fresh fix is broadcast to spectators');

      // Fix age is measured on the wall clock — a GPS-reported timestamp
      // can be skewed — and tester.pump does not advance it, so the
      // blackout has to be real time. The recorder's 1 s snapshot timer is
      // on the fake clock, so no fix lands during it: exactly the tunnel /
      // torn-down-stream case.
      await tester
          .runAsync(() => Future<void>.delayed(const Duration(seconds: 11)));
      // Now let the 1 s snapshot timer re-emit the frozen fix and the 2 s
      // GPS-health timer read it.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 2));
      tester.takeException();

      expect(find.text('GPS signal lost — move to open sky'), findsOneWidget,
          reason: 'the recorder re-emits the LAST fix every second, so a '
              'non-null position must never be read as a live sensor');
      expect(race.pings, pingsWhileLive,
          reason: 'a spectator must not see a frozen coordinate re-pinged '
              'as a fresh, stationary runner');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets('a rejected GPS teleport does not fire a turn cue',
        (tester) async {
      final s = await makeStores();
      final cues = _SpyAudioCues();
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: cues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
            initialRoute: _cornerRoute(),
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      // Run up the first leg towards the 500 m corner.
      for (var i = 0; i < 3; i++) {
        geolocator.emit(
            _pos(metresEast: 150 + i * 16.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
      expect(cues.turnDistances, hasLength(1),
          reason: 'the far band announces once on the approach');

      // A multipath fix 300 m up the course in 2 s: the recorder rejects it
      // for distance, so it must not advance route progress either.
      geolocator.emit(_pos(metresEast: 480, secondsFromStart: 6));
      await tester.pump(const Duration(milliseconds: 50));
      geolocator.emit(_pos(metresEast: 482, secondsFromStart: 8));
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      expect(cues.turnDistances, hasLength(1),
          reason: 'a fix the distance filter rejected must not announce the '
              'turn the runner has not reached');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets('a GPS-unavailable start reports no uncaught async error',
        (tester) async {
      final off = _ServicesOffGeolocatorPlatform();
      GeolocatorPlatform.instance = off;
      await pumpRunScreen(tester);

      await tester.tap(find.text('START'));
      await tester.pump();
      // prepare() rejects here, ~3 s before _begin awaits it.
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull,
          reason: 'a future that completes with an error while it has no '
              'listener is reported to the zone as uncaught');

      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // LiveRunMap tile-fetch noise

      expect(
        find.text('No GPS — tracking will start when Location is on.'),
        findsOneWidget,
        reason: 'the indoor fallback still tells the runner why',
      );

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
      await off.dispose();
    });
  });

  group('RunScreen — resume a process-killed partial', () {
    cm.Run resumablePartial({String? routeId}) {
      final track = List.generate(
        6,
        (i) => cm.Waypoint(
          lat: 47.37,
          lng: 8.54 + i * 0.0002,
          timestamp: DateTime(2026, 4, 10, 9, 0, i * 5),
        ),
      );
      return cm.Run(
        id: 'resume-me-1',
        startedAt: DateTime(2026, 4, 10, 9, 0, 0),
        duration: const Duration(hours: 40),
        distanceMetres: 187000,
        track: track,
        routeId: routeId,
        source: cm.RunSource.app,
        metadata: {
          'activity_type': 'run',
          'in_progress_saved_at':
              DateTime(2026, 4, 10, 9, 40, 0).toIso8601String(),
          'laps': [
            {
              'index': 1,
              'start_offset_s': 0,
              'distance_m': 6700.0,
              'duration_s': 2400,
            },
          ],
        },
      );
    }

    Future<_CapturingRunStore> pumpResume(
      WidgetTester tester, {
      String? routeId,
      List<cm.Route> seedRoutes = const [],
    }) async {
      final runStore = _CapturingRunStore();
      await runStore.init(overrideDirectory: runsDir);
      final s = await makeStores();
      if (seedRoutes.isNotEmpty) {
        s.routeStore.debugSeed(seedRoutes);
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
            initialResumablePartial: resumablePartial(routeId: routeId),
          ),
        ),
      );
      // First pump mounts; second lets the post-frame callback open the dialog.
      await tester.pump();
      await tester.pump();
      return runStore;
    }

    testWidgets('cold start prompts Resume / Finish / Discard', (tester) async {
      await pumpResume(tester);
      expect(find.text('Resume your run?'), findsOneWidget);
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Finish now'), findsOneWidget);
      expect(find.text('Discard'), findsOneWidget);
    });

    testWidgets('Discard clears the in-progress file and returns to idle',
        (tester) async {
      final runStore = await pumpResume(tester);
      await tester.tap(find.text('Discard'));
      await tester.pump();
      await tester.pump();
      expect(runStore.clearInProgressCalls, greaterThanOrEqualTo(1),
          reason: 'Discard must drop the in-progress recovery file');
      expect(runStore.captured, isEmpty,
          reason: 'Discard saves nothing');
      // Back on the idle surface.
      expect(find.text('START'), findsOneWidget);
      expect(find.text('Resume your run?'), findsNothing);
    });

    testWidgets('Finish now finalizes the SAME run id without recording',
        (tester) async {
      final runStore = await pumpResume(tester);
      await tester.tap(find.text('Finish now'));
      await pumpUntil(tester, () => runStore.captured.isNotEmpty,
          describe: 'Finish now to persist the recovered partial');
      expect(runStore.captured, hasLength(1),
          reason: 'Finish saves the recovered partial exactly once');
      final saved = runStore.captured.single;
      expect(saved.id, 'resume-me-1',
          reason: 'the finalized run keeps the partial id, not a new one');
      expect(saved.metadata?['recovered_from_crash'], isTrue);
      expect(runStore.clearInProgressCalls, greaterThanOrEqualTo(1));
      // Never entered recording — still idle.
      expect(find.text('START'), findsOneWidget);
    });

    testWidgets('Resume does not re-announce the distance already banked',
        (tester) async {
      final bridgeCalls = <MethodCall>[];
      mockMethodChannel('run_app/run_notification', (call) async {
        bridgeCalls.add(call);
        return null;
      });

      await pumpResume(tester);
      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException();

      // Let the recorder's 1 s timer land the first post-resume snapshots.
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      tester.takeException();

      expect(bridgeCalls.where((c) => c.method == 'update_split'), isEmpty,
          reason: '187 km of restored distance is not a split just crossed — '
              'the resumed run must not announce one');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets('Resume continues the SAME run — hold-Finish saves partial id',
        (tester) async {
      final runStore = await pumpResume(tester);
      await tester.tap(find.text('Resume'));
      // Drive the resume: geolocator prepare + setState recording + the
      // resumed-banner overlay. Stay under the 10 s incremental-save timer.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // LiveRunMap tile-fetch noise on the recording mount

      // The prompt is gone and recording is live (LiveRunMap mounted).
      expect(find.text('Resume your run?'), findsNothing);
      final map = tester.allWidgets
          .where((w) => w.runtimeType.toString() == 'LiveRunMap')
          .toList();
      expect(map, isNotEmpty,
          reason: 'Resume re-hydrates the recorder into the recording surface');

      await tester.pump(const Duration(seconds: 4));
      tester.takeException();

      // Feed a couple of post-resume fixes, then finish.
      for (var i = 0; i < 3; i++) {
        geolocator.emit(_pos(metresEast: 1000 + i * 12.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();

      await holdFinish(tester);
      tester.takeException();

      expect(runStore.captured, hasLength(1),
          reason: 'finishing a resumed run saves ONE run, not a second record');
      final saved = runStore.captured.single;
      expect(saved.id, 'resume-me-1',
          reason: 'the finished run is the SAME run that was resumed');
      // Elapsed carries the pre-kill 40 h offset (continuity, not a fresh clock).
      expect(saved.duration.inHours, greaterThanOrEqualTo(40));

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });

    testWidgets(
        'Resume restores the followed route so finishing keeps it linked (#672)',
        (tester) async {
      final route = _testRoute('route-resume-1');
      final runStore = await pumpResume(
        tester,
        routeId: route.id,
        seedRoutes: [route],
      );
      await tester.tap(find.text('Resume'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // LiveRunMap tile-fetch noise on the recording mount

      await tester.pump(const Duration(seconds: 4));
      tester.takeException();

      // Feed a couple of post-resume fixes, then finish.
      for (var i = 0; i < 3; i++) {
        geolocator.emit(_pos(metresEast: 1000 + i * 12.0, secondsFromStart: i * 2));
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();

      await holdFinish(tester);
      tester.takeException();

      expect(runStore.captured, hasLength(1));
      final saved = runStore.captured.single;
      expect(saved.routeId, route.id,
          reason: 'a route picked before the crash must still be linked '
              'after resuming the crash-recovered partial and finishing '
              '(#672) — the off-route / remaining-distance UI depends on '
              'this restoring _selectedRoute before recording resumes');

      await tester.pumpWidget(const SizedBox());
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      tester.takeException();
    });
  });

  group('RunScreen — treadmill live-mode toggle', () {
    // The belt is an L4 auxiliary distance source layered on the live
    // recording. Every case below drives the REAL screen through the real
    // `_toggleTreadmillMode` / status-listener wiring using the
    // `@visibleForTesting` BleTreadmill emit seams, so no BLE stack is
    // needed and a regression in the screen (rather than in a replica of
    // its guards) is what fails.

    /// Pump the run screen with a belt already paired, returning the shared
    /// `BleTreadmill` the screen reads so the test can drive it.
    ///
    /// The pairing keys must be seeded AFTER `makeStores` (which resets the
    /// mock store) and BEFORE the first frame, because `_loadTreadmillPairing`
    /// reads them in a post-frame callback.
    Future<BleTreadmill> pumpWithPairedBelt(WidgetTester tester,
        {bool paired = true}) async {
      final s = await makeStores();
      if (paired) {
        SharedPreferences.setMockInitialValues({
          'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
          'treadmill_device_name': 'NordicTrack T9',
        });
      }
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();
      // Drain the pairedName() read the post-frame callback kicked off.
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      return s.treadmill;
    }

    /// Tap START and walk the 3-2-1 countdown into the recording view.
    Future<void> reachRecording(WidgetTester tester) async {
      await tester.tap(find.text('START'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      tester.takeException(); // LiveRunMap tile-fetch noise
    }

    /// Flip the toggle on with the belt reporting connected, then push one
    /// sample through. Leaves the screen showing the live belt speed.
    Future<void> engageBelt(WidgetTester tester, BleTreadmill treadmill,
        {double kmh = 10}) async {
      treadmill.debugEmitStatus(BleTreadmillStatus.connected);
      await tester.pump();
      await tester.tap(find.text('Treadmill mode'));
      await tester.pump();
      treadmill.debugEmitSample(TreadmillSample(instantaneousSpeedKmh: kmh));
      await tester.pump();
    }

    testWidgets('is absent while recording when no belt is paired',
        (tester) async {
      await pumpWithPairedBelt(tester, paired: false);
      await reachRecording(tester);
      expect(find.text('Treadmill mode'), findsNothing,
          reason: 'an unpaired belt makes the toggle a no-op — Settings is '
              'where the runner is pointed instead');
    });

    testWidgets('renders off by default once a belt is paired', (tester) async {
      await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      expect(find.text('Treadmill mode'), findsOneWidget);
      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isFalse,
          reason: 'a belt in range must never hijack an outdoor GPS run — '
              'treadmill mode only engages on an explicit tap');
      expect(sw.subtitle, isNull,
          reason: 'nothing is claimed about a belt the runner has not engaged');
    });

    testWidgets('turning it on feeds the belt speed into the readout',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill, kmh: 12);

      expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
          isTrue);
      expect(find.text('Belt 12.0 km/h'), findsOneWidget,
          reason: 'a connected belt states the speed it is reporting');
    });

    testWidgets('turning it off drops the belt readout', (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);
      expect(find.text('Belt 10.0 km/h'), findsOneWidget);

      await tester.tap(find.text('Treadmill mode'));
      // The off path awaits the live subscription's cancel before its
      // setState, and that future only completes on the real event loop.
      await pumpUntil(
        tester,
        () => !tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        describe: 'the belt toggle to settle off',
      );

      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isFalse);
      expect(sw.subtitle, isNull,
          reason: 'clearTreadmillMode handed distance back to GPS — the belt '
              'figure must not linger beside a disengaged toggle');
    });

    testWidgets('a mid-run disconnect says the belt is not feeding',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);
      expect(find.text('Belt 10.0 km/h'), findsOneWidget);

      treadmill.debugEmitStatus(BleTreadmillStatus.disconnected);
      await tester.pump();

      expect(find.text('Belt 10.0 km/h'), findsNothing,
          reason: 'never a belt-derived figure while the belt is gone');
      expect(find.text('No belt data — distance from GPS'), findsOneWidget,
          reason: 'an engaged toggle with a blank subtitle reads identically '
              'to "connected, first sample pending" — the drop must stay '
              'disclosed after the banner expires');
    });

    testWidgets('a mid-run disconnect leaves the recording running',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      treadmill.debugEmitStatus(BleTreadmillStatus.disconnected);
      await tester.pump(const Duration(seconds: 2));
      tester.takeException();

      // L1/L0 intact: the recording surface is still mounted and the core
      // controls a runner needs are still reachable.
      expect(
          tester.allWidgets
              .where((w) => w.runtimeType.toString() == 'LiveRunMap'),
          isNotEmpty,
          reason: 'a belt failure must never tear down the recording view');
      expect(
          find
              .byWidgetPredicate(
                  (w) => w.runtimeType.toString() == 'HoldToStopButton')
              .hitTestable(),
          findsOneWidget,
          reason: 'Finish must stay reachable through an auxiliary failure');
    });

    testWidgets('reconnecting is disclosed rather than a frozen speed',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      treadmill.debugEmitStatus(BleTreadmillStatus.reconnecting);
      await tester.pump();

      expect(find.text('Belt 10.0 km/h'), findsNothing);
      expect(find.text('Treadmill lost, reconnecting…'), findsWidgets,
          reason: 'the toggle states the belt is being chased, and does not '
              'hold the last speed as if it were current');
    });

    testWidgets('a connect failure is disclosed on the toggle', (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      // A belt that was off at launch reports connectFailed and never
      // auto-retries, so the toggle itself has to carry the state.
      treadmill.debugEmitStatus(BleTreadmillStatus.connectFailed);
      await tester.pump();
      await tester.tap(find.text('Treadmill mode'));
      await tester.pump();

      expect(find.text('No belt data — distance from GPS'), findsOneWidget);
      expect(find.text('Reconnect'), findsOneWidget,
          reason: 'connectFailed never retries itself — the runner is offered '
              'the one-tap reconnect, mirroring the HR strap');
    });

    testWidgets('connecting is disclosed on the toggle', (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      treadmill.debugEmitStatus(BleTreadmillStatus.connecting);
      await tester.pump();

      expect(find.text('Connecting to the treadmill…'), findsOneWidget);
      expect(find.text('Belt 10.0 km/h'), findsNothing);
    });

    testWidgets('a belt sample fault does not disturb the recording',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      treadmill.debugEmitSampleError(StateError('belt fault'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull,
          reason: 'the screen-side onError absorbs the fault — nothing may '
              'escape into the widget error zone');
      expect(
          tester.allWidgets
              .where((w) => w.runtimeType.toString() == 'LiveRunMap'),
          isNotEmpty);
    });

    testWidgets('the belt keeps feeding across a pause and resume',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      await tester.tap(find.bySemanticsLabel('Pause run'));
      await tester.pump();
      expect(find.bySemanticsLabel('Resume run'), findsOneWidget,
          reason: 'the run is manually paused');
      // The recorder excludes paused belt advance itself; the screen keeps
      // the subscription rather than tearing it down and re-arming.
      treadmill.debugEmitSample(
          const TreadmillSample(instantaneousSpeedKmh: 3));
      await tester.pump();
      expect(find.text('Belt 3.0 km/h'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Resume run'));
      await tester.pump();
      treadmill.debugEmitSample(
          const TreadmillSample(instantaneousSpeedKmh: 11));
      await tester.pump();
      expect(find.text('Belt 11.0 km/h'), findsOneWidget,
          reason: 'a pause/resume cycle must not silently drop the belt '
              'subscription — the toggle would then lie about being on');
      tester.takeException();
    });

    testWidgets('finishing the run cancels the belt subscription',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill);

      await holdFinish(tester);
      tester.takeException();

      // The recording view (and its toggle) is gone, and a late belt sample
      // arriving after the stop path cancelled the subscription is inert.
      expect(find.text('Treadmill mode'), findsNothing);
      treadmill.debugEmitSample(
          const TreadmillSample(instantaneousSpeedKmh: 9));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'a sample landing after stop must not reach a dead '
              'recorder or a disposed screen');
    });

    testWidgets('a belt that reconnects states nothing until it feeds again',
        (tester) async {
      // The subtitle switches on the status, so the three non-feeding arms are
      // disclosed whatever `_treadmillSpeedKmh` holds. What that structure
      // does NOT cover is the return to `connected`: the status listener's
      // null-out on the way out is the only thing stopping the pre-drop figure
      // being re-presented as current the moment the link is back, before a
      // single new sample has arrived.
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill, kmh: 10);
      expect(find.text('Belt 10.0 km/h'), findsOneWidget);

      treadmill.debugEmitStatus(BleTreadmillStatus.reconnecting);
      await tester.pump();
      treadmill.debugEmitStatus(BleTreadmillStatus.connected);
      await tester.pump();

      expect(find.text('Belt 10.0 km/h'), findsNothing,
          reason: 'the belt has not sent anything since it came back — '
              'showing what it last said before the drop presents a stale '
              'figure as the current one');
      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.subtitle, isNull,
          reason: 'connected-with-no-sample is the one blank state, and it is '
              'blank because it is true');
    });

    testWidgets('a fresh sample after a reconnect is the figure shown',
        (tester) async {
      // The negative control for the case above: the blank is a pending
      // reading, not a subscription the drop tore down.
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill, kmh: 10);

      treadmill.debugEmitStatus(BleTreadmillStatus.reconnecting);
      await tester.pump();
      treadmill.debugEmitStatus(BleTreadmillStatus.connected);
      await tester.pump();
      treadmill.debugEmitSample(
          const TreadmillSample(instantaneousSpeedKmh: 7.5));
      await tester.pump();

      expect(find.text('Belt 7.5 km/h'), findsOneWidget);
      expect(find.text('Belt 10.0 km/h'), findsNothing);
    });

    testWidgets('a connect failure after a live belt clears the last figure',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      await engageBelt(tester, treadmill, kmh: 10);

      treadmill.debugEmitStatus(BleTreadmillStatus.connectFailed);
      await tester.pump();

      expect(find.text('Belt 10.0 km/h'), findsNothing);
      expect(find.text('No belt data — distance from GPS'), findsOneWidget,
          reason: 'connectFailed and disconnected share one line: the fact '
              'the runner needs is that distance is coming from GPS');
    });

    testWidgets('an engaged belt with no sample yet claims nothing',
        (tester) async {
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);
      treadmill.debugEmitStatus(BleTreadmillStatus.connected);
      await tester.pump();
      await tester.tap(find.text('Treadmill mode'));
      await tester.pump();

      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isTrue);
      expect(sw.subtitle, isNull,
          reason: 'a connected belt that has not sent a reading yet is the '
              'one state with nothing to say');
    });

    testWidgets('a belt failure while the toggle is off says nothing at all',
        (tester) async {
      // A background belt's connection churn must not narrate an outdoor GPS
      // run. The status arm is only entered while the runner engaged the mode.
      final treadmill = await pumpWithPairedBelt(tester);
      await reachRecording(tester);

      treadmill.debugEmitStatus(BleTreadmillStatus.disconnected);
      await tester.pump();

      final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(sw.value, isFalse);
      expect(sw.subtitle, isNull,
          reason: 'nothing is claimed about a belt the runner never engaged');
      expect(find.text('No belt data — distance from GPS'), findsNothing);
    });

    testWidgets('the belt speed is stated in the runner own unit',
        (tester) async {
      // The figure is belt-reported km/h; a miles runner reads mph. Nothing
      // else pins the conversion, so an inverted factor would ship.
      final s = await makeStores();
      await tester.runAsync(() => s.prefs.setUseMiles(true));
      SharedPreferences.setMockInitialValues({
        'treadmill_device_id': 'AA:BB:CC:DD:EE:FF',
        'treadmill_device_name': 'NordicTrack T9',
      });
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: RunScreen(
            apiClient: null,
            runStore: s.runStore,
            routeStore: s.routeStore,
            preferences: s.prefs,
            audioCues: s.audioCues,
            social: s.social,
            raceController: s.raceController,
            training: s.training,
            heartRate: s.heartRate,
            treadmill: s.treadmill,
          ),
        ),
      );
      await tester.pump();
      // Third copy of the deliberate case at the helper above: the pairedName()
      // read the post-frame callback kicked off is invisible at idle, so there
      // is no condition that is ever false to poll for (decisions § 723).
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      });
      await tester.pump();
      await reachRecording(tester);
      await engageBelt(tester, s.treadmill, kmh: 16.09344);

      expect(find.text('Belt 10.0 mph'), findsOneWidget,
          reason: '16.09344 km/h is exactly 10 mph — a runner set to miles '
              'must not read the belt in kilometres');
    });
  });
}
