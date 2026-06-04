import 'package:core_models/core_models.dart';
import 'package:flutter_test/flutter_test.dart';
import '../lib/training_load.dart';

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

    test('a long layoff resets CTL/TSB (comeback #29)', () {
      final ref = DateTime.utc(2026, 4, 30, 12);
      final runs = <Run>[];
      // 3-week build ending ~50 days ago, then nothing — past the 28-day
      // reset threshold.
      for (var i = 70; i >= 50; i--) {
        runs.add(_run(
          distanceM: 10000,
          durationS: 3000,
          startedAt: ref.subtract(Duration(days: i)),
        ));
      }
      final series = computeTrainingLoadSeries(runs, windowDays: 90, endDate: ref);
      expect(series.last.ctl < 1, isTrue,
          reason: 'CTL should reset to ~0 after a >28d layoff');
      expect(series.last.tsb.abs() < 1, isTrue,
          reason: 'TSB should be ~0 after a layoff');
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

  // Persona-hunt Pro #2 — per-window calibration so a strap-less day
  // doesn't fake a 3× spike in the daily series. Mirrors the web tests
  // for byte-identical contract.
  group('computeCalibration (persona-hunt Pro #2)', () {
    test('mode=distance when no HR prefs', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
      );
      final cal = computeCalibration([r]);
      expect(cal.mode, 'distance');
      expect(cal.trimpPerKmFallback, isNull);
    });

    test('mode=distance when prefs set but no HR-eligible run', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
      );
      final cal = computeCalibration(
        [r],
        const HrPrefs(restingHrBpm: 50, maxHrBpm: 190),
      );
      expect(cal.mode, 'distance');
    });

    test('mode=trimp when at least one run has HR', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
        metadata: {'avg_bpm': 140},
      );
      final cal = computeCalibration(
        [r],
        const HrPrefs(restingHrBpm: 50, maxHrBpm: 190),
      );
      expect(cal.mode, 'trimp');
      expect(cal.trimpPerKmFallback, isNotNull);
      expect(cal.trimpPerKmFallback! > 0, isTrue);
    });
  });

  group('aggregateDailyStress — Pro #2 spike fix', () {
    test('strap-less day uses calibrated fallback, not legacy 10/km', () {
      final withHr = _run(
        distanceM: 12000,
        durationS: 3600,
        startedAt: DateTime.utc(2026, 4, 1, 7),
        metadata: {'avg_bpm': 140},
      );
      final noHr = _run(
        distanceM: 12000,
        durationS: 3600,
        startedAt: DateTime.utc(2026, 4, 2, 7),
      );
      final daily = aggregateDailyStress(
        [withHr, noHr],
        const HrPrefs(restingHrBpm: 50, maxHrBpm: 190),
      );
      final day1 = daily[
        DateTime(withHr.startedAt.toLocal().year,
            withHr.startedAt.toLocal().month, withHr.startedAt.toLocal().day)
      ]!;
      final day2 = daily[
        DateTime(noHr.startedAt.toLocal().year,
            noHr.startedAt.toLocal().month, noHr.startedAt.toLocal().day)
      ]!;
      final ratio = day2 / day1;
      expect(ratio > 0.5 && ratio < 1.5, isTrue,
          reason:
              'Strap-less day ($day2) should be within 50% of strap day '
              '($day1); pre-fix this was ~3×. Got ratio ${ratio.toStringAsFixed(2)}');
    });

    // Persona-hunt Round 2 finding Pro #2 — CTL warm-up pin.
    test('day 1 of an established pro\'s chart is at steady state', () {
      final ref = DateTime.utc(2026, 5, 1, 12);
      final runs = <Run>[];
      for (var i = 1; i <= 300; i++) {
        runs.add(_run(
          distanceM: 12000,
          durationS: 3600,
          startedAt: ref.subtract(Duration(days: i)),
        ));
      }
      final series = computeTrainingLoadSeries(
        runs,
        windowDays: 90,
        endDate: ref,
      );
      final day1 = series.first;
      expect(day1.ctl > 100, isTrue,
          reason: 'day 1 CTL should be ≈ 120 (steady-state for 12 km/day); '
              'pre-fix this was ≈ 0 because the loop ignored pre-window '
              'runs. Got ${day1.ctl}');
      expect(day1.tsb.abs() < 10, isTrue,
          reason: 'day 1 TSB should be near 0 at steady state; '
              'got ${day1.tsb}');
    });

    test('pure-distance window keeps legacy 10/km behaviour', () {
      final r = _run(
        distanceM: 5000,
        durationS: 1800,
        startedAt: DateTime.utc(2026, 4, 1),
      );
      final daily = aggregateDailyStress([r]);
      final local = r.startedAt.toLocal();
      final key = DateTime(local.year, local.month, local.day);
      expect(daily[key], 50);
    });
  });

  group('lift load', () {
    // A representative HARD session: 16 working sets of 8 reps at 62.5 kg
    // (~8,000 kg tonnage) at RPE 8 — the calibration anchor.
    LiftForLoad hardLiftSession(DateTime when) => LiftForLoad(
          startedAt: when,
          sets: List.generate(
            16,
            (_) => const LiftSetForLoad(reps: 8, weightKg: 62.5, rpe: 8),
          ),
        );

    test('rpeFactor anchored at RPE 8 = 1.0, absent = 1.0, bounded', () {
      expect(rpeFactor(8), 1.0);
      expect(rpeFactor(null), 1.0);
      expect(rpeFactor(6) < 1.0 && rpeFactor(10) > 1.0, isTrue);
      expect(rpeFactor(0), 0.5);
      expect(rpeFactor(20), 1.25);
    });

    test('CALIBRATION: a hard lift session scores in the easy-run band (40-60)',
        () {
      final stress = computeLiftStress(hardLiftSession(DateTime.utc(2026, 4, 1)));
      expect(stress >= 40 && stress <= 60, isTrue);
    });

    test('sets without reps or weight contribute nothing', () {
      final bw = LiftForLoad(
        startedAt: DateTime.utc(2026, 4, 1),
        sets: const [
          LiftSetForLoad(reps: 20, weightKg: null),
          LiftSetForLoad(reps: null, weightKg: 60),
          LiftSetForLoad(reps: 0, weightKg: 60),
        ],
      );
      expect(computeLiftStress(bw), 0);
    });

    test('a fat-fingered weight is capped, cannot spike the curve', () {
      final typo = LiftForLoad(
        startedAt: DateTime.utc(2026, 4, 1),
        sets: const [LiftSetForLoad(reps: 5, weightKg: 50000, rpe: 8)],
      );
      expect(computeLiftStress(typo), kLiftStressCap);
    });

    test('aggregateDailyLiftStress sums by local day, skips empty sessions', () {
      final when = DateTime.utc(2026, 4, 1);
      final daily = aggregateDailyLiftStress([
        hardLiftSession(when),
        hardLiftSession(when),
        LiftForLoad(
          startedAt: DateTime.utc(2026, 4, 2),
          sets: const [LiftSetForLoad(reps: 10, weightKg: null)],
        ),
      ]);
      final local = when.toLocal();
      final key = DateTime(local.year, local.month, local.day);
      expect((daily[key] ?? 0) > 80, isTrue);
      expect(daily.containsKey(DateTime(2026, 4, 2)), isFalse);
    });

    test('lift stress is separable and raises fatigue', () {
      final ref = DateTime.utc(2026, 5, 1, 12);
      final runDay = ref.subtract(const Duration(days: 1));
      final runs = [
        _run(distanceM: 8000, durationS: 2400, startedAt: runDay),
      ];
      final lifts = [hardLiftSession(runDay)];

      final runOnly = computeTrainingLoadSeries(runs, endDate: ref);
      final withLifts =
          computeTrainingLoadSeries(runs, endDate: ref, lifts: lifts);

      // Run-only curve is recoverable from runStress regardless of lifts.
      for (var i = 0; i < runOnly.length; i++) {
        expect(withLifts[i].runStress, runOnly[i].stress);
      }
      final last = withLifts[withLifts.length - 2];
      expect(last.liftStress > 0, isTrue);
      expect(last.stress > last.runStress, isTrue);
      expect(withLifts.last.atl > runOnly.last.atl, isTrue);
    });

    test('no lifts leaves liftStress 0 and stress unchanged', () {
      final ref = DateTime.utc(2026, 5, 1, 12);
      final runs = [
        _run(
          distanceM: 5000,
          durationS: 1500,
          startedAt: ref.subtract(const Duration(days: 2)),
        ),
      ];
      final series = computeTrainingLoadSeries(runs, endDate: ref);
      expect(series.every((p) => p.liftStress == 0), isTrue);
      expect(series.every((p) => p.stress == p.runStress), isTrue);
    });
  });
}
