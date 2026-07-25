import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/route_simplify.dart';

void main() {
  // Approximate conversions near the equator:
  //   1e-5 degrees latitude  ≈ 1.11 metres
  //   1e-4 degrees latitude  ≈ 11.1 metres
  //   1e-3 degrees latitude  ≈ 111 metres

  Waypoint wp(double lat, double lng, {double? ele}) =>
      Waypoint(lat: lat, lng: lng, elevationMetres: ele);

  group('simplifyTrack', () {
    test('returns input unchanged when fewer than 3 points', () {
      final track = [wp(0, 0), wp(0, 0.001)];
      expect(simplifyTrack(track).length, 2);
    });

    test('drops points that lie on a straight line', () {
      // 5 points along a perfect line east — simplification should keep
      // just the two endpoints.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(0, 0.002),
        wp(0, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, 2);
      expect(out.first.lng, 0);
      expect(out.last.lng, 0.004);
    });

    test('keeps a sharp corner at higher than epsilon', () {
      // L-shaped path: east, then north. The corner point must be kept.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(0, 0.002), // corner
        wp(0.001, 0.002),
        wp(0.002, 0.002),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, 3);
      expect(out[1].lat, 0);
      expect(out[1].lng, 0.002);
    });

    test('smooths sub-epsilon GPS jitter around a straight path', () {
      // A mostly-east line with small random lateral wobble under ~3 m.
      final track = [
        wp(0, 0),
        wp(0.00001, 0.001), // ~1 m north of ideal
        wp(-0.00001, 0.002),
        wp(0.00002, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      // Jitter is below the 5 m epsilon so only endpoints survive.
      expect(out.length, 2);
    });

    test('keeps deviations above epsilon', () {
      // 20 m detour south in the middle of an otherwise-straight line.
      final track = [
        wp(0, 0),
        wp(0, 0.001),
        wp(-0.00018, 0.002), // ~20 m south
        wp(0, 0.003),
        wp(0, 0.004),
      ];
      final out = simplifyTrack(track, epsilonMetres: 5);
      expect(out.length, greaterThanOrEqualTo(3));
      expect(out.any((w) => w.lat < -0.00001), isTrue);
    });
  });

  group('computeElevationGain', () {
    test('returns zero for flat or missing data', () {
      expect(
        computeElevationGain([wp(0, 0, ele: 10), wp(0, 0.001, ele: 10)]),
        0,
      );
      expect(
        computeElevationGain([wp(0, 0), wp(0, 0.001)]),
        0,
      );
    });

    test('accumulates only positive segments', () {
      final track = [
        wp(0, 0, ele: 10),
        wp(0, 0.001, ele: 15), // +5
        wp(0, 0.002, ele: 12), // -3, ignored
        wp(0, 0.003, ele: 20), // +8
      ];
      expect(computeElevationGain(track), 13);
    });

    test('carries the last valid elevation across a missing-reading gap', () {
      final track = [
        wp(0, 0, ele: 10),
        wp(0, 0.001), // no elevation
        wp(0, 0.002, ele: 20),
      ];
      // The runner climbed 10 m across the dropout; skipping the gap
      // entirely (the old adjacent-pair behaviour) wrongly reported 0.
      expect(computeElevationGain(track), 10);
    });

    test('carries across a multi-point gap and still ignores descents', () {
      final track = [
        wp(0, 0, ele: 100),
        wp(0, 0.001), // no elevation
        wp(0, 0.002), // no elevation
        wp(0, 0.003, ele: 130), // +30 across the gap
        wp(0, 0.004, ele: 120), // -10, ignored
        wp(0, 0.005, ele: 125), // +5
      ];
      expect(computeElevationGain(track), 35);
    });

    test('jitter inside the noise band is not climb', () {
      // A 1 Hz sawtooth of ±1 m around a flat road. Summing every positive
      // pair turned this into metres of phantom vert per minute; over a long
      // run it integrated into thousands.
      final track = [
        for (var i = 0; i < 200; i++)
          wp(0, i * 0.0001, ele: 100 + (i % 2).toDouble()),
      ];
      expect(computeElevationGain(track), 0);
    });

    test('a real climb through jitter is counted in full', () {
      // 100 m of climb delivered in 4 m steps with ±1 m noise on top.
      final track = [
        for (var i = 0; i <= 25; i++)
          wp(0, i * 0.0001, ele: 100 + i * 4 + (i % 2).toDouble()),
      ];
      expect(computeElevationGain(track), inInclusiveRange(98, 102));
    });

    test('a descent resets the reference to the valley', () {
      // Up 50, down 50, up 50 = 100 m of gain, not 50: the second climb must
      // be measured from the bottom, not from the first summit.
      final track = [
        wp(0, 0, ele: 100),
        wp(0, 0.001, ele: 150),
        wp(0, 0.002, ele: 100),
        wp(0, 0.003, ele: 150),
      ];
      expect(computeElevationGain(track), 100);
    });

    test('loss mirrors gain — same gate, same dropout carry', () {
      // The run-detail screen shows the two side by side, so they must be
      // graded the same way: a flat road reading 0 m of climb next to
      // hundreds of metres of descent would read as a bug.
      final jitter = [
        for (var i = 0; i < 200; i++)
          wp(0, i * 0.0001, ele: 100 + (i % 2).toDouble()),
      ];
      expect(computeElevationLoss(jitter), 0);

      final hill = [
        wp(0, 0, ele: 100),
        wp(0, 0.001, ele: 150),
        wp(0, 0.002), // dropout
        wp(0, 0.003, ele: 100),
      ];
      expect(computeElevationGain(hill), 50);
      expect(computeElevationLoss(hill), 50);
    });

    test('a save-as-route hill that simplifies away keeps its climb', () {
      // The mobile save-as-route path calls simplifyTrack and
      // computeElevationGain separately, and the gain call must take the RAW
      // track: RDP works in 2-D, so a dead-straight road over a summit
      // collapses to its endpoints and grading the simplified line reads 0.
      final track = [
        for (var i = 0; i <= 20; i++)
          wp(0, i * 0.0001,
              ele: 100 + (i <= 10 ? i * 5 : (20 - i) * 5).toDouble()),
      ];
      expect(simplifyTrack(track, epsilonMetres: 10).length, 2);
      expect(computeElevationGain(track), 50);
    });
  });

  group('ElevationGainAccumulator', () {
    test('a flat track with sub-3 m jitter accumulates nothing', () {
      // The live run screen used to sum every positive delta, turning a 1 Hz
      // sawtooth on a flat road into hundreds of metres of phantom vert while
      // the finished-run screen showed ~0 for the same track.
      final acc = ElevationGainAccumulator();
      for (var i = 0; i < 2000; i++) {
        acc.add(wp(0, i * 0.00001, ele: 100 + (i % 3).toDouble()));
      }
      expect(acc.gainMetres, 0);
    });

    test('fed one point at a time it matches computeElevationGain exactly', () {
      final track = [
        wp(0, 0, ele: 100),
        wp(0, 0.0001, ele: 101),
        wp(0, 0.0002, ele: 104),
        wp(0, 0.0003), // dropout carries the reference
        wp(0, 0.0004, ele: 106),
        wp(0, 0.0005, ele: 90),
        wp(0, 0.0006, ele: 140),
        wp(0, 0.0007, ele: 141),
      ];
      final acc = ElevationGainAccumulator();
      for (final p in track) {
        acc.add(p);
      }
      expect(acc.gainMetres, computeElevationGain(track));
      expect(acc.gainMetres, 54);
    });

    test('appending a tail matches replaying the whole track', () {
      // How the run screen uses it: only the waypoints appended since the last
      // GPS tick are fed in, so the tail-only result must equal the full one.
      final track = [
        for (var i = 0; i <= 60; i++)
          wp(0, i * 0.0001, ele: 100 + (i <= 30 ? i * 4 : (60 - i) * 4).toDouble()),
      ];
      final incremental = ElevationGainAccumulator();
      var processed = 0;
      while (processed < track.length) {
        final next = (processed + 7).clamp(0, track.length);
        for (var i = processed; i < next; i++) {
          incremental.add(track[i]);
        }
        processed = next;
      }
      expect(incremental.gainMetres, computeElevationGain(track));
    });

    test('reset clears both the total and the carried reference', () {
      final acc = ElevationGainAccumulator();
      acc.addAll([wp(0, 0, ele: 100), wp(0, 0.0001, ele: 150)]);
      expect(acc.gainMetres, 50);
      acc.reset();
      // A fresh 200 m start must not be read as a 100 m climb from the old ref.
      acc.addAll([wp(0, 0, ele: 200), wp(0, 0.0001, ele: 201)]);
      expect(acc.gainMetres, 0);
    });
  });
}
