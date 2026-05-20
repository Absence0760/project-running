import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/mileage_trend.dart';

Run _run({
  required DateTime startedAt,
  required double distanceM,
}) =>
    Run(
      id: 'r-${startedAt.millisecondsSinceEpoch}',
      startedAt: startedAt,
      duration: const Duration(minutes: 30),
      distanceMetres: distanceM,
      source: RunSource.app,
    );

void main() {
  final now = DateTime(2026, 5, 19, 12); // Tuesday

  group('aggregateMileage — weekly', () {
    test('returns empty when there are no runs', () {
      final out = aggregateMileage(const [], view: MileageView.weekly, now: now);
      expect(out, isEmpty);
    });

    test('groups same-week runs into a single bucket (Monday anchor)', () {
      // Mon 11 May 2026 + Wed 13 May 2026 → same ISO week (starts
      // Monday 11 May). Total should sum.
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 5, 11, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 13, 6), distanceM: 8000),
        ],
        view: MileageView.weekly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.distanceM, 13000);
      expect(out.first.label, '11 May');
    });

    test('separates runs across week boundaries', () {
      // Sunday 10 May → previous week (Mon 4 May); Monday 11 May →
      // new week. Two buckets.
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 5, 10, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 11, 6), distanceM: 8000),
        ],
        view: MileageView.weekly,
        now: now,
      );
      expect(out, hasLength(2));
      // Order is chronological.
      expect(out[0].label, '4 May');
      expect(out[0].distanceM, 5000);
      expect(out[1].label, '11 May');
      expect(out[1].distanceM, 8000);
    });

    test('caps at the most-recent 12 buckets by default', () {
      // 14 weeks of runs → only the last 12 buckets survive.
      final runs = <Run>[];
      for (var i = 0; i < 14; i++) {
        runs.add(_run(
          startedAt: DateTime(2026, 1, 5).add(Duration(days: 7 * i)),
          distanceM: 1000.0 * (i + 1),
        ));
      }
      final out =
          aggregateMileage(runs, view: MileageView.weekly, now: now);
      expect(out, hasLength(12));
      // Earliest two buckets are dropped — first remaining is the 3rd week.
      expect(out.first.distanceM, 3000);
      expect(out.last.distanceM, 14000);
    });

    test('respects maxBuckets override', () {
      final runs = [
        for (var i = 0; i < 5; i++)
          _run(
            startedAt: DateTime(2026, 1, 5).add(Duration(days: 7 * i)),
            distanceM: 1000,
          ),
      ];
      final out = aggregateMileage(
        runs,
        view: MileageView.weekly,
        now: now,
        maxBuckets: 3,
      );
      expect(out, hasLength(3));
    });
  });

  group('aggregateMileage — monthly', () {
    test('groups same-month runs into one bucket', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 4, 2, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 4, 30, 6), distanceM: 8000),
        ],
        view: MileageView.monthly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.distanceM, 13000);
      expect(out.first.label, "Apr '26");
    });

    test('separates runs across month boundaries with chronological order',
        () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2026, 4, 30, 7), distanceM: 5000),
          _run(startedAt: DateTime(2026, 5, 1, 6), distanceM: 8000),
        ],
        view: MileageView.monthly,
        now: now,
      );
      expect(out, hasLength(2));
      expect(out[0].label, "Apr '26");
      expect(out[1].label, "May '26");
    });
  });

  group('aggregateMileage — yearly', () {
    test('groups same-year runs into one bucket', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2025, 1, 5, 7), distanceM: 12000),
          _run(startedAt: DateTime(2025, 12, 31, 6), distanceM: 8000),
        ],
        view: MileageView.yearly,
        now: now,
      );
      expect(out, hasLength(1));
      expect(out.first.label, '2025');
      expect(out.first.distanceM, 20000);
    });

    test('separates runs across year boundaries', () {
      final out = aggregateMileage(
        [
          _run(startedAt: DateTime(2024, 6, 1, 7), distanceM: 5000),
          _run(startedAt: DateTime(2025, 6, 1, 7), distanceM: 6000),
          _run(startedAt: DateTime(2026, 6, 1, 7), distanceM: 7000),
        ],
        view: MileageView.yearly,
        now: now,
      );
      expect(out.map((p) => p.label).toList(), ['2024', '2025', '2026']);
    });
  });
}
