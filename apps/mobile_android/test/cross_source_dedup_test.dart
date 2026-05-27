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

    test('±10% distance → NOT a duplicate (outside fraction)', () {
      final hc = _run(
        source: RunSource.healthconnect,
        startedAt: DateTime.utc(2026, 4, 15, 7),
        distanceM: 11000,
      );
      expect(isCrossSourceDuplicate(hc, existing), isFalse);
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
