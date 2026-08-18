import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

/// Test fake for [GeolocatorPlatform]. Replaces the real platform
/// channel so [Geolocator.checkPermission], [Geolocator.requestPermission],
/// [Geolocator.isLocationServiceEnabled], and [Geolocator.getPositionStream]
/// all flow through configurable values + a controllable position stream.
///
/// Extends (not implements) so `PlatformInterface.verify` passes.
class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permissionState = LocationPermission.always;
  // The value that [requestPermission] returns. Defaults to mirroring
  // [permissionState] so simple tests don't need to set both.
  LocationPermission? requestPermissionResult;

  StreamController<Position>? _positions;
  Stream<Position> get positions => _positions!.stream;
  int subscriptionsOpened = 0;
  // Records the LocationSettings instance handed to each getPositionStream
  // call so tests can pin the per-platform Settings shape (Apple vs Android,
  // pauseLocationUpdatesAutomatically, activityType, FGS config, ...).
  final List<LocationSettings?> lastLocationSettings = <LocationSettings?>[];

  // When set, isLocationServiceEnabled parks on this completer — lets a test
  // hold the GPS retry loop mid-precheck while something else happens.
  Completer<bool>? serviceEnabledGate;

  @override
  Future<bool> isLocationServiceEnabled() async {
    final gate = serviceEnabledGate;
    if (gate != null) return gate.future;
    return serviceEnabled;
  }

  @override
  Future<LocationPermission> checkPermission() async => permissionState;

  @override
  Future<LocationPermission> requestPermission() async {
    final result = requestPermissionResult ?? permissionState;
    permissionState = result;
    return result;
  }

  @override
  Stream<Position> getPositionStream({LocationSettings? locationSettings}) {
    subscriptionsOpened++;
    lastLocationSettings.add(locationSettings);
    _positions ??= StreamController<Position>.broadcast();
    return _positions!.stream;
  }

  /// Push a synthetic position through the active stream. Mirrors what
  /// the real platform channel does when a fix arrives.
  void emit(Position p) {
    _positions ??= StreamController<Position>.broadcast();
    _positions!.add(p);
  }

  /// Send a stream-level error — production behaviour cancels the
  /// subscription on cancelOnError, then the retry loop reopens.
  void emitError(Object error) {
    _positions?.addError(error);
  }

  /// Force the underlying stream to close so a fresh `getPositionStream`
  /// call gets a new subscription. Lets tests count subscribe events.
  Future<void> resetStream() async {
    await _positions?.close();
    _positions = null;
  }

  Future<void> dispose() async {
    await _positions?.close();
    _positions = null;
  }
}

