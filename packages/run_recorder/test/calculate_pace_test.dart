import 'package:flutter_test/flutter_test.dart';
import 'package:core_models/core_models.dart';
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

  group('pace never spans a pause or a resumed-session gap', () {
    /// Five accepted fixes at a true 200 s/km, ending 200 m along at t=40 s.
    void runPrePauseLeg(RunRecorder r) {
      for (int i = 0; i < 5; i++) {
        r.debugInjectPosition(
          makePosition(metresEast: i * 50.0, secondsFromStart: i * 10),
        );
      }
    }

    test('a 10-minute pause is not charged to the post-resume distance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      // The runner rests 600 s at an aid station without moving, then resumes
      // and covers 75 m in 25 s (3 m/s -> 333 s/km).
      r.resume();
      for (int i = 0; i < 6; i++) {
        r.debugInjectPosition(makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: 640 + i * 5,
        ));
      }
      // Walking back across the pause billed 225 m against 645 s of wall clock
      // and reported ~2866 s/km — which run_screen feeds to the pace-alert and
      // cut-off catch-up voice cues.
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });

    test('pace is null until enough post-resume fixes exist', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      expect(r.debugPaceSecondsPerKm, isNotNull);
      r.pause();
      r.resume();
      // Two post-resume points is below the 5-point smoothing floor, so the
      // honest answer is "unknown" rather than a pace timed off a stale fix.
      r.debugInjectPosition(
          makePosition(metresEast: 200, secondsFromStart: 640));
      r.debugInjectPosition(
          makePosition(metresEast: 250, secondsFromStart: 650));
      expect(r.debugPaceSecondsPerKm, isNull);
    });

    test('pace recovers to the true value once the post-resume leg is long',
        () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      r.resume();
      // 300 m post-resume at a true 200 s/km — past the ~200 m window, so the
      // walk never reaches the floor and the answer is the normal rolling pace.
      for (int i = 0; i < 7; i++) {
        r.debugInjectPosition(makePosition(
          metresEast: 200 + i * 50.0,
          secondsFromStart: 640 + i * 10,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(200, 10));
    });

    test('repeated pauses each reseal the window', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      addTearDown(r.dispose);
      r.begin();
      runPrePauseLeg(r);
      r.pause();
      r.resume();
      for (int i = 0; i < 6; i++) {
        r.debugInjectPosition(makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: 640 + i * 5,
        ));
      }
      r.pause();
      r.resume();
      for (int i = 0; i < 6; i++) {
        r.debugInjectPosition(makePosition(
          metresEast: 275 + i * 15.0,
          secondsFromStart: 1300 + i * 5,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });

    test('a resumed session does not time against the pre-kill track', () {
      // The seeded track's last timestamp can be up to kResumableWindow (48 h)
      // old, so timing the first post-resume metres against it reported a pace
      // hundreds of times too slow.
      final seeded = [
        for (int i = 0; i < 5; i++)
          Waypoint(
            lat: lat,
            lng: lngBase + (i * 50.0) / metrePerDegLng,
            timestamp: DateTime(2026, 4, 9, 10, 0, i * 10),
          ),
      ];
      final r = RunRecorder()
        ..debugResumeWithoutStream(
          track: seeded,
          distanceMetres: 200,
          elapsed: const Duration(seconds: 40),
          startedAt: DateTime(2026, 4, 9, 10, 0),
        );
      addTearDown(r.dispose);
      expect(r.debugPaceSecondsPerKm, isNull,
          reason: 'the seeded track is all pre-kill — nothing to time yet');
      for (int i = 0; i < 6; i++) {
        r.debugInjectPosition(makePosition(
          metresEast: 200 + i * 15.0,
          secondsFromStart: i * 5,
        ));
      }
      expect(r.debugPaceSecondsPerKm, closeTo(333, 20));
    });
  });
}
