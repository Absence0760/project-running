import 'package:flutter_test/flutter_test.dart';

import '../lib/readiness.dart';

void main() {
  group('computeReadiness', () {
    test('neutral inputs → 75 baseline, high band', () {
      final r = computeReadiness(const ReadinessInputs(tsb: 0));
      expect(r.score, 75);
      expect(r.band, ReadinessBand.high);
      expect(r.contributors, hasLength(1));
    });

    test('all inputs null → 75 baseline, no contributors', () {
      final r = computeReadiness(const ReadinessInputs(tsb: null));
      expect(r.score, 75);
      expect(r.contributors, isEmpty);
      expect(r.advice, matches(RegExp(r'good day|push the pace', caseSensitive: false)));
    });

    test('heavy fatigue + bad sleep → low band', () {
      final r = computeReadiness(
        const ReadinessInputs(tsb: -25, sleepHours: 4),
      );
      // -20 (TSB) + -25 (sleep) = -45 → 75-45 = 30 → low.
      expect(r.score, 30);
      expect(r.band, ReadinessBand.low);
      expect(r.advice, matches(RegExp('easy|rest', caseSensitive: false)));
    });

    test('fresh + great sleep → high band', () {
      final r = computeReadiness(
        const ReadinessInputs(
          tsb: 10,
          sleepHours: 8.5,
          restingHrBpm: 55,
          baselineRestingHrBpm: 58,
        ),
      );
      // 75 + 8 + 5 + 3 = 91.
      expect(r.score, 91);
      expect(r.band, ReadinessBand.high);
      expect(r.advice, matches(RegExp('harder effort')));
    });

    test('clamps to 0..100 on extreme inputs', () {
      final low = computeReadiness(
        const ReadinessInputs(
          tsb: -50,
          sleepHours: 2,
          restingHrBpm: 100,
          baselineRestingHrBpm: 55,
        ),
      );
      expect(low.score, 12);
      expect(low.band, ReadinessBand.low);

      final high = computeReadiness(
        const ReadinessInputs(
          tsb: 10,
          sleepHours: 8,
          restingHrBpm: 50,
          baselineRestingHrBpm: 55,
        ),
      );
      expect(high.score, inInclusiveRange(75, 100));
    });

    test('TSB > +25 (over-tapered) → small negative not positive', () {
      final r = computeReadiness(const ReadinessInputs(tsb: 30));
      expect(r.score, 75 - 3);
      final tsb = r.contributors.firstWhere((c) => c.name == 'Form (TSB)');
      expect(tsb.delta, -3);
      expect(tsb.note, matches(RegExp('Over-tapered')));
    });

    test('resting HR +12 above baseline → strong negative', () {
      final r = computeReadiness(
        const ReadinessInputs(
          tsb: 0,
          restingHrBpm: 70,
          baselineRestingHrBpm: 58,
        ),
      );
      expect(r.score, 75 - 18);
      expect(r.band, ReadinessBand.moderate);
      expect(r.advice,
          matches(RegExp('illness|under-recovery', caseSensitive: false)));
    });

    test('dominant input drives the advice line', () {
      final r = computeReadiness(
        const ReadinessInputs(tsb: -3, sleepHours: 4),
      );
      expect(r.advice,
          matches(RegExp('Very little sleep|compromised', caseSensitive: false)));
    });

    test('partial inputs — only sleep present', () {
      final r = computeReadiness(
        const ReadinessInputs(tsb: null, sleepHours: 8.5),
      );
      expect(r.score, 80);
      expect(r.band, ReadinessBand.high);
      expect(r.contributors, hasLength(1));
    });

    test('band thresholds', () {
      expect(
          computeReadiness(const ReadinessInputs(tsb: 0)).band,
          ReadinessBand.high);
      expect(
          computeReadiness(const ReadinessInputs(tsb: -10)).band,
          ReadinessBand.moderate);
      expect(
          computeReadiness(const ReadinessInputs(tsb: -25)).band,
          ReadinessBand.moderate);
      expect(
          computeReadiness(
                  const ReadinessInputs(tsb: -25, sleepHours: 3))
              .band,
          ReadinessBand.low);
    });

    test('score is deterministic — same inputs → same output', () {
      final a = computeReadiness(
          const ReadinessInputs(tsb: 5, sleepHours: 7));
      final b = computeReadiness(
          const ReadinessInputs(tsb: 5, sleepHours: 7));
      expect(a.score, b.score);
      expect(a.band, b.band);
      expect(a.advice, b.advice);
    });

    test('a tie in |delta| is broken by insertion order, not by the sort', () {
      // A TSB of -12 and six hours of sleep both score -12, and the two carry
      // DIFFERENT advice, so which one wins has to be a contract. Dart's
      // List.sort is unstable where JS's is stable, so this needs the
      // explicit index tiebreak to match the web twin.
      final r = computeReadiness(
          const ReadinessInputs(tsb: -12, sleepHours: 6));
      expect(r.contributors[0].delta, -12);
      expect(r.contributors[1].delta, -12);
      expect(r.advice, startsWith('Fatigued from recent training.'));
    });

    test('an all-zero tie still resolves to the first contributor', () {
      final r = computeReadiness(const ReadinessInputs(
        tsb: 0,
        sleepHours: 10,
        restingHrBpm: 50,
        baselineRestingHrBpm: 50,
      ));
      expect(r.contributors, hasLength(3));
      expect(r.contributors.map((c) => c.delta).toList(), [0, 0, 0]);
      expect(r.advice, startsWith('Form is neutral.'));
    });

    test('the tiebreak does not override a genuinely larger contributor', () {
      // Sleep at -25 beats a TSB of -12 even though TSB was added first.
      final r = computeReadiness(
          const ReadinessInputs(tsb: -12, sleepHours: 4));
      expect(r.advice, startsWith('Very little sleep'));
    });
  });
}
