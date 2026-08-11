// Mirrors apps/web/src/lib/training/plan_week.test.ts case-for-case.
//
// Regression for the DST undercount (issue #338): the old plan-detail code
// took `DateTime.now().difference(plan.startDate).inDays`, which counts
// absolute 24-hour spans. The 2026-03-01 → 2026-03-15 span crosses the US
// spring-forward on 2026-03-08, so in America/New_York it is 14*24h − 1h and
// `inDays` truncated to 13 → week 1 instead of the correct 14 → 2. Run under
// `TZ=America/New_York` to exercise the exact scenario; the UTC epoch-day
// math makes the result timezone-independent.

import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_week.dart';

void main() {
  test('DST-crossing span reports the correct week (issue #338 repro)', () {
    expect(currentPlanWeekIndex('2026-03-01', '2026-03-15', 12), 2);
  });

  test('non-DST control span reports the correct week', () {
    // 2026-06-01 → 2026-06-15 spans no DST transition: 14 whole days → week 2.
    expect(currentPlanWeekIndex('2026-06-01', '2026-06-15', 12), 2);
  });

  test('day zero is week zero', () {
    expect(currentPlanWeekIndex('2026-03-01', '2026-03-01', 12), 0);
  });

  test('a day before the plan starts clamps to week zero', () {
    expect(currentPlanWeekIndex('2026-03-01', '2026-02-20', 12), 0);
  });

  test('past the last week clamps to the final week index', () {
    expect(currentPlanWeekIndex('2026-03-01', '2026-12-01', 12), 11);
  });

  test('a plan with no weeks yields no valid index', () {
    // -1, not 0: weekCount - 1 underflows. Callers must guard the empty case
    // themselves (fetchActiveOverview used to feed this straight into
    // clamp(0, weeks.length - 1), and Dart's clamp THROWS on inverted bounds).
    expect(currentPlanWeekIndex('2026-03-01', '2026-03-15', 0), -1);
  });
}
