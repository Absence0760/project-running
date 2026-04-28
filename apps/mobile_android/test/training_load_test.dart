import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_android/training_load.dart';

Run _run({
  required double distanceM,
  required int durationS,
  required DateTime startedAt,
  Map<String, dynamic>? metadata,
}) =>
    Run(
      id: 'r-${startedAt.toIso8601String()}-$durationS',
      startedAt: startedAt,
      duration: Duration(seconds: durationS),
      distanceMetres: distanceM,
      track: const [],
      source: RunSource.app,
      metadata: metadata,
    );

void main() {
  group('computeStress', () {
    test('distance fallback gives 50 for an easy 5k', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1, 7),
      );
      expect(computeStress(r), 50);
    });

    test('TRIMP path differs from distance fallback when HR known', () {
      final r = _run(
        distanceM: 10000,
        durationS: 3600,
        startedAt: DateTime.utc(2026, 4, 1, 7),
        metadata: {'avg_bpm': 150},
      );
      final trimp = computeStress(
        r,
        const HrPrefs(restingHrBpm: 50, maxHrBpm: 190),
      );
      final distance = computeStress(r);
      expect(trimp, isNot(distance));
      expect(trimp > 0, isTrue);
    });

    test('zero distance + zero duration → 0', () {
      final r = _run(
        distanceM: 0,
        durationS: 0,
        startedAt: DateTime.utc(2026, 4, 1),
      );
      expect(computeStress(r), 0);
    });
  });

  group('aggregateDailyStress', () {
    test('sums same-day runs', () {
      final a = _run(
        distanceM: 5000,
        durationS: 1500,
        startedAt: DateTime.utc(2026, 4, 1, 7),
      );
      final b = _run(
        distanceM: 3000,
        durationS: 900,
        startedAt: DateTime.utc(2026, 4, 1, 18),
      );
      final m = aggregateDailyStress([a, b]);
      final local = a.startedAt.toLocal();
      final key = DateTime(local.year, local.month, local.day);
      expect(m[key], 80);
    });
  });

  group('computeTrainingLoadSeries', () {
    test('emits exactly windowDays entries', () {
      final series = computeTrainingLoadSeries(
        const [],
        windowDays: 30,
        endDate: DateTime.utc(2026, 4, 30, 12),
      );
      expect(series.length, 30);
    });

    test('TSB rises during taper (no runs after a build)', () {
      final runs = <Run>[];
      final ref = DateTime.utc(2026, 4, 30, 12);
      for (var i = 28; i >= 14; i--) {
        runs.add(_run(
          distanceM: 5000,
          durationS: 1500,
          startedAt: ref.subtract(Duration(days: i)),
        ));
      }
      final series = computeTrainingLoadSeries(
        runs,
        windowDays: 60,
        endDate: ref,
      );
      expect(series.last.tsb > 0, isTrue);
    });

    test('series is all-zero with no runs', () {
      final series = computeTrainingLoadSeries(
        const [],
        windowDays: 30,
        endDate: DateTime.utc(2026, 4, 30, 12),
      );
      expect(series.every((p) => p.atl == 0 && p.ctl == 0 && p.tsb == 0),
          isTrue);
    });
  });

  group('hasTrimpSignal', () {
    test('false when no avg_bpm', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
      );
      expect(
        hasTrimpSignal([r], const HrPrefs(restingHrBpm: 50, maxHrBpm: 190)),
        isFalse,
      );
    });

    test('true when at least one run has avg_bpm and prefs are set', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
        metadata: {'avg_bpm': 150},
      );
      expect(
        hasTrimpSignal([r], const HrPrefs(restingHrBpm: 50, maxHrBpm: 190)),
        isTrue,
      );
    });

    test('false when prefs missing', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
        metadata: {'avg_bpm': 150},
      );
      expect(hasTrimpSignal([r]), isFalse);
    });
  });
}