Position _pos({
  double metresEast = 0,
  int secondsFromStart = 0,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeGeolocatorPlatform fake;

  setUp(() {
    fake = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = fake;
  });

  tearDown(() async {
    await fake.dispose();
  });

  group('RunRecorder.prepare — error paths', () {
    test('throws LocationServiceDisabledError when services are off', () async {
      fake.serviceEnabled = false;
      final r = RunRecorder();
      await expectLater(
        r.prepare(),
        throwsA(isA<LocationServiceDisabledError>()),
      );
      // prepared flips to true even on error so begin() can still run a
      // time-only session — see the doc comment on prepare().
      expect(r.prepared, isTrue);
      r.dispose();
    });

    test('throws LocationPermissionDeniedError when permission is denied after request',
        () async {
      fake.permissionState = LocationPermission.denied;
      fake.requestPermissionResult = LocationPermission.denied;
      final r = RunRecorder();
      try {
        await r.prepare();
        fail('expected LocationPermissionDeniedError');
      } on LocationPermissionDeniedError catch (e) {
        expect(e.forever, isFalse);
      }
      r.dispose();
    });

    test('throws LocationPermissionDeniedError(forever: true) when deniedForever',
        () async {
      fake.permissionState = LocationPermission.deniedForever;
      final r = RunRecorder();
      try {
        await r.prepare();
        fail('expected LocationPermissionDeniedError(forever: true)');
      } on LocationPermissionDeniedError catch (e) {
        expect(e.forever, isTrue);
      }
      r.dispose();
    });

    test('records under a whileInUse grant on Android, flagging it as limited',
        () async {
      // Android's first-run dialog cannot grant more than "While using the
      // app" — "Allow all the time" is a separate trip to Settings. Refusing
      // the grant meant the DEFAULT Android runner got no position stream at
      // all: no fixes, a map stuck on "Waiting for GPS", distance frozen at
      // 0, the run saved as indoor. Foreground fixes work fine under it, so
      // the recorder records and reports the limitation instead.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      fake.permissionState = LocationPermission.whileInUse;
      final r = RunRecorder();
      await r.prepare();
      expect(r.prepared, isTrue);
      expect(
        fake.subscriptionsOpened,
        1,
        reason: 'a foreground-only grant must still open the position '
            'stream — the map and distance depend on it.',
      );
      expect(r.backgroundLocationLimited, isTrue,
          reason: 'the caller needs the limitation disclosed, not hidden.');
      r.dispose();
    });

    test('does NOT flag whileInUse as limited on iOS', () async {
      // iOS treats "While Using the App" + UIBackgroundModes:location as
      // a valid background-recording configuration — only Android needs
      // the escalation to "Allow all the time".
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      fake.permissionState = LocationPermission.whileInUse;
      final r = RunRecorder();
      await r.prepare();
      expect(r.prepared, isTrue);
      expect(r.backgroundLocationLimited, isFalse);
      r.dispose();
    });

    test('does NOT flag an always grant as limited on Android', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      fake.permissionState = LocationPermission.always;
      final r = RunRecorder();
      await r.prepare();
      expect(r.backgroundLocationLimited, isFalse);
      r.dispose();
    });

    test('clears backgroundLocationLimited when a later prepare is unrestricted',
        () async {
      // The runner upgrades to "Allow all the time" from Settings and starts
      // a second run: the stale flag must not keep warning them.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      fake.permissionState = LocationPermission.whileInUse;
      final r = RunRecorder();
      await r.prepare();
      expect(r.backgroundLocationLimited, isTrue);

      fake.permissionState = LocationPermission.always;
      await r.prepare();
      expect(r.backgroundLocationLimited, isFalse);
      r.dispose();
    });

    test('does NOT request permission when already granted', () async {
      fake.permissionState = LocationPermission.always;
      // If requestPermission is hit, it would return `denied` per our
      // override — and prepare() would then throw. Reaching the end
      // without throwing proves the granted path skipped the request.
      fake.requestPermissionResult = LocationPermission.denied;
      final r = RunRecorder();
      await r.prepare();
      expect(r.prepared, isTrue);
      r.dispose();
    });
  });

  group('RunRecorder.prepare — per-platform location settings', () {
    test('on iOS, passes AppleSettings with auto-pause OFF + fitness activity',
        () async {
      // Reason: CLLocationManager.pausesLocationUpdatesAutomatically defaults
      // to TRUE, which auto-pauses GPS the moment iOS thinks the user has
      // stopped moving — including pausing 30 s to take a picture. That is
      // the iOS twin of the Android whileInUse silent freeze. The recorder
      // MUST pin this to false. activityType.fitness biases CoreLocation's
      // power-saving heuristics for running pace.
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final r = RunRecorder();
      await r.prepare();
      expect(fake.lastLocationSettings, isNotEmpty);
      final settings = fake.lastLocationSettings.last;
      expect(
        settings,
        isA<AppleSettings>(),
        reason: 'iOS must receive AppleSettings, not AndroidSettings — '
            'passing AndroidSettings on iOS leaves the iOS-specific knobs '
            '(pauseLocationUpdatesAutomatically, activityType, '
            'showBackgroundLocationIndicator) at CoreLocation defaults.',
      );
      final apple = settings as AppleSettings;
      expect(
        apple.pauseLocationUpdatesAutomatically,
        isFalse,
        reason: 'pauseLocationUpdatesAutomatically MUST be false — true is '
            'the CoreLocation default and silently freezes the run when the '
            'user stops moving for a moment (the iOS twin of the Android '
            'whileInUse bug — same silent-freeze pattern, no error surface).',
      );
      expect(apple.activityType, ActivityType.fitness);
      expect(apple.distanceFilter, 0,
          reason: 'distanceFilter must stay 0 so every fix flows through '
              'software filtering (same rule as Android — see ADR §21).');
      expect(apple.allowBackgroundLocationUpdates, isTrue);
      r.dispose();
    });

    test('on Android, passes AndroidSettings with a ForegroundNotificationConfig',
        () async {
      // Reason: without a ForegroundNotificationConfig the geolocator
      // package falls back to a regular bound service, which Android puts
      // into CACHED state the moment the app is backgrounded — Samsung
      // Freecess then freezes the whole process and the position callback
      // queue drains to nothing. The FGS notification is what keeps the
      // process alive while another app holds the screen.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final r = RunRecorder();
      await r.prepare();
      final settings = fake.lastLocationSettings.last;
      expect(
        settings,
        isA<AndroidSettings>(),
        reason: 'Android must receive AndroidSettings so the FGS config '
            'gets applied.',
      );
      final android = settings as AndroidSettings;
      expect(
        android.foregroundNotificationConfig,
        isNotNull,
        reason: 'ForegroundNotificationConfig is what promotes the '
            'geolocator service to a typed foreground service — without it '
            'the process drops to CACHED + Samsung Freecess kills it.',
      );
      expect(android.distanceFilter, 0,
          reason: 'distanceFilter must stay 0 so every fix flows through '
              'software filtering (ADR §21).');
      r.dispose();
    });
  });

  group('RunRecorder.prepare — happy path + stream wiring', () {
    test('opens the position stream after prepare succeeds', () async {
      final r = RunRecorder();
      await r.prepare();
      // First subscribe was the prepare call itself.
      expect(fake.subscriptionsOpened, greaterThanOrEqualTo(1));
      r.dispose();
    });

    test('positions emitted by the fake flow through the filter chain', () async {
      final r = RunRecorder();
      await r.prepare();
      // Drain the post-prepare async setup before emitting so the
      // listen() callback is wired up.
      await Future<void>.delayed(Duration.zero);

      // Pre-begin: positions update the dot but not the track.
      fake.emit(_pos(metresEast: 0, secondsFromStart: 0));
      await Future<void>.delayed(Duration.zero);
      expect(r.debugCurrentWaypoint, isNotNull);
      expect(r.debugTrack, isEmpty);

      r.begin();
      // First post-begin fix becomes the anchor.
      fake.emit(_pos(metresEast: 0, secondsFromStart: 1));
      await Future<void>.delayed(Duration.zero);
      expect(r.debugTrack.length, 1);

      // Subsequent fix above the movement threshold accumulates distance.
      fake.emit(_pos(metresEast: 10, secondsFromStart: 3));
      await Future<void>.delayed(Duration.zero);
      expect(r.debugDistanceMetres, greaterThan(5));

      r.dispose();
    });

    test('stream onError tears down the subscription', () async {
      final r = RunRecorder();
      await r.prepare();
      await Future<void>.delayed(Duration.zero);

      fake.emit(_pos(metresEast: 0, secondsFromStart: 0));
      await Future<void>.delayed(Duration.zero);
      expect(r.debugCurrentWaypoint, isNotNull);

      // After a stream error, the subscription is cancelled. The retry
      // loop will re-open it, but we don't drive that here — we just
      // verify the recorder doesn't blow up when an error arrives.
      fake.emitError(Exception('platform stream torn down'));
      await Future<void>.delayed(Duration.zero);
      // Subsequent emits on the same stream still resolve (broadcast
      // controller stays open in the fake), but the recorder's
      // subscription is gone — no new positions land.
      // (Asserting the subscription state directly would require
      // exposing a private — this test just pins "no exception".)
      r.dispose();
    });
  });

  group('RunRecorder — GPS retry loop honours prepare()\'s permission gate (#671)',
      () {
    test(
      'does NOT silently open a stream ~3s after a denied prepare() failure',
      () async {
        // #671: the retry loop must not reopen a stream prepare() has just
        // refused to open for the same permission state — a run that told
        // the user GPS was unavailable must not start tracking three
        // seconds later with no notice.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        fake.permissionState = LocationPermission.deniedForever;
        final r = RunRecorder();
        await expectLater(
          r.prepare(),
          throwsA(isA<LocationPermissionDeniedError>()),
        );
        expect(fake.subscriptionsOpened, 0,
            reason: 'prepare() must not open the stream when permission is '
                'denied.');

        // The retry loop's interval is 3s — wait past at least one tick.
        await Future<void>.delayed(const Duration(seconds: 4));

        expect(
          fake.subscriptionsOpened,
          0,
          reason: 'The retry loop\'s precheck must bail on a denied grant '
              'just like prepare() does — it must not open a stream '
              'permission still forbids.',
        );
        r.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'DOES open the stream once permission is later granted',
      () async {
        // The legitimate flip side of the same gate: a runner who denied the
        // dialog can relent from Settings mid-run. The retry loop must still
        // pick that up — the gate must not turn the loop into a permanent
        // no-op once prepare() has failed once.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        fake.permissionState = LocationPermission.deniedForever;
        final r = RunRecorder();
        await expectLater(
          r.prepare(),
          throwsA(isA<LocationPermissionDeniedError>()),
        );
        expect(fake.subscriptionsOpened, 0);

        fake.permissionState = LocationPermission.always;

        await Future<void>.delayed(const Duration(seconds: 4));

        expect(
          fake.subscriptionsOpened,
          greaterThanOrEqualTo(1),
          reason: 'Once permission is granted, the retry loop must open the '
              'stream — the gate must not break the retry-after-grant path.',
        );
        r.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test(
      'a whileInUse grant needs no retry — prepare() already opened the stream',
      () async {
        // The regression this whole change exists to prevent: an Android
        // runner on the default first-run grant must be tracking from the
        // moment prepare() returns, not waiting on a retry that never fires.
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        fake.permissionState = LocationPermission.whileInUse;
        final r = RunRecorder();
        await r.prepare();
        expect(fake.subscriptionsOpened, 1);

        await Future<void>.delayed(const Duration(seconds: 4));

        expect(
          fake.subscriptionsOpened,
          1,
          reason: 'the healthy stream must be left alone — the retry loop '
              'is a repair path, not a second subscriber.',
        );
        r.dispose();
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('RunRecorder.dispose', () {
    test('cancels the position subscription so the recorder stops processing fixes',
        () async {
      final r = RunRecorder();
      await r.prepare();
      await Future<void>.delayed(Duration.zero);

      r.begin();
      fake.emit(_pos(metresEast: 0, secondsFromStart: 0));
      await Future<void>.delayed(Duration.zero);
      final firstTrackLen = r.debugTrack.length;
      expect(firstTrackLen, 1);

      r.dispose();

      // After dispose, further fixes should NOT extend the track.
      fake.emit(_pos(metresEast: 50, secondsFromStart: 5));
      await Future<void>.delayed(Duration.zero);
      expect(r.debugTrack.length, firstTrackLen,
          reason: 'dispose should have cancelled the position subscription');
    });

    test(
      'a retry callback in flight during dispose cannot re-open the stream',
      () async {
        // The retry loop awaits its service/permission precheck. A callback
        // parked on that await when the recorder is disposed used to resume and
        // subscribe again — a subscription nothing is left to cancel, holding
        // the GPS radio and the foreground service for the life of the process
        // while every fix raised on the closed snapshot sink.
        final r = RunRecorder();
        await r.prepare();
        await Future<void>.delayed(Duration.zero);
        r.begin();
        expect(fake.subscriptionsOpened, 1);

        // Tear the stream down so the retry loop has work to do, and park its
        // precheck.
        final gate = Completer<bool>();
        fake.serviceEnabledGate = gate;
        fake.emitError(Exception('platform stream torn down'));
        await Future<void>.delayed(Duration.zero);

        // Wait past a retry tick (the interval is 3 s) so a callback is parked
        // on the gate, then dispose while it is still in flight.
        await Future<void>.delayed(const Duration(seconds: 4));
        r.dispose();
        gate.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(fake.subscriptionsOpened, 1,
            reason: 'dispose must be terminal — no stream may be opened after '
                'it, whatever was already in flight');

        // Nothing is listening, but a re-opened stream would push this fix
        // through _emitSnapshot and raise on the closed controller.
        fake.emit(_pos(metresEast: 50, secondsFromStart: 5));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(r.debugTrack, isEmpty);
      },
      timeout: const Timeout(Duration(seconds: 20)),
    );

    test('prepare() after dispose() throws rather than returning a zombie',
        () async {
      final r = RunRecorder();
      await r.prepare();
      r.dispose();
      await expectLater(r.prepare(), throwsA(isA<StateError>()));
      expect(r.prepared, isFalse);
      expect(fake.subscriptionsOpened, 1);
    });
  });
}
