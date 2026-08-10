import 'package:flutter_test/flutter_test.dart';

import '../lib/streaks.dart';

// Helper: build a local-noon DateTime for a given Y/M/D. Noon (not
// midnight) keeps the test stable against fractional-hour TZ offsets.
DateTime localNoon(int y, int m, int d) => DateTime(y, m, d, 12);

void main() {
  group('computeRunStreaks', () {
    test('empty input → zero', () {
      expect(
        computeRunStreaks(const [], localNoon(2026, 5, 13)),
        const RunStreaks(current: 0, best: 0),
      );
    });

    test('single run today → current=1, best=1', () {
      expect(
        computeRunStreaks(
          [localNoon(2026, 5, 13)],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 1),
      );
    });

    test('multiple runs same day count once', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 5, 13),
            DateTime(2026, 5, 13, 7),
            DateTime(2026, 5, 13, 18),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 1),
      );
    });

    test('three-day streak ending today', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 5, 11),
            localNoon(2026, 5, 12),
            localNoon(2026, 5, 13),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 3, best: 3),
      );
    });

    test('Strava grace — missing today but yesterday present', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 5, 11),
            localNoon(2026, 5, 12),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 2, best: 2),
      );
    });

    test('two consecutive days missing breaks the streak', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 5, 9),
            localNoon(2026, 5, 10),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 0, best: 2),
      );
    });

    test('best preserves a historical longer run', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 4, 1),
            localNoon(2026, 4, 2),
            localNoon(2026, 4, 3),
            localNoon(2026, 4, 4),
            localNoon(2026, 4, 5),
            localNoon(2026, 5, 12),
            localNoon(2026, 5, 13),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 2, best: 5),
      );
    });

    test('future-dated runs are clamped to <= today', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 5, 13),
            localNoon(2026, 5, 14),
            localNoon(2026, 5, 15),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 1),
      );
    });

    test('long single streak — current === best', () {
      const days = 30;
      final runs = <DateTime>[
        for (var i = 0; i < days; i++) localNoon(2026, 4, 14 + i),
      ];
      expect(
        computeRunStreaks(runs, localNoon(2026, 5, 13)),
        const RunStreaks(current: 30, best: 30),
      );
    });

    test('input order does not matter', () {
      final ordered = computeRunStreaks(
        [
          localNoon(2026, 5, 11),
          localNoon(2026, 5, 12),
          localNoon(2026, 5, 13),
        ],
        localNoon(2026, 5, 13),
      );
      final shuffled = computeRunStreaks(
        [
          localNoon(2026, 5, 13),
          localNoon(2026, 5, 11),
          localNoon(2026, 5, 12),
        ],
        localNoon(2026, 5, 13),
      );
      expect(ordered, shuffled);
    });

    test('month boundary is consecutive', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2026, 4, 30),
            localNoon(2026, 5, 1),
            localNoon(2026, 5, 13),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 2),
      );
    });

    test('year boundary is consecutive', () {
      expect(
        computeRunStreaks(
          [localNoon(2025, 12, 31), localNoon(2026, 1, 1)],
          localNoon(2026, 1, 1),
        ),
        const RunStreaks(current: 2, best: 2),
      );
    });

    test('gap of exactly one day breaks the streak', () {
      expect(
        computeRunStreaks(
          [localNoon(2026, 5, 11), localNoon(2026, 5, 13)],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 1),
      );
    });
  });

  group('RunStreaks value semantics', () {
    test('equality and hashCode follow current + best', () {
      const a = RunStreaks(current: 3, best: 7);
      const b = RunStreaks(current: 3, best: 7);
      const c = RunStreaks(current: 3, best: 8);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });

  group('DST safety', () {
    test('spring-forward day + next day still register as consecutive', () {
      // Mar 8 2026 is the US DST spring-forward (23-hour day). Y/M/D
      // arithmetic in _previousLocalDay sidesteps the 86_400_000-ms
      // gotcha; this test passes regardless of system TZ.
      expect(
        computeRunStreaks(
          [
            DateTime(2026, 3, 8, 12),
            DateTime(2026, 3, 9, 12),
          ],
          DateTime(2026, 3, 9, 12),
        ),
        const RunStreaks(current: 2, best: 2),
      );
    });

    test('fall-back day + next day still register as consecutive', () {
      // Nov 1 2026 is the US DST fall-back (25-hour day).
      expect(
        computeRunStreaks(
          [
            DateTime(2026, 11, 1, 12),
            DateTime(2026, 11, 2, 12),
          ],
          DateTime(2026, 11, 2, 12),
        ),
        const RunStreaks(current: 2, best: 2),
      );
    });
  });

  group('computeRunStreaks — bestSince bounds best to a period', () {
    test('omitted still reports the all-time best', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2024, 2, 1),
            localNoon(2024, 2, 2),
            localNoon(2024, 2, 3),
            localNoon(2026, 5, 13),
          ],
          localNoon(2026, 5, 13),
        ),
        const RunStreaks(current: 1, best: 3),
      );
    });

    test('drops a streak that ended before the period', () {
      expect(
        computeRunStreaks(
          [
            localNoon(2024, 2, 1),
            localNoon(2024, 2, 2),
            localNoon(2024, 2, 3),
            localNoon(2026, 5, 13),
          ],
          localNoon(2026, 5, 13),
          localNoon(2026, 1, 1),
        ),
        const RunStreaks(current: 1, best: 1),
      );
    });

    test('a streak crossing into the period keeps its full length', () {
      // 28 Dec → 3 Jan. The January card owns it, at seven days, not three.
      final days = [
        localNoon(2025, 12, 28),
        localNoon(2025, 12, 29),
        localNoon(2025, 12, 30),
        localNoon(2025, 12, 31),
        localNoon(2026, 1, 1),
        localNoon(2026, 1, 2),
        localNoon(2026, 1, 3),
      ];
      expect(
        computeRunStreaks(days, localNoon(2026, 1, 31), localNoon(2026, 1, 1))
            .best,
        7,
      );
    });

    test('a streak ending the day before the bound does not count', () {
      final days = [
        localNoon(2025, 12, 28),
        localNoon(2025, 12, 29),
        localNoon(2025, 12, 31),
      ];
      final out =
          computeRunStreaks(days, localNoon(2026, 1, 31), localNoon(2026, 1, 1));
      expect(out.best, 0, reason: 'nothing reaches January');
      expect(out.current, 0);
    });

    test('picks the longest of several in-period streaks', () {
      final days = [
        // 5 days, all before the bound.
        localNoon(2025, 6, 1),
        localNoon(2025, 6, 2),
        localNoon(2025, 6, 3),
        localNoon(2025, 6, 4),
        localNoon(2025, 6, 5),
        // 2 days in period.
        localNoon(2026, 3, 1),
        localNoon(2026, 3, 2),
        // 4 days in period — the answer.
        localNoon(2026, 7, 10),
        localNoon(2026, 7, 11),
        localNoon(2026, 7, 12),
        localNoon(2026, 7, 13),
      ];
      expect(
        computeRunStreaks(days, localNoon(2026, 12, 31), localNoon(2026, 1, 1))
            .best,
        4,
      );
    });

    test('a bound after the anchor admits nothing', () {
      final out = computeRunStreaks(
        [localNoon(2026, 5, 12), localNoon(2026, 5, 13)],
        localNoon(2026, 5, 13),
        localNoon(2027, 1, 1),
      );
      expect(out.best, 0);
      // `current` is anchored at `today` and unaffected by the bound.
      expect(out.current, 2);
    });
  });
}
