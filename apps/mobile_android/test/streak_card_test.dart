import 'package:flutter_test/flutter_test.dart';

import '../lib/streak_card.dart';
import '../lib/streaks.dart';

/// Mirrors `apps/web/src/lib/runs/streak_card.test.ts` — 7 mirror cases,
/// plus the Dart-only [mergeAllTimeStreaks] cases (the offline-first
/// union fold has no web twin).
void main() {
  group('streakCardState', () {
    test('a pre-window best streak wins over the windowed figure', () {
      // The defect the RPC fixes: a 10-day streak years ago is outside the
      // slice of history resident on this device, so the local compute
      // reports 3 and the old sub-label claimed 3 was the all-time best.
      final s = streakCardState(
        const RunStreaks(current: 3, best: 10),
        const RunStreaks(current: 3, best: 3),
      );
      expect(
        s,
        const StreakCardState(current: 3, sub: StreakSubKind.best, bestN: 10),
      );
    });

    test('server current is the headline when available', () {
      final s = streakCardState(
        const RunStreaks(current: 4, best: 9),
        const RunStreaks(current: 3, best: 3),
      );
      expect(s.current, 4);
    });

    test('all-time best fires only when the server confirms it', () {
      final s = streakCardState(
        const RunStreaks(current: 5, best: 5),
        const RunStreaks(current: 5, best: 5),
      );
      expect(s.sub, StreakSubKind.allTimeBest);
    });

    test('server data: a broken streak still shows the numeric best', () {
      // Matches the pre-RPC template: best > current always wins the label,
      // so "restart" only ever renders from the no-server fallback below.
      final s = streakCardState(
        const RunStreaks(current: 0, best: 6),
        const RunStreaks(current: 0, best: 0),
      );
      expect(
        s,
        const StreakCardState(current: 0, sub: StreakSubKind.best, bestN: 6),
      );
    });

    test('server data: no runs ever offers a start', () {
      final s = streakCardState(
        const RunStreaks(current: 0, best: 0),
        const RunStreaks(current: 0, best: 0),
      );
      expect(s, const StreakCardState(current: 0, sub: StreakSubKind.start));
    });

    test('no server data: an active streak makes no all-time claim', () {
      // Fail-closed (§ 470): rendering the resident best as "best N" or
      // "all-time best" is the silently-low number this card used to show.
      final s = streakCardState(null, const RunStreaks(current: 3, best: 8));
      expect(s, const StreakCardState(current: 3, sub: StreakSubKind.none));
    });

    test('no server data: restart/start need no all-time knowledge', () {
      // A resident best > 0 proves a streak existed; "run to restart it"
      // claims nothing numeric, so it may render before the RPC resolves.
      expect(
        streakCardState(null, const RunStreaks(current: 0, best: 2)),
        const StreakCardState(current: 0, sub: StreakSubKind.restart),
      );
      expect(
        streakCardState(null, const RunStreaks(current: 0, best: 0)),
        const StreakCardState(current: 0, sub: StreakSubKind.start),
      );
    });
  });

  group('mergeAllTimeStreaks (mobile-only)', () {
    test('takes the pointwise max on both fields', () {
      expect(
        mergeAllTimeStreaks(
          const RunStreaks(current: 3, best: 10),
          const RunStreaks(current: 4, best: 4),
        ),
        const RunStreaks(current: 4, best: 10),
      );
    });

    test('an unsynced local run day is never walked back', () {
      // A run recorded moments ago has not synced, so the server row still
      // reads current 0 — the local day must survive the fold.
      expect(
        mergeAllTimeStreaks(
          const RunStreaks(current: 0, best: 10),
          const RunStreaks(current: 1, best: 1),
        ),
        const RunStreaks(current: 1, best: 10),
      );
    });

    test('fresh install: the server row carries the deep history', () {
      expect(
        mergeAllTimeStreaks(
          const RunStreaks(current: 2, best: 50),
          const RunStreaks(current: 0, best: 0),
        ),
        const RunStreaks(current: 2, best: 50),
      );
    });
  });
}
