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
    double altitude = 400,
    double altitudeAccuracy = 2,
  }) {
    return Position(
      longitude: lngBase + metresEast / metrePerDegLng,
      latitude: lat,
      timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      accuracy: accuracy,
      altitude: altitude,
      altitudeAccuracy: altitudeAccuracy,
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

  group('elevation sentinel', () {
    test('altitude 0.0 with a valid accuracy is kept (sea-level fix)', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.debugInjectPosition(makePosition(
        metresEast: 0,
        secondsFromStart: 0,
        altitude: 0,
        altitudeAccuracy: 3,
      ));
      expect(r.debugCurrentWaypoint!.elevationMetres, 0);
    });

    test('altitude 0.0 with no vertical fix is null', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.debugInjectPosition(makePosition(
        metresEast: 0,
        secondsFromStart: 0,
        altitude: 0,
        altitudeAccuracy: 0,
      ));
      expect(r.debugCurrentWaypoint!.elevationMetres, isNull);
    });

    test('altitude with a non-finite accuracy is null', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.debugInjectPosition(makePosition(
        metresEast: 0,
        secondsFromStart: 0,
        altitude: 120,
        altitudeAccuracy: double.nan,
      ));
      expect(r.debugCurrentWaypoint!.elevationMetres, isNull);
    });

    test('a real altitude with a valid accuracy is kept', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.debugInjectPosition(makePosition(
        metresEast: 0,
        secondsFromStart: 0,
        altitude: 412.5,
        altitudeAccuracy: 2,
      ));
      expect(r.debugCurrentWaypoint!.elevationMetres, 412.5);
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

    test('accuracy-gate drop sets weakGps; a good fix clears it', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugWeakGps, isFalse,
          reason: 'a clean fix must not raise the weak-GPS flag');
      r.debugInjectPosition(
        makePosition(metresEast: 10, secondsFromStart: 3, accuracy: 50),
      );
      expect(r.debugWeakGps, isTrue,
          reason: 'a fix above the accuracy gate stalls distance — flag it');
      r.debugInjectPosition(
        makePosition(metresEast: 12, secondsFromStart: 6, accuracy: 8),
      );
      expect(r.debugWeakGps, isFalse,
          reason: 'a fix back within the gate clears the weak-GPS flag');
    });

    test('weakGps surfaces on the emitted snapshot', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      final received = <RunSnapshot>[];
      final sub = r.snapshots.listen(received.add);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(
        makePosition(metresEast: 10, secondsFromStart: 3, accuracy: 50),
      );
      // The dropped fix doesn't emit; the 1 s timer carries the flag forward.
      await Future.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();
      await r.stop();
      expect(received.last.weakGps, isTrue);
    });

    test('default accuracy gate accepts realistic ~15m GPS fixes', () {
      // Regression guard: an earlier Advanced-GPS path tightened the gate to
      // 10m, which silently rejected almost every real-world fix (phones
      // routinely report 15–30m horizontal accuracy outdoors). If the default
      // prepare params ever drop below this, the live map freezes and
      // distance stays at 0 in Advanced mode.
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(
        makePosition(metresEast: 0, secondsFromStart: 0, accuracy: 15),
      );
      r.debugInjectPosition(
        makePosition(metresEast: 5, secondsFromStart: 2, accuracy: 15),
      );
      expect(r.debugCurrentWaypoint, isNotNull);
      expect(r.debugTrack.length, 2);
      expect(r.debugDistanceMetres, closeTo(5, 0.5));
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

    test('teleport on a duplicate (zero-dt) GPS timestamp is rejected', () {
      // Two fixes sharing a timestamp (batched/queued fixes, or a clock
      // correction): dt = 0 makes speed undefined. A 90 m hop must not slip
      // through the < 100 m filter — the speed clamp can't vet it.
      final r = RunRecorder()..debugPrepareWithoutStream(maxSpeedMps: 10);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 5));
      r.debugInjectPosition(makePosition(metresEast: 90, secondsFromStart: 5));
      expect(r.debugTrack.length, 1);
      expect(r.debugDistanceMetres, 0);
    });

    test('zero-dt rejection is lossless — next valid fix still accumulates', () {
      // After a rejected same-timestamp fix, a later fix with a real
      // timestamp accumulates the delta from the last good position over the
      // true elapsed time (20 m in 10 s = 2 m/s, within the clamp).
      final r = RunRecorder()..debugPrepareWithoutStream(maxSpeedMps: 10);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 90, secondsFromStart: 0));
      expect(r.debugDistanceMetres, 0);
      r.debugInjectPosition(makePosition(metresEast: 20, secondsFromStart: 10));
      expect(r.debugDistanceMetres, closeTo(20, 0.5));
      expect(r.debugTrack.length, 2);
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

  group('indoor / no-GPS mode', () {
    test('RunSnapshot.currentPosition is nullable', () {
      const snap = RunSnapshot(
        elapsed: Duration(seconds: 10),
        distanceMetres: 0,
        currentPosition: null,
      );
      expect(snap.currentPosition, isNull);
      expect(snap.elapsed, const Duration(seconds: 10));
      expect(snap.distanceMetres, 0);
      expect(snap.track, isEmpty);
    });

    test('timer emits a null-position snapshot when begin() runs without fixes',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      final received = <RunSnapshot>[];
      final sub = r.snapshots.listen(received.add);
      r.begin();
      // The periodic timer fires at 1-second intervals; wait a hair longer
      // so at least one tick lands even on a slow CI runner.
      await Future.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();
      await r.stop();
      expect(received, isNotEmpty,
          reason: 'Timer should fire without a GPS fix (indoor mode)');
      expect(received.last.currentPosition, isNull);
      expect(received.last.distanceMetres, 0);
      expect(received.last.track, isEmpty);
      expect(received.last.elapsed, greaterThan(Duration.zero));
    });

    test('injected fix during indoor mode populates currentPosition', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // Indoor timer-driven snapshot would have currentPosition == null.
      // When a fix arrives, currentPosition populates and future snapshots
      // carry it.
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugCurrentWaypoint, isNotNull);
      expect(r.debugTrack.length, 1);
    });

    test('setHeartRate stamps subsequent waypoints with per-point BPM', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // No HR yet → first waypoint carries bpm:null.
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugTrack.last.bpm, isNull,
          reason: 'no setHeartRate yet → no bpm on the waypoint');

      r.setHeartRate(142);
      r.debugInjectPosition(makePosition(metresEast: 5, secondsFromStart: 2));
      expect(r.debugTrack.last.bpm, 142,
          reason: 'setHeartRate value must apply to the next waypoint');

      // Clear the strap reading (e.g. dropped connection); future
      // waypoints stop carrying BPM.
      r.setHeartRate(null);
      r.debugInjectPosition(makePosition(metresEast: 10, secondsFromStart: 4));
      expect(r.debugTrack.last.bpm, isNull,
          reason: 'setHeartRate(null) clears the stamp');
    });

    test('setHeartRate ignores out-of-range readings', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setHeartRate(155);
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      expect(r.debugTrack.last.bpm, 155);

      // A bogus 250 BPM reading from a flaky strap mustn't clobber the
      // good value — hr_zones drops < 30 and > 230 anyway, so silently
      // dropping at the recorder keeps the saved track clean.
      r.setHeartRate(250);
      r.debugInjectPosition(makePosition(metresEast: 5, secondsFromStart: 2));
      expect(r.debugTrack.last.bpm, 155,
          reason: 'out-of-range readings must be ignored, preserving the '
              'last known good value');
    });
  });

  group('treadmill distance source (additive, opt-in seam)', () {
    test('off by default — distance comes from GPS untouched', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      expect(r.debugTreadmillMode, isFalse);
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 10, secondsFromStart: 5));
      expect(r.debugReportedDistanceMetres, closeTo(10, 0.5),
          reason: 'GPS distance is reported when treadmill mode is off');
    });

    test('belt total distance is rebased to 0 on the first sample', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // Belt was already showing 200 m when the run started.
      r.setTreadmillSample(2.5, totalDistanceMetres: 200);
      r.setTreadmillSample(2.5, totalDistanceMetres: 350);
      expect(r.debugTreadmillMode, isTrue);
      expect(r.debugReportedDistanceMetres, 150.0,
          reason: 'pre-run belt distance must not be credited');
    });

    test('belt distance overrides GPS distance once in treadmill mode', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 30, secondsFromStart: 10));
      // A spurious GPS fix exists, but the belt is authoritative now.
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1500);
      expect(r.debugReportedDistanceMetres, 500.0);
      expect(r.debugDistanceMetres, greaterThan(0),
          reason: 'GPS accumulator keeps running underneath, untouched');
    });

    test('speed integration when the belt reports no total distance', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // First sample sets the baseline timestamp; no distance yet.
      r.setTreadmillSample(2.0);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      r.setTreadmillSample(2.0);
      // ~0.1s at the previous 2.0 m/s ≈ 0.2 m. Allow generous slop for the
      // wall-clock delay under test load.
      expect(r.debugReportedDistanceMetres, greaterThan(0));
      expect(r.debugReportedDistanceMetres, lessThan(2.0));
    });

    test('an extreme belt sample never breaks recording (layered resilience)',
        () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // 999 m/s is rejected by the integration clamp; recording stays alive.
      r.setTreadmillSample(999);
      r.setTreadmillSample(999);
      expect(r.recording, isTrue);
    });

    test('a bogus belt sample is not carried forward to poison the next interval',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // Good baseline, then a glitch, then a good reading. The glitch is
      // rejected for its OWN interval — but it must also not become the
      // integrand for the NEXT interval. With the bug the final good sample
      // integrated the stored 999 m/s (≈ 999 × 0.05 s ≈ 50 m of phantom
      // distance); fixed, it integrates the last GOOD 2.0 m/s (≈ 0.1 m).
      r.setTreadmillSample(2.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.setTreadmillSample(999);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.setTreadmillSample(2.0);
      expect(r.debugReportedDistanceMetres, lessThan(2.0),
          reason: 'a single glitch reading must not inject phantom distance');
    });

    test('clearTreadmillMode reverts to the GPS distance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 20, secondsFromStart: 8));
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1200);
      expect(r.debugReportedDistanceMetres, 200.0);
      r.clearTreadmillMode();
      expect(r.debugTreadmillMode, isFalse);
      expect(r.debugReportedDistanceMetres, closeTo(20, 0.5));
    });

    test('stop() tags an indoor treadmill run in metadata', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(2.5, totalDistanceMetres: 100);
      r.setTreadmillSample(2.5, totalDistanceMetres: 600);
      final run = await r.stop();
      expect(run.distanceMetres, 500.0);
      expect(run.metadata?['indoor'], isTrue);
      expect(run.metadata?['indoor_source'], 'treadmill');
      expect(run.metadata?['distance_source'], 'treadmill');
    });

    test('stop() on a normal GPS run carries no indoor metadata', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 10, secondsFromStart: 4));
      final run = await r.stop();
      expect(run.metadata?['indoor'], isNull);
      expect(run.metadata?['indoor_source'], isNull);
    });

    test('lap() records belt distance in treadmill mode, not GPS', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // GPS accumulator runs underneath, but the belt is authoritative.
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 15, secondsFromStart: 6));
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1400);
      r.lap();
      expect(r.laps.last.cumulativeDistanceMetres, 400.0,
          reason: 'a treadmill lap split must use belt distance, not GPS');
    });

    test('belt distance accrued while paused is not credited', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000); // baseline
      r.setTreadmillSample(3.0, totalDistanceMetres: 1300); // 300 m run
      expect(r.debugReportedDistanceMetres, 300.0);
      r.pause();
      // Belt keeps counting during the pause (user idling on a running belt).
      r.setTreadmillSample(3.0, totalDistanceMetres: 1600);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1900);
      expect(r.debugReportedDistanceMetres, 300.0,
          reason: 'paused belt advance must not inflate the distance');
      r.resume();
      r.setTreadmillSample(3.0, totalDistanceMetres: 2000);
      expect(r.debugReportedDistanceMetres, 400.0,
          reason: 'distance resumes from the frozen pre-pause value');
    });

    test('speed-only belt does not credit the pause gap after resume',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      // Speed-only belt (no totalDistanceMetres): establish a moving anchor.
      r.setTreadmillSample(3.0);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      r.setTreadmillSample(3.0);
      final beforePause = r.debugReportedDistanceMetres;
      r.pause();
      // A real-world short pause (tie a shoe) shorter than the 30 s dtSec
      // clamp. With the bug the first post-resume sample integrated 3 m/s
      // back across this whole gap (~0.6 m of phantom distance here, and a
      // jog × a 20 s pause would be tens of metres).
      await Future<void>.delayed(const Duration(milliseconds: 200));
      r.resume();
      r.setTreadmillSample(3.0);
      expect(r.debugReportedDistanceMetres, closeTo(beforePause, 0.01),
          reason: 'the paused interval must not be credited as belt distance');
    });
  });
}
