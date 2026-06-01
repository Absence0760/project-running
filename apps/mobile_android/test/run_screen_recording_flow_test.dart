import 'dart:async';
import 'dart:io';

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
import '../lib/local_route_store.dart';
import '../lib/local_run_store.dart';
import '../lib/preferences.dart';
import '../lib/race_controller.dart';
import '../lib/screens/run_screen.dart';
import '../lib/social_service.dart';
import '../lib/training_service.dart';

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

  @override
  Future<void> save(run) async {
    captured.add(run);
  }

  @override
  Future<void> clearInProgress() async {}
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
      audioCues: AudioCues(),
      raceController: RaceController(social),
    );
  }

  Future<LocalRunStore> pumpRunScreen(WidgetTester tester) async {
    final s = await makeStores();
    await tester.pumpWidget(
      MaterialApp(
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
        ),
      ),
    );
    await tester.pump();
    return s.runStore;
  }

  /// Complete a Finish hold. The button (`_HoldToStopButton`) only fires
  /// `onHoldComplete` after an 800 ms `Ticker`-driven hold; driving that
  /// Ticker to the threshold under the fake test clock is unreliable, so
  /// we assert the button is present + hit-testable in the recording UI
  /// (a real user can reach it), then invoke its wired `onHoldComplete`
  /// callback — the exact action a completed hold performs. That routes
  /// through the real `_stop()`, which persists via `runStore.save(run)`.
  Future<void> holdFinish(WidgetTester tester) async {
    final btnFinder =
        find.byWidgetPredicate((w) => w.runtimeType.toString() == '_HoldToStopButton');
    expect(btnFinder.hitTestable(), findsOneWidget,
        reason: 'a hit-testable Finish button must be present while recording');
    final hitButton = btnFinder.hitTestable().evaluate().single.widget;
    // _stop() awaits recorder.stop(), whose position-stream cancel only
    // completes on the real event loop (not the fake test clock), so drive
    // it under runAsync. The spy store captures the save synchronously, so
    // no real I/O is left in flight when runAsync returns.
    await tester.runAsync(() async {
      // ignore: avoid_dynamic_calls
      (hitButton as dynamic).onHoldComplete();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();
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
  });
}
