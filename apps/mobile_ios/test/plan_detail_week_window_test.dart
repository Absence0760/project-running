// Plan-detail week-window arithmetic and the current-week index.
//
// Kept out of `training_test.dart` (which mirrors `training.test.ts`
// case-for-case) because these pin a screen's use of the engine, not the
// engine itself.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../lib/plan_week.dart';
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

    test('a week end derived from the week start is the next week start', () {
      // The re-plan input builds weekStart with addDays and weekEnd off it; if
      // only one of the two is calendar-safe they disagree by an hour across a
      // transition and `isComplete` grades the wrong week. Spans the US spring
      // forward (2026-03-08) and fall back (2026-11-01).
      for (final start in [DateTime(2026, 3, 1), DateTime(2026, 10, 25)]) {
        for (var w = 0; w < 4; w++) {
          final weekStart = addDays(start, w * 7);
          expect(addDays(weekStart, 7), addDays(start, (w + 1) * 7));
          expect(addDays(weekStart, 7).hour, 0);
        }
      }
    });
  });

  group('currentPlanWeekIndex on the plan-detail dates', () {
    test('a span crossing the autumn fall-back reports the correct week', () {
      // The 169-hour direction: 2026-10-25 → 2026-11-08 in America/New_York is
      // 14*24h + 1h. Counting epoch-days keeps it at 14 days → week 2 in every
      // timezone, and the 7-day boundary a week earlier stays week 1.
      expect(currentPlanWeekIndex('2026-10-25', '2026-11-08', 12), 2);
      expect(currentPlanWeekIndex('2026-10-25', '2026-11-01', 12), 1);
      expect(currentPlanWeekIndex('2026-10-25', '2026-10-31', 12), 0);
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
      expect(
        RegExp(r'weekStart\.add\(').hasMatch(src),
        isFalse,
        reason: 'the week end must step off the week start with the same '
            'calendar arithmetic the week start used, or the two boundaries '
            'disagree by an hour across a transition and `isComplete` grades '
            'the wrong week.',
      );
      expect(RegExp(r'addDays\(weekStart, 7\)').allMatches(src).length, 2);
    });

    test('the current-week index counts epoch days, not 24-hour spans', () {
      final start = src.indexOf('int _currentWeekIndex(');
      expect(start, isNonNegative);
      final body = src.substring(start, src.indexOf('\n  }', start));
      expect(
        body.contains('.inDays'),
        isFalse,
        reason: 'difference().inDays counts absolute 24-hour spans, so a '
            'start→today span crossing a DST transition truncates a day short '
            'and reports the previous week — a whole week off on the '
            'plan-detail surface (issue #338).',
      );
      expect(
        body,
        contains('currentPlanWeekIndex('),
        reason: 'the epoch-day basis is shared with the web twin '
            'apps/web/src/lib/training/plan_week.ts — do not re-derive it.',
      );
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

    test('build reuses that helper rather than deriving the index inline', () {
      // The inline copy in build() was the one without the guard.
      expect(src, contains('final currentWeek = _currentWeekIndex(p);'));
      expect(
        RegExp(r'currentPlanWeekIndex\(').allMatches(src).length,
        1,
        reason: 'exactly one place should compute the current week index',
      );
    });
  });
}
