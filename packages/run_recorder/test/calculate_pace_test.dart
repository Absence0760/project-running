import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:run_recorder/run_recorder.dart';

void main() {
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

  group('_calculatePace via debugPaceSecondsPerKm', () {
    test('returns null when track is empty', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns null when track has fewer than 5 points', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 4; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
      expect(r.debugTrack.length, 4);
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns null when total tracked distance is below 50m', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 6; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 4.0, secondsFromStart: i * 5),
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }
      expect(r.debugTrack.length, greaterThanOrEqualTo(5));
      expect(r.debugDistanceMetres, lessThan(50));
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('returns the GPS-derived pace once track has 5 points and ≥50m', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugDistanceMetres, closeTo(200, 1));

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, closeTo(200, 1));
    });

    test('synchronous inject loop still produces a non-null pace', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugPaceSecondsPerKm, isNotNull);
      expect(r.debugPaceSecondsPerKm, closeTo(200, 1));
    });

    test('window slides — early-slow segments excluded from pace', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 50, secondsFromStart: 60));
      r.debugInjectPosition(makePosition(metresEast: 100, secondsFromStart: 120));
      r.debugInjectPosition(makePosition(metresEast: 150, secondsFromStart: 130));
      r.debugInjectPosition(makePosition(metresEast: 200, secondsFromStart: 140));
      r.debugInjectPosition(makePosition(metresEast: 250, secondsFromStart: 150));
      r.debugInjectPosition(makePosition(metresEast: 300, secondsFromStart: 160));
      r.debugInjectPosition(makePosition(metresEast: 350, secondsFromStart: 170));

      expect(r.debugTrack.length, 8);

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, closeTo(200, 5));
    });

    test('snapshot stream reports the same pace value as debugPaceSecondsPerKm',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      final received = <double?>[];
      final sub = r.snapshots.listen((s) => received.add(s.currentPaceSecondsPerKm));
      r.begin();
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 3));
      }
      await Future.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      await r.stop();

      expect(received, isNotEmpty);
      expect(received.last, r.debugPaceSecondsPerKm);
    });

    test('pace stays null while paused (no new track points)', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      await Future.delayed(const Duration(milliseconds: 2));
      r.debugInjectPosition(makePosition(metresEast: 50, secondsFromStart: 10));
      await Future.delayed(const Duration(milliseconds: 2));
      r.pause();

      for (int i = 2; i < 6; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }

      expect(r.debugTrack.length, 2);
      expect(r.debugPaceSecondsPerKm, isNull);
    });
  });
}
