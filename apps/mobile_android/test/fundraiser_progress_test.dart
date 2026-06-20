import 'package:flutter_test/flutter_test.dart';
import '../lib/fundraiser_progress.dart';

void main() {
  group('fundraiserProgress', () {
    test('zero raised is starting, empty bar, full remaining', () {
      final p = fundraiserProgress(0, 100000);
      expect(p.fillPct, 0);
      expect(p.rawPct, 0);
      expect(p.remainingCents, 100000);
      expect(p.state, ThermometerState.starting);
    });

    test('below 10% is starting', () {
      final p = fundraiserProgress(5000, 100000);
      expect(p.rawPct, 5);
      expect(p.state, ThermometerState.starting);
    });

    test('at the 10% threshold flips to progressing', () {
      final p = fundraiserProgress(10000, 100000);
      expect(p.rawPct, 10);
      expect(p.state, ThermometerState.progressing);
    });

    test('mid progress reports remaining + progressing', () {
      final p = fundraiserProgress(60000, 100000);
      expect(p.fillPct, 60);
      expect(p.remainingCents, 40000);
      expect(p.state, ThermometerState.progressing);
    });

    test('exactly at goal is met, no remaining, full bar', () {
      final p = fundraiserProgress(100000, 100000);
      expect(p.fillPct, 100);
      expect(p.rawPct, 100);
      expect(p.remainingCents, 0);
      expect(p.state, ThermometerState.met);
    });

    test('over goal is exceeded, fill clamps to 100, rawPct uncapped', () {
      final p = fundraiserProgress(118000, 100000);
      expect(p.fillPct, 100);
      expect(p.rawPct, 118);
      expect(p.remainingCents, 0);
      expect(p.state, ThermometerState.exceeded);
    });

    test('zero goal yields a safe zeroed starting result', () {
      final p = fundraiserProgress(5000, 0);
      expect(p.fillPct, 0);
      expect(p.rawPct, 0);
      expect(p.remainingCents, 0);
      expect(p.state, ThermometerState.starting);
    });

    test('negative goal is treated as no goal', () {
      final p = fundraiserProgress(5000, -100);
      expect(p.state, ThermometerState.starting);
      expect(p.rawPct, 0);
    });

    test('negative raised floors to zero', () {
      final p = fundraiserProgress(-500, 100000);
      expect(p.fillPct, 0);
      expect(p.remainingCents, 100000);
      expect(p.state, ThermometerState.starting);
    });

    test('non-finite raised is treated as zero', () {
      final p = fundraiserProgress(double.nan, 100000);
      expect(p.rawPct, 0);
      expect(p.state, ThermometerState.starting);
    });

    test('fractional percentage is preserved in rawPct', () {
      final p = fundraiserProgress(12345, 100000);
      expect(p.rawPct, closeTo(12.345, 1e-9));
      expect(p.state, ThermometerState.progressing);
    });
  });
}
