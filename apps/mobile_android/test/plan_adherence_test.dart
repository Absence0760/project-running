import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_adherence.dart';

void main() {
  group('weeklyDrift', () {
    test('on-track when actual matches planned', () {
      final d = weeklyDrift(40000, 41000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('flags under-running past the threshold', () {
      final d = weeklyDrift(40000, 28000);
      expect(d.direction, DriftDirection.under);
      expect(d.flagged, true);
      expect(d.driftFraction < -planDriftThreshold, true);
    });

    test('flags over-running past the threshold', () {
      final d = weeklyDrift(40000, 52000);
      expect(d.direction, DriftDirection.over);
      expect(d.flagged, true);
      expect(d.driftFraction > planDriftThreshold, true);
    });

    test('just inside the threshold is not flagged', () {
      final d = weeklyDrift(40000, 47000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
    });

    test('no planned volume yields a neutral, unflagged result', () {
      final d = weeklyDrift(0, 30000);
      expect(d.direction, DriftDirection.onTrack);
      expect(d.flagged, false);
      expect(d.driftFraction, 0);
    });

    test('clamps negative actual to zero', () {
      final d = weeklyDrift(40000, -5);
      expect(d.actualMetres, 0);
      expect(d.direction, DriftDirection.under);
    });
  });

  group('missedWorkoutAdvice', () {
    test('base/build long run is worth making up', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: false, recoveryWeekImminent: false));
      expect(a.recommendation, MakeUpRecommendation.makeUp);
      expect(a.reason, MissedWorkoutReason.keySession);
    });

    test('skip a long run missed in the taper', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: true, recoveryWeekImminent: false));
      expect(a.recommendation, MakeUpRecommendation.skip);
      expect(a.reason, MissedWorkoutReason.taper);
    });

    test('skip when a recovery week is imminent', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: false, recoveryWeekImminent: true));
      expect(a.recommendation, MakeUpRecommendation.skip);
      expect(a.reason, MissedWorkoutReason.recoverySoon);
    });

    test('taper takes precedence over recovery-soon', () {
      final a = missedWorkoutAdvice(const MissedWorkoutInput(
          kind: 'long', isTaper: true, recoveryWeekImminent: true));
      expect(a.reason, MissedWorkoutReason.taper);
    });

    test('a missed quality session is just skipped', () {
      for (final kind in ['tempo', 'interval', 'easy', 'marathon_pace']) {
        final a = missedWorkoutAdvice(MissedWorkoutInput(
            kind: kind, isTaper: false, recoveryWeekImminent: false));
        expect(a.recommendation, MakeUpRecommendation.skip);
        expect(a.reason, MissedWorkoutReason.notLongRun);
      }
    });
  });
}
