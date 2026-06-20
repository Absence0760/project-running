import 'package:flutter_test/flutter_test.dart';
import '../lib/coach_load.dart';

void main() {
  group('acwr', () {
    test('ratio is acute / chronic', () {
      expect(acwr(100, 80), 1.25);
    });

    test('zero chronic base returns 0 (no division)', () {
      expect(acwr(50, 0), 0);
    });

    test('non-finite inputs return 0', () {
      expect(acwr(double.nan, 80), 0);
      expect(acwr(100, double.nan), 0);
    });
  });

  group('injuryRiskBand (band edges)', () {
    test('zero chronic base is insufficient, not low', () {
      expect(injuryRiskBand(40, 0), InjuryRiskBand.insufficient);
    });

    test('just below 0.8 is low', () {
      expect(injuryRiskBand(79, 100), InjuryRiskBand.low);
    });

    test('exactly 0.8 is optimal (low is < 0.8)', () {
      expect(injuryRiskBand(80, 100), InjuryRiskBand.optimal);
    });

    test('1.0 is optimal', () {
      expect(injuryRiskBand(100, 100), InjuryRiskBand.optimal);
    });

    test('exactly 1.3 is elevated (optimal is < 1.3)', () {
      expect(injuryRiskBand(130, 100), InjuryRiskBand.elevated);
    });

    test('just below 1.5 is elevated', () {
      expect(injuryRiskBand(149, 100), InjuryRiskBand.elevated);
    });

    test('exactly 1.5 is high', () {
      expect(injuryRiskBand(150, 100), InjuryRiskBand.high);
    });

    test('a big spike is high', () {
      expect(injuryRiskBand(220, 100), InjuryRiskBand.high);
    });
  });

  group('loadTrend', () {
    test('>15% above chronic is ramping', () {
      expect(loadTrend(120, 100), LoadTrend.ramping);
    });

    test('>15% below chronic is tapering', () {
      expect(loadTrend(80, 100), LoadTrend.tapering);
    });

    test('within the deadband is steady', () {
      expect(loadTrend(100, 100), LoadTrend.steady);
    });

    test('no chronic base is steady (one week is not a trend)', () {
      expect(loadTrend(50, 0), LoadTrend.steady);
    });
  });
}
