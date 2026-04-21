import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_android/preferences.dart';
import 'package:mobile_android/widgets/pace_segments.dart';

void main() {
  group('paceBucketForSpeed', () {
    test('running: 5:00/km (3.33 m/s) lands in the middle of the ramp', () {
      final b = paceBucketForSpeed(3.33, ActivityType.run);
      expect(b, inInclusiveRange(2, 4),
          reason: 'A steady 5:00/km pace should be one of the mid buckets, '
              'not painted red or cyan.');
    });

    test('running: a jog (2.5 m/s ≈ 6:40/km) is in a slow bucket', () {
      expect(paceBucketForSpeed(2.5, ActivityType.run), lessThan(3));
    });

    test('running: a hard effort (5 m/s ≈ 3:20/km) clamps to fastest', () {
      expect(paceBucketForSpeed(5.0, ActivityType.run), 5);
    });

    test('running: near-stationary clamps to slowest', () {
      expect(paceBucketForSpeed(0.05, ActivityType.run), 0);
    });

    test('cycling: 25 km/h (~6.94 m/s) lands mid-ramp', () {
      final b = paceBucketForSpeed(6.94, ActivityType.cycle);
      expect(b, inInclusiveRange(2, 4));
    });

    test('cycling: 40 km/h (~11.1 m/s) clamps to fastest', () {
      expect(paceBucketForSpeed(11.1, ActivityType.cycle), 5);
    });

    test('walking uses its own scale — 1.4 m/s is mid-walk, not slow-run', () {
      final walk = paceBucketForSpeed(1.4, ActivityType.walk);
      final run = paceBucketForSpeed(1.4, ActivityType.run);
      expect(walk, greaterThan(run),
          reason: '1.4 m/s is brisk walking but barely-moving running; '
              'the ramp must account for activity.');
    });
  });

  group('ageBandFor', () {
    test('single-segment track is treated as newest', () {
      expect(ageBandFor(0, 1), 2);
    });

    test('three-segment track splits across all bands', () {
      expect(ageBandFor(0, 3), 0);
      expect(ageBandFor(1, 3), 1);
      expect(ageBandFor(2, 3), 2);
    });

    test('long track: the first third is oldest, last third is newest', () {
      expect(ageBandFor(0, 100), 0);
      expect(ageBandFor(33, 100), 1);
      expect(ageBandFor(99, 100), 2);
    });
  });

  group('buildPaceSegments', () {
    Waypoint wp({
      required double metresEast,
      required int secondsFromStart,
      double baseLat = 47.37,
      double baseLng = 8.54,
    }) {
      const metresPerDegLng = 111320 * 0.6773; // cos(47.37°)
      return Waypoint(
        lat: baseLat,
        lng: baseLng + metresEast / metresPerDegLng,
        timestamp: DateTime(2026, 4, 20, 10, 0, secondsFromStart),
      );
    }

    test('empty / single-point track emits no polylines', () {
      expect(
        buildPaceSegments(
          track: const [],
          rendered: const [],
          activity: ActivityType.run,
        ),
        isEmpty,
      );
      final oneWp = [wp(metresEast: 0, secondsFromStart: 0)];
      expect(
        buildPaceSegments(
          track: oneWp,
          rendered: [LatLng(oneWp[0].lat, oneWp[0].lng)],
          activity: ActivityType.run,
        ),
        isEmpty,
      );
    });

    test('uniform pace coalesces into a single polyline per age band', () {
      // 10 segments at ~3.3 m/s — should all land in the same pace bucket.
      // Split into 3 age bands (oldest / mid / newest), so we expect 3
      // polylines.
      final track = <Waypoint>[
        for (int i = 0; i <= 10; i++)
          wp(metresEast: i * 3.3, secondsFromStart: i),
      ];
      final rendered = track.map((w) => LatLng(w.lat, w.lng)).toList();
      final polys = buildPaceSegments(
        track: track,
        rendered: rendered,
        activity: ActivityType.run,
      );
      expect(polys.length, 3,
          reason: 'Uniform pace should produce one polyline per age band.');
      // Every polyline has the same colour hue (ignoring alpha).
      final firstRgb = polys.first.color.value & 0x00FFFFFF;
      for (final p in polys) {
        expect(p.color.value & 0x00FFFFFF, firstRgb);
      }
      // Alpha increases from oldest to newest.
      final alphas = polys.map((p) => p.color.alpha).toList();
      expect(alphas[0], lessThan(alphas[1]));
      expect(alphas[1], lessThan(alphas[2]));
    });

    test('a pace change mid-run splits into extra polylines', () {
      // First 5 segments at ~3.3 m/s (mid bucket), next 5 at ~5 m/s (fast).
      final track = <Waypoint>[
        wp(metresEast: 0, secondsFromStart: 0),
        for (int i = 1; i <= 5; i++)
          wp(metresEast: i * 3.3, secondsFromStart: i),
        for (int i = 1; i <= 5; i++)
          wp(metresEast: 5 * 3.3 + i * 5.0, secondsFromStart: 5 + i),
      ];
      final rendered = track.map((w) => LatLng(w.lat, w.lng)).toList();
      final polys = buildPaceSegments(
        track: track,
        rendered: rendered,
        activity: ActivityType.run,
      );
      // With both pace and age bucketing, a single pace change produces
      // strictly more polylines than the uniform-pace case (3).
      expect(polys.length, greaterThan(3));
      // And strictly fewer than one-per-segment (10).
      expect(polys.length, lessThan(10));
    });

    test('adjacent polylines share a vertex so the line is visually continuous',
        () {
      // Deliberately force a bucket boundary to confirm the coalescing
      // emits runs that share endpoints with the next run.
      final track = <Waypoint>[
        wp(metresEast: 0, secondsFromStart: 0),
        wp(metresEast: 2, secondsFromStart: 1),
        wp(metresEast: 4, secondsFromStart: 2),
        wp(metresEast: 9, secondsFromStart: 3), // faster
        wp(metresEast: 14, secondsFromStart: 4),
        wp(metresEast: 19, secondsFromStart: 5),
      ];
      final rendered = track.map((w) => LatLng(w.lat, w.lng)).toList();
      final polys = buildPaceSegments(
        track: track,
        rendered: rendered,
        activity: ActivityType.run,
      );
      for (int i = 1; i < polys.length; i++) {
        final prevLast = polys[i - 1].points.last;
        final curFirst = polys[i].points.first;
        expect(prevLast, equals(curFirst),
            reason: 'Consecutive polylines must share a vertex so the '
                'rendered line has no visible gap at bucket transitions.');
      }
    });

    test('waypoints without timestamps get the slowest bucket (safe default)',
        () {
      // No timestamps — speed can't be computed, fall back to slowest.
      final track = <Waypoint>[
        Waypoint(lat: 47.37, lng: 8.54),
        Waypoint(lat: 47.37, lng: 8.541),
        Waypoint(lat: 47.37, lng: 8.542),
      ];
      final rendered = track.map((w) => LatLng(w.lat, w.lng)).toList();
      final polys = buildPaceSegments(
        track: track,
        rendered: rendered,
        activity: ActivityType.run,
      );
      expect(polys, isNotEmpty);
      for (final p in polys) {
        // Slowest bucket is red (0xFFEF4444).
        expect(p.color.value & 0x00FFFFFF, 0xEF4444);
      }
    });
  });
}
