import 'package:core_models/core_models.dart';
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

    test('implausible short-interval single-hop jump (> 100m) is rejected', () {
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      // 150 m in 5 s = 30 m/s (within the loosened speed clamp) but > 100 m
      // hop filter, and only 5 s elapsed (< the 10 s gap re-anchor window) so
      // this is a corrupt teleport, not a real gap: rejected, anchor unmoved.
      r.debugInjectPosition(
        makePosition(metresEast: 150, secondsFromStart: 5),
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

    test('GPS gap > 100m re-anchors and resumes tracking (#330)', () {
      // A real dropout — fixes rejected under cover / in a tunnel / while
      // backgrounded — while the runner keeps moving. The first fix back is
      // > 100 m from the stale anchor but a genuine interval has elapsed, so
      // the anchor rebases to it WITHOUT crediting the un-sampled gap, and
      // ordinary movement accumulates again from the new anchor.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      // 150 m gap over 60 s (> the 10 s re-anchor window): rebase, no credit.
      r.debugInjectPosition(makePosition(metresEast: 150, secondsFromStart: 60));
      expect(r.debugDistanceMetres, 0);
      expect(r.debugTrack.length, 2);
      // Normal movement from the re-anchored position now accumulates.
      r.debugInjectPosition(makePosition(metresEast: 160, secondsFromStart: 70));
      expect(r.debugDistanceMetres, closeTo(10, 0.5));
      expect(r.debugTrack.length, 3);
    });

    test('consecutive post-gap fixes do not stay stuck on stale anchor (#330)',
        () {
      // Regression guard: before the time-based re-anchor, once the runner was
      // > 100 m from the anchor every later fix only grew the delta, so the
      // anchor could never re-qualify and distance was frozen for the rest of
      // the run. Inject three fixes each further away after a gap; the first
      // rebases and the next two accumulate the real movement between them.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      // 200 m gap over 60 s → re-anchor at 200 m, nothing credited.
      r.debugInjectPosition(makePosition(metresEast: 200, secondsFromStart: 60));
      r.debugInjectPosition(makePosition(metresEast: 230, secondsFromStart: 70));
      r.debugInjectPosition(makePosition(metresEast: 260, secondsFromStart: 80));
      // 30 m + 30 m of real movement after the re-anchor; the 200 m gap itself
      // is never credited.
      expect(r.debugDistanceMetres, closeTo(60, 1.0));
      expect(r.debugTrack.length, 4);
    });

    test('> 100m hop within the gap window (short dt) still fails closed (#330)',
        () {
      // A > 100 m hop that arrives BEFORE the re-anchor window (dt < 10 s, but
      // dt > 0) is a corrupt teleport, not a gap: it must keep failing closed
      // so a single bad fix can't move the anchor onto a glitch location.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      r.debugInjectPosition(makePosition(metresEast: 150, secondsFromStart: 8));
      expect(r.debugDistanceMetres, 0);
      expect(r.debugTrack.length, 1);
    });

    test('zero-dt duplicate teleport still fails closed after re-anchor (#330)',
        () {
      // The re-anchor must not open a hole for the zero-dt duplicate case:
      // two fixes sharing a timestamp give dt = 0, which is < the re-anchor
      // window, so a 120 m hop is still rejected.
      final r = RunRecorder()
        ..debugPrepareWithoutStream(maxSpeedMps: 1000);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 30));
      r.debugInjectPosition(makePosition(metresEast: 120, secondsFromStart: 30));
      expect(r.debugDistanceMetres, 0);
      expect(r.debugTrack.length, 1);
    });
  });

  group('snapshot fix provenance', () {
    // The snapshot stream is a broadcast controller: `add` delivers on a
    // microtask, so a synchronous inject is not visible to the listener yet.
    Future<void> pumpStream() => Future<void>.delayed(Duration.zero);

    test('positionFixedAt does not advance on a timer-only emit', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      final received = <RunSnapshot>[];
      final sub = r.snapshots.listen(received.add);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      await pumpStream();
      final fixedAt = received.last.positionFixedAt;
      expect(fixedAt, isNotNull,
          reason: 'an accepted fix must stamp its acceptance time');
      // No further fixes — only the 1 s timer emits from here.
      await Future.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();
      await r.stop();
      expect(received.last.currentPosition, isNotNull,
          reason: 'the last fix keeps driving the blue dot');
      expect(received.last.positionFixedAt, fixedAt,
          reason: 'a timer-driven emit re-carries the OLD fix — its age is '
              'what tells a consumer the sensor has gone quiet');
    });

    test('positionFixedAt is null until the first fix lands', () async {
      final r = RunRecorder()..debugPrepareWithoutStream();
      final received = <RunSnapshot>[];
      final sub = r.snapshots.listen(received.add);
      r.begin();
      await Future.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();
      await r.stop();
      expect(received, isNotEmpty);
      expect(received.last.positionFixedAt, isNull,
          reason: 'no fix has arrived, so there is no fix age to report — '
              'the GPS-lost banner must stay dormant during warmup');
    });

    test('a rejected teleport is published as an untrusted position',
        () async {
      final r = RunRecorder()..debugPrepareWithoutStream(maxSpeedMps: 1000);
      final received = <RunSnapshot>[];
      final sub = r.snapshots.listen(received.add);
      r.begin();
      r.debugInjectPosition(makePosition(metresEast: 0, secondsFromStart: 0));
      await pumpStream();
      expect(received.last.positionTrusted, isTrue);
      // 150 m in 5 s: over the 100 m one-hop cap and under the 10 s
      // re-anchor window — a corrupt teleport the distance chain rejects.
      r.debugInjectPosition(makePosition(metresEast: 150, secondsFromStart: 5));
      await pumpStream();
      expect(r.debugTrack.length, 1,
          reason: 'the teleport must not enter the track');
      expect(received.last.currentPosition, isNotNull,
          reason: 'the rejected fix still drives the blue dot');
      expect(received.last.positionTrusted, isFalse,
          reason: 'route progress must be able to tell it was rejected');
      // The next good fix restores trust.
      r.debugInjectPosition(makePosition(metresEast: 8, secondsFromStart: 7));
      await pumpStream();
      expect(received.last.positionTrusted, isTrue);
      await sub.cancel();
      await r.stop();
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

    test('a console session reset keeps belt distance monotonic', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(3.0, totalDistanceMetres: 0);
      r.setTreadmillSample(3.0, totalDistanceMetres: 5000);
      expect(r.debugReportedDistanceMetres, closeTo(5000, 0.1));
      // Safety key pulled / workout ended on the console: the belt's cumulative
      // counter restarts from 0 while the runner keeps going. Holding the last
      // good value froze distance at 5000 for the next 5 km, then dropped it to
      // 0 the moment the belt climbed past the stale baseline.
      r.setTreadmillSample(3.0, totalDistanceMetres: 0);
      expect(r.debugReportedDistanceMetres, closeTo(5000, 0.1),
          reason: 'the reset itself must not lose the banked 5 km');
      r.setTreadmillSample(3.0, totalDistanceMetres: 2500);
      expect(r.debugReportedDistanceMetres, closeTo(7500, 0.1));
      r.setTreadmillSample(3.0, totalDistanceMetres: 5000);
      expect(r.debugReportedDistanceMetres, closeTo(10000, 0.1),
          reason: '10 km run must report 10 km, not 5 km');
    });

    test('a partial counter step-down rebases without losing distance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(3.0, totalDistanceMetres: 100);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1100);
      expect(r.debugReportedDistanceMetres, closeTo(1000, 0.1));
      // Console restarts but its counter resumes from a nonzero value.
      r.setTreadmillSample(3.0, totalDistanceMetres: 400);
      expect(r.debugReportedDistanceMetres, closeTo(1000, 0.1));
      r.setTreadmillSample(3.0, totalDistanceMetres: 900);
      expect(r.debugReportedDistanceMetres, closeTo(1500, 0.1));
    });

    test('belt distance never goes backwards across a reset', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      var previous = 0.0;
      for (final total in <double>[0, 800, 1600, 2400, 0, 700, 1400, 40, 900]) {
        r.setTreadmillSample(3.0, totalDistanceMetres: total);
        final reported = r.debugReportedDistanceMetres;
        expect(reported, greaterThanOrEqualTo(previous - 0.001),
            reason: 'distance dropped after belt total $total');
        previous = reported;
      }
      expect(previous, closeTo(2400 + 1400 + 860, 0.1));
    });

    test('a reset during a pause still excludes the paused advance', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(3.0, totalDistanceMetres: 0);
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000);
      r.pause();
      // Console reset while paused, then the belt advances 200 m unattended.
      r.setTreadmillSample(3.0, totalDistanceMetres: 0);
      r.setTreadmillSample(3.0, totalDistanceMetres: 200);
      expect(r.debugReportedDistanceMetres, closeTo(1000, 0.1),
          reason: 'paused belt advance is never credited');
      r.resume();
      r.setTreadmillSample(3.0, totalDistanceMetres: 300);
      expect(r.debugReportedDistanceMetres, closeTo(1100, 0.1));
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

    test(
        'cumulative belt advance during a pause with NO sample is not '
        'credited after resume', () {
      final r = RunRecorder()..debugPrepareWithoutStream();
      r.begin();
      r.setTreadmillSample(3.0, totalDistanceMetres: 1000); // baseline
      r.setTreadmillSample(3.0, totalDistanceMetres: 1300); // 300 m run
      expect(r.debugReportedDistanceMetres, 300.0);
      // Pause and resume without any sample landing during the pause — the
      // belt reports infrequently, or the user pauses then resumes between
      // two reports. The _paused-edge rebaseline in setTreadmillSample never
      // fires, so the baseline must instead be dropped on resume.
      r.pause();
      r.resume();
      // The belt kept counting during the pause; the first post-resume
      // reading is higher than the pre-pause total.
      r.setTreadmillSample(3.0, totalDistanceMetres: 1600);
      expect(r.debugReportedDistanceMetres, 300.0,
          reason:
              'the 300 m the belt advanced during the pause must not be '
              'credited — the first post-resume sample re-anchors');
      r.setTreadmillSample(3.0, totalDistanceMetres: 1700);
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

  group('resumeSession — process-kill continuity', () {
    // A partial persisted before a process kill: a few waypoints, an
    // accumulated distance, prior elapsed, and one mid-run lap.
    List<Waypoint> seededTrack() => [
          Waypoint(
              lat: lat,
              lng: lngBase,
              timestamp: DateTime(2026, 4, 10, 10, 0, 0)),
          Waypoint(
              lat: lat,
              lng: lngBase + 20 / metrePerDegLng,
              timestamp: DateTime(2026, 4, 10, 10, 0, 5)),
          Waypoint(
              lat: lat,
              lng: lngBase + 40 / metrePerDegLng,
              timestamp: DateTime(2026, 4, 10, 10, 0, 10)),
        ];

    test('re-hydrates track, distance, elapsed offset, and start time',
        () async {
      final r = RunRecorder();
      final track = seededTrack();
      r.debugResumeWithoutStream(
        track: track,
        distanceMetres: 187000,
        elapsed: const Duration(hours: 40),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      );
      expect(r.recording, isTrue);
      expect(r.debugTrack, hasLength(track.length),
          reason: 'the seeded track is kept, not cleared like begin()');
      expect(r.debugDistanceMetres, 187000,
          reason: 'accumulated distance continues, not reset to 0');

      // The broadcast snapshot stream delivers asynchronously — grab the next.
      final snapFuture = r.snapshots.first;
      r.debugInjectPosition(
          makePosition(metresEast: 60, secondsFromStart: 15));
      final snap = await snapFuture;
      // Elapsed reports the prior 40 h offset plus the live stopwatch (~0 here).
      expect(snap.elapsed, greaterThanOrEqualTo(const Duration(hours: 40)));
    });

    test('a post-resume fix extends the same track and adds to distance', () {
      final r = RunRecorder();
      final track = seededTrack();
      r.debugResumeWithoutStream(
        track: track,
        distanceMetres: 1000,
        elapsed: const Duration(minutes: 20),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
      );
      // First post-resume fix re-anchors (no spurious delta across the gap).
      r.debugInjectPosition(
          makePosition(metresEast: 1000, secondsFromStart: 20));
      // Second fix 30 m further adds real movement onto the seeded distance.
      r.debugInjectPosition(
          makePosition(metresEast: 1030, secondsFromStart: 25));
      expect(r.debugTrack.length, greaterThan(track.length),
          reason: 'new fixes extend the seeded track');
      expect(r.debugDistanceMetres, closeTo(1030, 2),
          reason: 'seeded 1000 m + the ~30 m post-resume hop, no gap delta');
    });

    test('restored laps continue numbering and survive to stop()', () async {
      final r = RunRecorder();
      final restored = lapsFromCanonicalJson([
        {'index': 1, 'start_offset_s': 0, 'distance_m': 500.0, 'duration_s': 300},
        {'index': 2, 'start_offset_s': 300, 'distance_m': 500.0, 'duration_s': 300},
      ], startedAt: DateTime(2026, 4, 10, 10, 0, 0));
      r.debugResumeWithoutStream(
        track: seededTrack(),
        distanceMetres: 1000,
        elapsed: const Duration(minutes: 10),
        startedAt: DateTime(2026, 4, 10, 10, 0, 0),
        laps: restored,
      );
      expect(r.laps, hasLength(2));
      // A new lap continues numbering from the restored ones.
      final n = r.lap();
      expect(n, 3);
      final run = await r.stop();
      final laps = run.metadata?['laps'] as List<dynamic>?;
      expect(laps, hasLength(3),
          reason: 'pre-kill laps + the post-resume lap all serialise');
      expect((laps![2] as Map)['index'], 3);
      // Total elapsed carries the 10 min offset.
      expect(run.duration, greaterThanOrEqualTo(const Duration(minutes: 10)));
    });

    test('lapsFromCanonicalJson is the inverse of lapsToCanonicalJson', () {
      final round = lapsToCanonicalJson(lapsFromCanonicalJson([
        {'index': 1, 'start_offset_s': 0, 'distance_m': 400.0, 'duration_s': 240},
        {'index': 2, 'start_offset_s': 240, 'distance_m': 600.0, 'duration_s': 300},
      ]));
      expect(round, hasLength(2));
      expect(round[0]['distance_m'], 400.0);
      expect(round[0]['duration_s'], 240);
      expect(round[1]['start_offset_s'], 240);
      expect(round[1]['distance_m'], 600.0);
    });
  });
}
