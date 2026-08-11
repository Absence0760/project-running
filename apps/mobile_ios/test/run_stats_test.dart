import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/run_stats.dart';

void main() {
  group('movingTimeOf', () {
    // Zürich coordinates, moving eastward. ~0.00001 degree of longitude at
    // 47.37°N is ~0.75 m — usable for constructing realistic short segments.
    const lat = 47.37;
    const lngBase = 8.54;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      // 1 metre east ≈ 1 / (111320 * cos(lat)) degrees of longitude.
      final metrePerDeg = 111320 * 0.6773; // cos(47.37°)
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns zero for empty or single-point tracks', () {
      expect(movingTimeOf(const []), Duration.zero);
      expect(
        movingTimeOf([wp(metresEast: 0, secondsFromStart: 0)]),
        Duration.zero,
      );
    });

    test('includes fast segments (running pace)', () {
      // 12 m in 4 s → 3 m/s → running
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 12, secondsFromStart: 4),
      ];
      expect(movingTimeOf(track), const Duration(seconds: 4));
    });

    test('excludes slow segments below the default 0.5 m/s threshold', () {
      // 1 m in 5 s → 0.2 m/s → standing still / GPS jitter
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('mixed: running then long stop then running', () {
      // 10 m in 5 s (2 m/s, moving)
      // 0.5 m in 90 s (0.006 m/s, stopped at a light)
      // 10 m in 5 s (2 m/s, moving again)
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 10, secondsFromStart: 5),
        wp(metresEast: 10.5, secondsFromStart: 95),
        wp(metresEast: 20.5, secondsFromStart: 100),
      ];
      // Moving = 5 + 5 = 10s. Elapsed = 100s. Stop segment excluded.
      expect(movingTimeOf(track), const Duration(seconds: 10));
    });

    test('custom threshold can include slower walks', () {
      // 1.5 m in 5 s → 0.3 m/s → below default, above custom 0.2
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 1.5, secondsFromStart: 5),
      ];
      expect(movingTimeOf(track), Duration.zero); // default threshold
      expect(
        movingTimeOf(track, minSpeedMps: 0.2),
        const Duration(seconds: 5),
      );
    });

    test('skips segments with missing timestamps', () {
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        Waypoint(lat: lat, lng: lngBase + 0.0001), // no timestamp
        wp(metresEast: 10, secondsFromStart: 5),
      ];
      // First segment skipped (no timestamp on either end); second segment
      // is counted because both endpoints have timestamps. But wait — the
      // second segment compares point[1] (no ts) to point[2]. That one is
      // also skipped. So nothing counted.
      expect(movingTimeOf(track), Duration.zero);
    });

    test('skips segments with zero or negative dt', () {
      // Two points with the same timestamp → dt = 0
      final ts = DateTime(2026, 4, 10, 10, 0, 0);
      final track = [
        Waypoint(lat: lat, lng: lngBase, timestamp: ts),
        Waypoint(lat: lat, lng: lngBase + 0.0001, timestamp: ts),
      ];
      expect(movingTimeOf(track), Duration.zero);
    });

    test('sums across many fast segments', () {
      // Ten 3-second segments at 3 m/s each → 30s moving
      final track = <Waypoint>[];
      for (var i = 0; i <= 10; i++) {
        track.add(wp(metresEast: i * 9.0, secondsFromStart: i * 3));
      }
      expect(movingTimeOf(track), const Duration(seconds: 30));
    });
  });

  group('fastestWindowOf', () {
    const lat = 47.37;
    const lngBase = 8.54;
    final metrePerDeg = 111320 * 0.6773;

    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
    }) {
      final lng = lngBase + metresEast / metrePerDeg;
      return Waypoint(
        lat: lat,
        lng: lng,
        timestamp: DateTime(2026, 4, 10, 10, 0, secondsFromStart),
      );
    }

    test('returns null for empty or short tracks', () {
      expect(fastestWindowOf(const [], 5000), isNull);
      expect(
        fastestWindowOf([wp(metresEast: 0, secondsFromStart: 0)], 5000),
        isNull,
      );
    });

    test('returns null when track covers less than the window', () {
      // 4 km straight line in 20 min — not enough for a 5 km window.
      final track = [
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 4000, secondsFromStart: 20 * 60),
      ];
      expect(fastestWindowOf(track, 5000), isNull);
    });

    test('even-paced 10 km gives half-time for fastest 5 km', () {
      // 10 km in 50:00 at constant pace — fastest 5 km must be 25:00.
      // Use 50 waypoints at 200 m apart, 60 s apart.
      final track = <Waypoint>[
        for (var i = 0; i <= 50; i++)
          wp(metresEast: i * 200.0, secondsFromStart: i * 60),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // Allow 1-second interpolation slack.
      expect(best!.inSeconds, closeTo(25 * 60, 1));
    });

    test('picks the fast middle 5 km out of a slow → fast → slow run', () {
      // 3 km warmup at 300 s/km (slow)
      // 5 km fast at 240 s/km (the PB window)
      // 3 km cooldown at 300 s/km
      // 11 km total. Best 5k should be 1200 s = 20:00.
      final track = <Waypoint>[];
      var distance = 0.0;
      var seconds = 0;
      track.add(wp(metresEast: distance, secondsFromStart: seconds));

      // 3 km warmup: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 5 km fast: 50 segments of 100 m at 24 s each
      for (var i = 0; i < 50; i++) {
        distance += 100;
        seconds += 24;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }
      // 3 km cooldown: 30 segments of 100 m at 30 s each
      for (var i = 0; i < 30; i++) {
        distance += 100;
        seconds += 30;
        track.add(wp(metresEast: distance, secondsFromStart: seconds));
      }

      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      expect(best!.inSeconds, closeTo(20 * 60, 2));
    });

    test('does not project: a 10 km at even pace stays at its real 5k time', () {
      // Regression for the "Fastest 5k" scaled-pace bug. A 10 km in
      // 1:14:34 (4474 s) at perfectly even pace → fastest 5 km is 37:17.
      // Build 100 segments of 100 m each, total 4474 s.
      final track = <Waypoint>[
        for (var i = 0; i <= 100; i++)
          wp(
            metresEast: i * 100.0,
            secondsFromStart: (i * 4474 / 100).round(),
          ),
      ];
      final best = fastestWindowOf(track, 5000);
      expect(best, isNotNull);
      // 37:17 ± small interpolation slack
      expect(best!.inSeconds, closeTo(2237, 2));
    });
  });

  group('bestEffortsFromPersonalRecords', () {
    PersonalRecordRow pr(String distance, int seconds) => PersonalRecordRow(
          userId: 'u',
          distance: distance,
          bestTimeS: seconds,
          achievedAt: DateTime.utc(2026, 1, 1),
          updatedAt: DateTime.utc(2026, 1, 1),
        );

    test('maps cache rows to labels ordered shortest-first', () {
      // Deliberately out of order on input.
      final efforts = bestEffortsFromPersonalRecords([
        pr('marathon', 12000),
        pr('5k', 1200),
        pr('12k', 3100),
        pr('1_mile', 360),
        pr('half_marathon', 5400),
        pr('8k', 2000),
        pr('10k', 2500),
      ]);
      expect(efforts.keys.toList(),
          ['Mile', '5 km', '8 km', '10 km', '12 km', 'Half Marathon', 'Marathon']);
      expect(efforts['5 km'], const Duration(seconds: 1200));
      expect(efforts['Marathon'], const Duration(seconds: 12000));
    });

    test('drops unknown brackets and returns empty for none', () {
      expect(bestEffortsFromPersonalRecords([pr('50k', 99999)]), isEmpty);
      expect(bestEffortsFromPersonalRecords(const []), isEmpty);
    });
  });

  group('computeSplitDurations', () {
    final start = DateTime(2026, 4, 10, 10, 0, 0);
    // Move east along the equator, where haversineMetres(0,0,0,deg) is exactly
    // R·deg·π/180, so `metres` maps to a precise longitude (6371000·π/180
    // metres per degree). Tracks overshoot the last asserted boundary so it is
    // unambiguously crossed (no reliance on exact float equality).
    const mPerDeg = 6371000 * 3.141592653589793 / 180;
    Waypoint at(double metres, int seconds) => Waypoint(
          lat: 0,
          lng: metres / mPerDeg,
          timestamp: start.add(Duration(seconds: seconds)),
        );

    /// A waypoint with NO timestamp — what gpx_parser emits for a `<trkpt>`
    /// that carries no `<time>`, which strava_importer copies straight onto the
    /// saved run track.
    Waypoint untimed(double metres) =>
        Waypoint(lat: 0, lng: metres / mPerDeg);

    test('an untimestamped mid-track point never yields a negative split', () {
      // Substituting startedAt for the missing timestamp made
      // bTime.difference(aTime) ≈ -50 min, so the interpolated crossing landed
      // before tickStart and split 10 came out negative — which then poisoned
      // tickStart and every split after it.
      final track = [
        for (var m = 0; m <= 9500; m += 500) at(m.toDouble(), m * 6 ~/ 1000),
        untimed(10200),
        at(11000, 3960),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits, isNotEmpty);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]);
    });

    test('splits stay monotonic when a track has several untimed points', () {
      final track = [
        at(0, 0),
        at(500, 150),
        untimed(1200),
        untimed(1800),
        at(2400, 720),
        at(3000, 900),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
      // Cumulative crossing times must be non-decreasing, so the summed splits
      // can never exceed the run's own elapsed time.
      final total = splits.fold(Duration.zero, (a, s) => a + s.duration);
      expect(total, lessThanOrEqualTo(const Duration(seconds: 900)));
    });

    test('a backwards timestamp clamps to 0:00 rather than going negative', () {
      // Android batching queued fixes / an NTP correction can walk a timestamp
      // backwards; the same clamp must absorb it.
      final track = [
        at(0, 0),
        at(900, 270),
        Waypoint(lat: 0, lng: 1100 / mPerDeg, timestamp: start),
        at(2100, 600),
      ];
      final splits = computeSplitDurations(track, 1000, start);
      for (final s in splits) {
        expect(s.duration, greaterThanOrEqualTo(Duration.zero),
            reason: 'split ${s.tick} is negative: ${s.duration}');
      }
    });

    test('a fully-timestamped track is unaffected by the clamp', () {
      // Even 300 s/km, overshooting each boundary so it is unambiguously
      // crossed (see the group's float-equality note).
      final splits = computeSplitDurations(
        [at(0, 0), at(1050, 315), at(2100, 630)],
        1000,
        start,
      );
      expect(splits.length, 2);
      expect(splits[0].duration.inSeconds, closeTo(300, 1));
      expect(splits[1].duration.inSeconds, closeTo(300, 1));
    });

    test('returns nothing for short tracks or a non-positive tick', () {
      expect(computeSplitDurations(const [], 1000, start), isEmpty);
      expect(computeSplitDurations([at(0, 0)], 1000, start), isEmpty);
      expect(computeSplitDurations([at(0, 0), at(1000, 300)], 0, start), isEmpty);
    });

    test('a multi-boundary GPS gap yields one timed split per tick, no 0:00 phantoms', () {
      // Dense to 500 m, then a single 2500 m fix-to-fix gap (a tunnel, a
      // canyon/forest signal loss, or a downsampled import), then on past
      // 4000 m — all at an even 300 s/km. The gap segment straddles the 1/2/3
      // km boundaries. The old loop emitted the first split then 0:00 phantoms
      // for km 2 and km 3 (which also poisoned the fastest-split highlight).
      final track = [at(0, 0), at(500, 150), at(3000, 900), at(4100, 1230)];
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3, 4]);
      for (final s in splits) {
        expect(s.duration.inSeconds, closeTo(300, 2),
            reason: 'tick ${s.tick} was ${s.duration.inSeconds}s (0 = phantom)');
      }
    });

    test('even-paced dense run splits into full km ticks', () {
      final track = <Waypoint>[];
      for (var m = 0; m <= 3100; m += 100) {
        track.add(at(m.toDouble(), (m * 3) ~/ 10)); // 300 s/km
      }
      final splits = computeSplitDurations(track, 1000, start);
      expect(splits.map((s) => s.tick).toList(), [1, 2, 3]);
      for (final s in splits) {
        expect(s.duration.inSeconds, closeTo(300, 2));
      }
    });

    test('mile tick produces a mile-long split (full ticks only, no partial)', () {
      final track = <Waypoint>[];
      for (var m = 0; m <= 2000; m += 100) {
        track.add(at(m.toDouble(), (m * 3) ~/ 10)); // 300 s/km
      }
      final splits = computeSplitDurations(track, 1609.344, start);
      expect(splits.length, 1);
      expect(splits.first.tick, 1);
      // 1609.344 m at 300 s/km ≈ 483 s.
      expect(splits.first.duration.inSeconds, closeTo(483, 3));
    });
  });

  group('averagePaceSecPerKm', () {
    test('positive inputs return elapsed / distance-in-km', () {
      // 2 km in 600 s → 300 s/km.
      expect(averagePaceSecPerKm(2000, 600), closeTo(300, 1e-9));
    });

    test('zero (or negative) distance returns null', () {
      expect(averagePaceSecPerKm(0, 600), isNull);
      expect(averagePaceSecPerKm(-5, 600), isNull);
    });

    test('zero (or negative) elapsed returns null', () {
      expect(averagePaceSecPerKm(2000, 0), isNull);
      expect(averagePaceSecPerKm(2000, -1), isNull);
    });
  });

  test('haversineMetres clamps instead of returning NaN near antipodal', () {
    // web clamps with 2*asin(min(1, sqrt(a))); the unclamped atan2 form went
    // NaN when rounding pushed `a` past 1, and NaN then propagates silently
    // (Dart's NaN.clamp(0, 1) is 1.0, so interpolateAlongRoute returned the
    // END waypoint rather than the midpoint).
    final d = haversineMetres(-87.5, 0, 87.5, 180);
    expect(d.isFinite, isTrue);
    expect(d, closeTo(20015086.796, 1.0));
  });
}
