// Plan-detail week-window arithmetic and the current-week index.
//
// Kept out of `training_test.dart` (which mirrors `training.test.ts`
// case-for-case) because these pin a screen's use of the engine, not the
// engine itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/training.dart';

void main() {
  group('addDays', () {
    test('keeps the time of day, so a week boundary stays at midnight', () {
      // `.add(Duration(days: n))` adds absolute 24-hour spans, so crossing a
      // DST transition shifts the boundary by an hour and every later week
      // inherits the drift. Calendar arithmetic can't: whatever the runner's
      // timezone, the wall clock is preserved.
      for (final start in [
        DateTime(2026, 1, 4),
        DateTime(2026, 3, 1),
        DateTime(2026, 10, 20),
      ]) {
        for (final weeks in [1, 5, 10, 16]) {
          final b = addDays(start, weeks * 7);
          expect(b.hour, start.hour, reason: '$start +${weeks}w hour');
          expect(b.minute, start.minute, reason: '$start +${weeks}w minute');
          expect(b.second, 0);
        }
      }
    });

    test('rolls across month and year ends', () {
      expect(addDays(DateTime(2026, 1, 28), 7), DateTime(2026, 2, 4));
      expect(addDays(DateTime(2026, 12, 30), 7), DateTime(2027, 1, 6));
      // Leap day is a real calendar day, not a special case.
      expect(addDays(DateTime(2028, 2, 22), 7), DateTime(2028, 2, 29));
    });

    test('a 7-day step is exactly one calendar week, every week', () {
      var d = DateTime(2026, 1, 4);
      for (var i = 0; i < 20; i++) {
        final next = addDays(d, 7);
        expect(next.weekday, d.weekday);
        d = next;
      }
    });
  });

  group('plan_detail_screen (source guard)', () {
    late String src;
    setUpAll(() {
      src = File('lib/screens/plan_detail_screen.dart').readAsStringSync();
    });

    test('week windows use calendar arithmetic, not 24-hour spans', () {
      expect(
        RegExp(r'startDate\.add\(\s*Duration\(days:').hasMatch(src),
        isFalse,
        reason: 'a week boundary built with Duration(days: n) drifts an hour '
            'once the plan crosses a DST transition, and a run logged in that '
            'hour is then counted against the wrong week — in both the '
            'adherence banner and the re-plan input.',
      );
      expect(src, contains('addDays(plan.startDate, weekIndex * 7)'));
      expect(src, contains('addDays(plan.startDate, w.weekIndex * 7)'));
    });

    test('the current-week index tolerates a plan with no weeks', () {
      final start = src.indexOf('int _currentWeekIndex(');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('\n  }', start));
      expect(
        body,
        contains('if (_weeks.isEmpty) return 0;'),
        reason: "Dart's clamp throws on an empty range, so "
            'clamp(0, _weeks.length - 1) takes the whole screen down for a '
            'plan whose weeks are missing.',
      );
    });

    test('build reuses that helper rather than clamping inline', () {
      // The inline copy in build() was the one without the guard.
      expect(src, contains('final currentWeek = _currentWeekIndex(p);'));
      expect(
        RegExp(r'\(dayIndex ~/ 7\)\.clamp').allMatches(src).length,
        1,
        reason: 'exactly one place should compute the current week index',
      );
    });
  });
}
