import 'package:core_models/core_models.dart' show Waypoint;
import 'package:flutter_test/flutter_test.dart';

import '../lib/route_overlap.dart';

// 1 m east at 47.37 °N latitude ≈ 1.3261 × 10^-5 degrees lng. Used so
// the test scenarios use easy round-number metres.
const _lat = 47.37;
const _metrePerDegLng = 111320 * 0.6773;

Waypoint _w(double metresEast) => Waypoint(
      lat: _lat,
      lng: 8.54 + metresEast / _metrePerDegLng,
    );

void main() {
  group('detectOverlapSpans', () {
    test('empty for fewer than four points', () {
      expect(detectOverlapSpans(const []), isEmpty);
      expect(detectOverlapSpans([_w(0), _w(100), _w(200)]), isEmpty);
    });

    test('one-way (no retracing) returns no overlap', () {
      // Straight line 0 → 100 → 200 → 300 → 400 m east. Nothing repeats.
      final path = [_w(0), _w(100), _w(200), _w(300), _w(400)];
      expect(detectOverlapSpans(path), isEmpty);
    });

    test('out-and-back marks the return half as overlap', () {
      // Out: 0 → 100 → 200. Back: 200 → 100 → 0.
      // The two halves overlap on segments [100,200] / [200,100] and
      // [0,100] / [100,0].
      final path = [_w(0), _w(100), _w(200), _w(100), _w(0)];
      final spans = detectOverlapSpans(path, toleranceM: 30);
      expect(spans, isNotEmpty,
          reason: 'an out-and-back must surface at least one overlap span');
    });

    test('tolerance gates parallel-but-separate streets', () {
      // Two parallel lines 80 m apart. With tolerance = 20, they
      // shouldn't be confused.
      final outA = [_w(0), _w(100), _w(200)];
      final outB = outA
          .map((w) => Waypoint(lat: w.lat + 80 / 111320, lng: w.lng))
          .toList();
      final path = [...outA, ...outB];
      expect(detectOverlapSpans(path, toleranceM: 20), isEmpty);
    });

    test('span covers contiguous overlapping indices', () {
      // Out: 0 → 100 → 200 → 300. Back: 300 → 200 → 100 → 0.
      // Multiple consecutive segments retrace; expect at least one span
      // and contiguous coverage.
      final path = [
        _w(0), _w(100), _w(200), _w(300), _w(200), _w(100), _w(0),
      ];
      final spans = detectOverlapSpans(path, toleranceM: 30);
      expect(spans, isNotEmpty);
      // Every span has end >= start (sanity invariant).
      for (final s in spans) {
        expect(s.endIndex >= s.startIndex, isTrue);
      }
    });

    test('OverlapSpan.contains hits indices inside the span', () {
      const s = OverlapSpan(startIndex: 3, endIndex: 7);
      expect(s.contains(3), isTrue);
      expect(s.contains(5), isTrue);
      expect(s.contains(7), isTrue);
      expect(s.contains(2), isFalse);
      expect(s.contains(8), isFalse);
    });

    test('down-sampled out-and-back collapses into broad contiguous spans', () {
      // 600-point out-and-back (> maxScannedPoints, so it down-samples):
      // out 0..2990 m, then retrace back to 0. The retraced half must
      // surface as a few wide spans, not a shower of width-2 stubs from
      // the old endpoint-only index mapping.
      final out = [for (var i = 0; i < 300; i++) _w(i * 10.0)];
      final back = [for (var i = 299; i >= 0; i--) _w(i * 10.0)];
      final path = [...out, ...back];
      final spans = detectOverlapSpans(path, toleranceM: 30);

      expect(spans, isNotEmpty);
      // Few spans, not hundreds of stubs.
      expect(spans.length, lessThan(6),
          reason: 'retrace should collapse into a handful of spans, '
              'got ${spans.length}');
      // At least one span is genuinely wide (spans many original points),
      // proving original-frame ranges were filled, not just endpoints.
      final widest = spans
          .map((s) => s.endIndex - s.startIndex)
          .reduce((a, b) => a > b ? a : b);
      expect(widest, greaterThan(100),
          reason: 'widest span was only $widest points');
      // Every reported index is in range.
      for (final s in spans) {
        expect(s.startIndex, inInclusiveRange(0, path.length - 1));
        expect(s.endIndex, inInclusiveRange(0, path.length - 1));
      }
    });

    test('long polylines are down-sampled to stay O(n²)-bounded', () {
      // 400 points along a straight line: no overlap. The call must
      // complete quickly (cap is maxScannedPoints=200).
      final path = [for (var i = 0; i < 400; i++) _w(i * 1.0)];
      final stopwatch = Stopwatch()..start();
      final spans = detectOverlapSpans(path);
      stopwatch.stop();
      expect(spans, isEmpty);
      // 200² ≈ 40k pair checks should easily finish under 100ms even
      // on the slowest CI machines.
      expect(stopwatch.elapsedMilliseconds, lessThan(500));
    });
  });
}
