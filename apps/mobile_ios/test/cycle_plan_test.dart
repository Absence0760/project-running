import 'package:flutter_test/flutter_test.dart';
import '../lib/cycle_plan.dart';

void main() {
  group('daysBetweenIso', () {
    test('forward, backward, zero', () {
      expect(daysBetweenIso('2026-06-01', '2026-06-08'), 7);
      expect(daysBetweenIso('2026-06-08', '2026-06-01'), -7);
      expect(daysBetweenIso('2026-06-01', '2026-06-01'), 0);
    });

    test('crosses month + year boundaries', () {
      expect(daysBetweenIso('2026-06-28', '2026-07-03'), 5);
      expect(daysBetweenIso('2026-12-30', '2027-01-02'), 3);
    });
  });

  group('cycleDayInfo', () {
    test('anchor day is menstrual day 0', () {
      final info = cycleDayInfo('2026-06-01', 28, '2026-06-01');
      expect(info?.dayInCycle, 0);
      expect(info?.phase, CyclePhase.menstrual);
      expect(info?.isEaseDay, true);
    });

    test('28-day phase boundaries', () {
      expect(cycleDayInfo('2026-06-01', 28, '2026-06-06')?.phase,
          CyclePhase.follicular);
      expect(cycleDayInfo('2026-06-01', 28, '2026-06-14')?.phase,
          CyclePhase.ovulatory);
      expect(
          cycleDayInfo('2026-06-01', 28, '2026-06-20')?.phase, CyclePhase.luteal);
    });

    test('late-luteal days are ease days, mid-luteal are not', () {
      expect(cycleDayInfo('2026-06-01', 28, '2026-06-20')?.isEaseDay, false);
      expect(cycleDayInfo('2026-06-01', 28, '2026-06-27')?.isEaseDay, true);
    });

    test('wraps into the next cycle', () {
      final info = cycleDayInfo('2026-06-01', 28, '2026-07-01');
      expect(info?.dayInCycle, 2);
      expect(info?.phase, CyclePhase.menstrual);
    });

    test('handles a date before the anchor', () {
      expect(cycleDayInfo('2026-06-01', 28, '2026-05-31')?.dayInCycle, 27);
    });

    test('short 21-day cycle keeps a valid ovulatory window', () {
      expect(cycleDayInfo('2026-06-01', 21, '2026-06-08')?.phase,
          CyclePhase.ovulatory);
      expect(cycleDayInfo('2026-06-01', 21, '2026-06-19')?.isEaseDay, true);
    });

    test('refuses out-of-band cycle lengths', () {
      expect(cycleDayInfo('2026-06-01', minCycleLengthDays - 1, '2026-06-10'),
          null);
      expect(cycleDayInfo('2026-06-01', maxCycleLengthDays + 1, '2026-06-10'),
          null);
    });
  });

  group('trimesterForDate', () {
    test('maps gestational age to trimesters', () {
      expect(trimesterForDate('2027-01-01', '2026-04-09'), 1);
      expect(trimesterForDate('2027-01-01', '2026-08-01'), 2);
      expect(trimesterForDate('2027-01-01', '2026-11-01'), 3);
    });

    test('near the due date is T3', () {
      expect(trimesterForDate('2027-01-01', '2026-12-25'), 3);
    });

    test('null before conception window', () {
      expect(trimesterForDate('2027-01-01', '2026-01-01'), null);
    });

    test('null more than two weeks past due', () {
      expect(trimesterForDate('2027-01-01', '2027-02-01'), null);
    });
  });

  group('cyclePlanWorkoutPatch — cycle mode', () {
    final cycle = const CyclePlanConfig.cycle(
      cycleLengthDays: 28,
      lastPeriodStartIso: '2026-06-01',
    );

    test('leaves rest + race + non-ease days untouched', () {
      expect(cyclePlanWorkoutPatch('rest', null, '2026-06-01', cycle), null);
      expect(cyclePlanWorkoutPatch('race', 42195, '2026-06-01', cycle), null);
      expect(cyclePlanWorkoutPatch('long', 20000, '2026-06-09', cycle), null);
    });

    test('eases long-run volume on a menstrual day', () {
      final patch = cyclePlanWorkoutPatch('long', 20000, '2026-06-02', cycle);
      expect(patch?.fields['target_distance_m'], (20000 * cycleEaseScale).round());
      expect(patch?.fields.containsKey('kind'), false);
    });

    test('quality session runs by feel on a late-luteal day', () {
      final patch = cyclePlanWorkoutPatch('interval', 8000, '2026-06-27', cycle);
      expect(patch?.fields['target_pace_sec_per_km'], null);
      expect(patch?.fields.containsKey('target_pace_sec_per_km'), true);
      expect(patch?.fields['target_pace_tolerance_sec'], null);
      expect(patch?.fields['target_distance_m'], (8000 * cycleEaseScale).round());
      expect(patch?.fields.containsKey('kind'), false);
    });

    test('distance-less easy day on an ease day yields no patch', () {
      expect(cyclePlanWorkoutPatch('easy', null, '2026-06-02', cycle), null);
    });
  });

  group('cyclePlanWorkoutPatch — pregnancy mode', () {
    final preg = const CyclePlanConfig.pregnancy(dueDateIso: '2027-01-01');

    test('strips a quality session to easy + tapers volume', () {
      final patch = cyclePlanWorkoutPatch('interval', 8000, '2026-11-01', preg);
      expect(patch?.fields['kind'], 'easy');
      expect(patch?.fields['target_pace_sec_per_km'], null);
      expect(patch?.fields['structure'], null);
      expect(patch?.fields['target_distance_m'],
          (8000 * pregnancyVolumeScale[3]!).round());
    });

    test('converts the goal race to an easy run', () {
      final patch = cyclePlanWorkoutPatch('race', 21097, '2026-08-01', preg);
      expect(patch?.fields['kind'], 'easy');
      expect(patch?.fields['target_distance_m'],
          (21097 * pregnancyVolumeScale[2]!).round());
    });

    test('tapers an easy run by trimester without changing its kind', () {
      final patch = cyclePlanWorkoutPatch('easy', 10000, '2026-04-09', preg);
      expect(patch?.fields.containsKey('kind'), false);
      expect(patch?.fields['target_distance_m'],
          (10000 * pregnancyVolumeScale[1]!).round());
    });

    test('leaves weeks outside the pregnancy untouched', () {
      expect(cyclePlanWorkoutPatch('interval', 8000, '2026-01-01', preg), null);
    });

    test('leaves rest untouched', () {
      expect(cyclePlanWorkoutPatch('rest', null, '2026-11-01', preg), null);
    });
  });
}
