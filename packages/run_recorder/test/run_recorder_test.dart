import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
  // Zürich coordinates. 1 m east ≈ 1 / (111320 * cos(47.37°)) degrees of
  // longitude. Helpers keep the numbers readable in each test.
  const lat = 47.37;
  const lngBase = 8.54;
  const metrePerDegLng = 111320 * 0.6773;

  Position makePosition({
    required double metresEast,
    required int secondsFromStart,
    double accuracy = 5,
  }) {
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

  group('RunRecorder state machine', () {
    test('initial state is idle', () {
      final r = RunRecorder();
      expect(r.prepared, isFalse);
      expect(r.recording, isFalse);
      expect(r.debugElapsed, Duration.zero);
      expect(r.debugCurrentWaypoint, isNull);
    });

    test('debugPrepareWithoutStream flips to prepared', () {
      final r = RunRecorder();
      r.debugPrepareWithoutStream();
      expect(r.prepared, isTrue);
      expect(r.recording, isFalse);
    });

    test('begin() without prepare() throws', () {
      final r = RunRecorder();
      expect(r.begin, throwsStateError);
    });

    test('begin() after prepare flips to recording', () {
      final r = RunRecorder();
      r.debugPrepareWithoutStream();
      r.begin();
      expect(r.recording, isTrue);
      expect(r.prepared, isTrue);
    });
  });

  group('position filter chain', () {
    test('positions during prepared update the dot but not the track', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugCurrentWaypoint, isNotNull);
      expect(r.debugTrack, isEmpty);
      expect(r.debugDistanceMetres, 0);
    });

    test('first fix after begin is appended as the track anchor', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugTrack.length, 1);
      expect(r.debugDistanceMetres, 0); // no delta from a single point
    });

    test('accuracy filter drops fixes above 20m', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(
        makePosition(metresEast: 10, secondsFromStart: 3, accuracy: 50),
      );
      // Track should still only have the first point — bad-accuracy fix
      // dropped.
      expect(r.debugTrack.length, 1);
    });

    test('movement threshold rejects sub-3m jitter', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 2, secondsFromStart: 1));
      // Delta 2m < 3m threshold → not appended
      expect(r.debugTrack.length, 1);
      expect(r.debugDistanceMetres, 0);
    });

    test('real movement above threshold accumulates distance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 5, secondsFromStart: 2));
      expect(r.debugTrack.length, 2);
      expect(r.debugDistanceMetres, closeTo(5, 0.5));
    });

    test('speed clamp drops teleport-style jumps', () {
      // Run's max is 10 m/s. 200 m in 1 s = 200 m/s — clearly bogus.
      // But also < 100 m jump filter kicks in first, so use 50 m in 1 s.
      // 50 / 1 = 50 m/s, above the 10 m/s threshold → dropped.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 10);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 50, secondsFromStart: 1));
      // Track should reject the corrupt fix.
      expect(r.debugTrack.length, 1);
      expect(r.debugDistanceMetres, 0);
    });

    test('implausible single-hop jump (> 100m) is rejected', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      // 150 m in 60 s = 2.5 m/s (within speed clamp) but > 100 m hop filter.
      r.debugInjectPosition(
        makePosition(metresEast: 150, secondsFromStart: 60),
      );
      expect(r.debugTrack.length, 1);
      expect(r.debugDistanceMetres, 0);
    });
  });

  group('pause and resume', () {
    test('pause drops incoming positions completely', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 5, secondsFromStart: 2));
      r.pause();
      final trackLengthBeforeInjection = r.debugTrack.length;
      final distanceBeforeInjection = r.debugDistanceMetres;
      // Inject several positions while paused — none should be counted.
      r.debugInjectPosition(
        makePosition(metresEast: 20, secondsFromStart: 5),
      );
      r.debugInjectPosition(
        makePosition(metresEast: 40, secondsFromStart: 10),
      );
      expect(r.debugTrack.length, trackLengthBeforeInjection);
      expect(r.debugDistanceMetres, distanceBeforeInjection);
    });

    test('resume does not count the pause-duration gap as distance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 5, secondsFromStart: 2));
      final distanceBeforePause = r.debugDistanceMetres;

      r.pause();
      // User walks 50m to a cafe while paused, then resumes.
      r.resume();

      // Next real fix is 50m from where we paused.
      r.debugInjectPosition(
        makePosition(metresEast: 55, secondsFromStart: 120),
      );
      // Resume wipes _lastTrackedPosition, so the 50m gap is NOT counted.
      // The first post-resume fix is a new anchor. Distance is unchanged.
      expect(r.debugDistanceMetres, distanceBeforePause);
    });

    test('stopwatch stops during pause (monotonic clock)', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      await Future.delayed(const Duration(milliseconds: 50));
      r.pause();
      final afterPause = r.debugElapsed;
      await Future.delayed(const Duration(milliseconds: 50));
      // Clock should not have advanced during the pause.
      expect(r.debugElapsed, afterPause);
      r.resume();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(r.debugElapsed, greaterThan(afterPause));
    });
  });
}
