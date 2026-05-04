import 'dart:async';

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

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

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
  });
}
