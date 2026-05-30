import 'package:flutter_test/flutter_test.dart';
import 'package:run_recorder/run_recorder.dart';

LapSplit _lap({
  required int number,
  required double cumulativeM,
  required Duration cumulativeDur,
}) =>
    LapSplit(
      number: number,
      timestamp: DateTime.utc(2026, 4, 28, 12, 0).add(cumulativeDur),
      cumulativeDistanceMetres: cumulativeM,
      cumulativeDuration: cumulativeDur,
    );

void main() {
  group('lapsToCanonicalJson', () {
    test('empty list returns empty list', () {
      expect(lapsToCanonicalJson(const []), isEmpty);
    });

    test('first lap uses start_offset_s=0 and full distance / duration as deltas', () {
      // Reason: the running prevDist / prevDuration trackers start at 0,
      // so the first lap's deltas equal its cumulative values.
      final out = lapsToCanonicalJson([
        _lap(
          number: 1,
          cumulativeM: 1000,
          cumulativeDur: const Duration(minutes: 5),
        ),
      ]);
      expect(out, hasLength(1));
      expect(out.first['index'], 1);
      expect(out.first['start_offset_s'], 0);
      expect(out.first['distance_m'], 1000.0);
      expect(out.first['duration_s'], 300);
    });

    test('subsequent laps emit per-lap deltas (not cumulative totals)', () {
      // Two laps: 1 km in 5 min, then 1.2 km in 6 min (cumulative
      // 2.2 km / 11 min). The wire shape must be the *deltas*, matching
      // the Wear OS sender at apps/watch_wear/.../RunViewModel.kt.
      final out = lapsToCanonicalJson([
        _lap(
          number: 1,
          cumulativeM: 1000,
          cumulativeDur: const Duration(minutes: 5),
        ),
        _lap(
          number: 2,
          cumulativeM: 2200,
          cumulativeDur: const Duration(minutes: 11),
        ),
      ]);
      expect(out, hasLength(2));
      expect(out[0]['distance_m'], 1000.0);
      expect(out[0]['duration_s'], 300);
      expect(out[1]['index'], 2);
      // start_offset_s = previous lap's cumulative duration (300 s).
      expect(out[1]['start_offset_s'], 300);
      // distance_m = 2200 - 1000.
      expect(out[1]['distance_m'], 1200.0);
      // duration_s = 660 - 300.
      expect(out[1]['duration_s'], 360);
    });

    test('clamps negative distance delta to 0', () {
      // Pathological case: GPS jitter could in theory leave the second
      // cumulative distance below the first. We don't ship negative
      // deltas — clamp to 0 so readers don't display nonsense.
      final out = lapsToCanonicalJson([
        _lap(
          number: 1,
          cumulativeM: 1000,
          cumulativeDur: const Duration(minutes: 5),
        ),
        _lap(
          number: 2,
          cumulativeM: 950,
          cumulativeDur: const Duration(minutes: 6),
        ),
      ]);
      expect(out[1]['distance_m'], 0.0);
    });

    test('clamps negative duration delta to 0', () {
      // Same defensive clamp on the duration axis.
      final out = lapsToCanonicalJson([
        _lap(
          number: 1,
          cumulativeM: 1000,
          cumulativeDur: const Duration(seconds: 300),
        ),
        _lap(
          number: 2,
          cumulativeM: 2000,
          cumulativeDur: const Duration(seconds: 250),
        ),
      ]);
      expect(out[1]['duration_s'], 0);
    });

    test('all laps carry the canonical key set, no extras', () {
      // Reason: silent-extra keys would drift away from
      // docs/backend/metadata.md and re-introduce the divergence the audit
      // already caught.
      final out = lapsToCanonicalJson([
        _lap(
          number: 1,
          cumulativeM: 1000,
          cumulativeDur: const Duration(minutes: 5),
        ),
      ]);
      expect(
        out.first.keys.toSet(),
        {'index', 'start_offset_s', 'distance_m', 'duration_s'},
      );
    });
  });
}
