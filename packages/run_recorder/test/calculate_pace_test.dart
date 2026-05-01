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

    test('returns a positive pace once track has 5 points and ≥50m covered',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 2));
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugDistanceMetres, closeTo(200, 1));

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, greaterThan(0));
      expect(pace, lessThan(60 * 60));
    });

    test('returns null when wall-clock timestamps collapse to zero seconds',
        () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
      expect(r.debugTrack.length, 5);
      expect(r.debugDistanceMetres, closeTo(200, 1));
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('window slides — early-track samples beyond ~200m are excluded',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      for (int i = 0; i < 8; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
        await Future.delayed(const Duration(milliseconds: 5));
      }
      expect(r.debugTrack.length, 8);
      expect(r.debugDistanceMetres, closeTo(350, 2));

      final pace = r.debugPaceSecondsPerKm;
      expect(pace, isNotNull);
      expect(pace, greaterThan(0));
      expect(pace, lessThan(60 * 60));
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
