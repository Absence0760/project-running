/// Dashboard streak-card state — which claim each figure source may back.
///
/// Mirrors `apps/web/src/lib/runs/streak_card.ts`. Keep in lockstep — the
/// shared-library-syncer agent watches the pair. The pair's scope is
/// [StreakCardState] + [streakCardState]; [mergeAllTimeStreaks] is
/// mobile-only (see its doc) and deliberately not twinned.
///
/// The card's headline + sub-label prefer the server-side all-time
/// aggregate (`run_streaks_for_user`, decisions § 471 / § 475). When that
/// fetch has not resolved — loading or failed — the local compute is only
/// trusted for claims it can actually prove: a numeric "best N" or an
/// "all-time best" from whatever slice of history is resident is exactly
/// the silently-low number § 470 forbids, so those render as nothing
/// instead.
library;

import 'streaks.dart';

enum StreakSubKind { best, allTimeBest, restart, start, none }

class StreakCardState {
  final int current;
  final StreakSubKind sub;

  /// The numeric best-streak claim; non-null iff [sub] is
  /// [StreakSubKind.best].
  final int? bestN;

  const StreakCardState({
    required this.current,
    required this.sub,
    this.bestN,
  });

  @override
  bool operator ==(Object other) =>
      other is StreakCardState &&
      other.current == current &&
      other.sub == sub &&
      other.bestN == bestN;

  @override
  int get hashCode => Object.hash(current, sub, bestN);

  @override
  String toString() =>
      'StreakCardState(current: $current, sub: $sub, bestN: $bestN)';
}

StreakCardState streakCardState(RunStreaks? allTime, RunStreaks windowed) {
  if (allTime != null) {
    // best >= current by construction (the current island counts toward
    // best), so equality is the only non-"best" case: an active streak
    // that IS the record, or no run days at all.
    final current = allTime.current;
    final best = allTime.best;
    if (best > current) {
      return StreakCardState(
          current: current, sub: StreakSubKind.best, bestN: best);
    }
    if (current > 0) {
      return StreakCardState(current: current, sub: StreakSubKind.allTimeBest);
    }
    return StreakCardState(current: current, sub: StreakSubKind.start);
  }
  final current = windowed.current;
  final best = windowed.best;
  if (current > 0) {
    return StreakCardState(current: current, sub: StreakSubKind.none);
  }
  if (best > 0) {
    return StreakCardState(current: current, sub: StreakSubKind.restart);
  }
  return StreakCardState(current: current, sub: StreakSubKind.start);
}

/// Mobile-only (not part of the web pair): fold the RPC row together with
/// the on-device compute before it becomes the card's all-time claim.
/// Both inputs are lower bounds over subsets of the true run-day set —
/// the server misses runs recorded here but not yet synced, the device
/// misses history never paged in — and a streak only grows as run days
/// are added, so the pointwise max is the closest provable figure.
/// Without it the RPC's slightly-stale row would walk a just-recorded
/// run's streak back a day, the same silent correction § 471 forbids.
/// Web needs no twin: its windowed fetch reads the same database the
/// aggregate does, so the RPC row is always the superset there.
RunStreaks mergeAllTimeStreaks(RunStreaks rpc, RunStreaks local) => RunStreaks(
      current: rpc.current > local.current ? rpc.current : local.current,
      best: rpc.best > local.best ? rpc.best : local.best,
    );
