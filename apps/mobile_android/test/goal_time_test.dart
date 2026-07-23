import 'package:flutter_test/flutter_test.dart';

import '../lib/goal_time.dart';

void main() {
  group('parseGoalTimeS', () {
    test('three-part input is always h:mm:ss', () {
      expect(parseGoalTimeS('3:30:00'), 12600);
      expect(parseGoalTimeS('0:25:00'), 1500);
    });

    test('bare number is minutes', () {
      expect(parseGoalTimeS('90'), 5400);
      expect(parseGoalTimeS('210'), 12600);
    });

    test('two-part input defaults to h:mm without a distance', () {
      expect(parseGoalTimeS('3:30'), 12600);
      expect(parseGoalTimeS('25:00'), 90000);
    });

    test('two-part input picks the pace-plausible reading for the distance',
        () {
      // "3:30" for a marathon: 3h30 is ~4:59/km (plausible); 3.5 min is not.
      expect(parseGoalTimeS('3:30', distanceM: 42195), 12600);
      // "25:00" for a 5K: 25 hours is ~300 min/km (implausible); 25 min is
      // 5:00/km.
      expect(parseGoalTimeS('25:00', distanceM: 5000), 1500);
      // "12:30" for a 100K ultra: 12h30 is ~7:30/km (plausible) — the hours
      // reading wins even though 12.5 min would parse.
      expect(parseGoalTimeS('12:30', distanceM: 100000), 45000);
    });

    test('rejects junk, negatives, zero, and four-part input', () {
      expect(parseGoalTimeS(''), isNull);
      expect(parseGoalTimeS('abc'), isNull);
      expect(parseGoalTimeS('1:2:3:4'), isNull);
      expect(parseGoalTimeS('0'), isNull);
      expect(parseGoalTimeS('-5:30'), isNull);
      expect(parseGoalTimeS('5:-30'), isNull);
    });
  });

  group('formatGoalTimeS', () {
    test('round-trips through parseGoalTimeS', () {
      expect(formatGoalTimeS(12600), '3:30:00');
      expect(formatGoalTimeS(1500), '25:00');
      expect(parseGoalTimeS(formatGoalTimeS(12600)), 12600);
      expect(parseGoalTimeS(formatGoalTimeS(1500), distanceM: 5000), 1500);
    });
  });
}
