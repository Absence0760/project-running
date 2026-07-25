// Persona-hunt Round 2 finding Intermediate #3 — fuzzy time +
// distance dedup at import time so a Garmin run that syncs into
// both Strava AND Health Connect doesn't land as two rows.

import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/cross_source_dedup.dart';

Run _run({
  required RunSource source,
  required DateTime startedAt,
  required double distanceM,
}) =>
    Run(
      id: 'r-${source.name}-${startedAt.toIso8601String()}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      track: const [],
      source: source,
    );

void main() {
  group('isCrossSourceDuplicate', () {
    final existing = [
      _run(
        source: RunSource.strava,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10000,
      ),
    ];

    test('exact same time + distance from a different source → duplicate', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isTrue);
    });

    test('±2 min start time + ±2% distance → still duplicate', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7, 2),
        distanceM: 10200,
      );
      expect(isCrossSourceDuplicate(hc, existing), isTrue);
    });

    test('±10 min start time → NOT a duplicate (outside window)', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7, 10),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isFalse);
    });

    test('start within the 180 s canonical window → duplicate', () {
      // 2 min 59 s — inside the 180 s twin tolerance.
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7, 2, 59),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isTrue);
    });

    test('start beyond the 180 s window → NOT a duplicate (twin parity)', () {
      // 4 min — beyond the 180 s tolerance; the old 5-min window would have
      // wrongly deduped it. Pins lockstep with the web / Go / Deno twins.
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7, 4),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isFalse);
    });

    test('distance fraction is against the LARGER of the two (twin parity)', () {
      // Candidate is 4% longer than the existing run: |Δ|/max = 400/10400 ≈
      // 3.85% ≤ 5% → duplicate (the canonical max-denominator rule).
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10400,
      );
      expect(isCrossSourceDuplicate(hc, existing), isTrue);
    });

    test('±10% distance → NOT a duplicate (outside fraction)', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 11000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isFalse);
    });

    test('two Health Connect rows for the same run ARE compared', () {
      // Health Connect is an aggregator: Garmin Connect and Samsung Health can
      // each write the same physical run into it. Both arrive tagged
      // `healthconnect` with DIFFERENT record uuids, so the external_id index
      // never sees them as the same row — skipping the comparison doubled the
      // runner's mileage, PRs and heatmap.
      final fromHealthConnect = [
        _run(
          source: RunSource.healthconnect,
          startedAt: DateTime.utc(2026, 4, 15, 7),
          distanceM: 10000,
        ),
      ];
      final secondWriter = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7, 0, 30),
        distanceM: 10120,
      );
      expect(isCrossSourceDuplicate(secondWriter, fromHealthConnect), isTrue);
    });

    test('HealthKit is an aggregator too', () {
      final fromHealthKit = [
        _run(
          source: RunSource.healthkit,
          startedAt: DateTime.utc(2026, 4, 15, 7),
          distanceM: 10000,
        ),
      ];
      final other = _run(
        source: RunSource.healthkit,
        startedAt: DateTime.utc(2026, 4, 15, 7, 1),
        distanceM: 10100,
      );
      expect(isCrossSourceDuplicate(other, fromHealthKit), isTrue);
    });

    test('two genuinely separate aggregator runs are still both kept', () {
      // Widening the comparison must not suppress a real second run: these
      // are two hours apart, so neither axis matches.
      final morning = [
        _run(
          source: RunSource.healthconnect,
          startedAt: DateTime.utc(2026, 4, 15, 7),
          distanceM: 10000,
        ),
      ];
      final evening = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 18),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(evening, morning), isFalse);
    });

    test('same source → NEVER a cross-source duplicate (DB unique guards it)',
        () {
      final dupStrava = _run(
        source: RunSource.strava,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(dupStrava, existing), isFalse,
          reason: 'same-source dedup is the per-source external_id ' +
              'partial unique index, not this helper');
    });

    test('zero-distance existing run is ignored to avoid false matches', () {
      final zero = [
        _run(
          source: RunSource.strava,
          startedAt: DateTime.utc(2026, 4, 15, 7),
          distanceM: 0,
        ),
      ];
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, zero), isFalse);
    });

    test('empty existing → never a duplicate', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 10000,
      );
      expect(isCrossSourceDuplicate(hc, const []), isFalse);
    });
  });
}
