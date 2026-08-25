import 'package:flutter_test/flutter_test.dart';
import '../lib/plan_start.dart';

void main() {
  test('nextSunday is a no-op on a Sunday', () {
    // 2026-06-07 is a Sunday.
    expect(nextSunday(DateTime(2026, 6, 7)), DateTime(2026, 6, 7));
    expect(isSunday(DateTime(2026, 6, 7)), isTrue);
  });

  test('nextSunday snaps a midweek date forward to the next Sunday', () {
    // 2026-06-03 is a Wednesday → 2026-06-07.
    expect(nextSunday(DateTime(2026, 6, 3)), DateTime(2026, 6, 7));
    expect(isSunday(DateTime(2026, 6, 3)), isFalse);
  });

  test('nextSunday snaps a Saturday forward one day', () {
    // 2026-06-06 is a Saturday → 2026-06-07.
    expect(nextSunday(DateTime(2026, 6, 6)), DateTime(2026, 6, 7));
  });

  test('nextSunday crosses a month boundary', () {
    // 2026-06-30 is a Tuesday → 2026-07-05 (Sunday).
    expect(nextSunday(DateTime(2026, 6, 30)), DateTime(2026, 7, 5));
  });
}
