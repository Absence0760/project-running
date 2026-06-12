/// Spectator freshness: how old the last live ping is, and whether it
/// is stale enough that the position can no longer be trusted as the
/// runner's *current* location. The live surface receives an `at`
/// timestamp on every ping but historically never consumed it, so a
/// runner who lost signal hours ago rendered as a permanently-fresh
/// "Live" dot — fatal for a spectator asking "is my person OK?" and for
/// a SAR actor deciding whether a last-known position is current. This
/// computes an honest age + a stale flag.
///
/// Returns a *structured* result (no language) so mobile (ARB) and the
/// web twin (`m()`) localize identically. TS↔Dart parity pair with
/// `apps/web/src/lib/runs/live_freshness.ts` — keep in lockstep.
library;

/// A ping older than this is treated as stale. ~18 missed 5s broadcaster
/// pings: long enough to ride out ordinary cellular flakiness, short
/// enough that a real signal loss surfaces within a minute and a half.
const int liveStaleAfterMs = 90000;

enum FreshnessBucket { now, seconds, minutes, hours, days }

class Freshness {
  /// Age of the last ping in ms, clamped to >= 0 (a future-dated ping
  /// from clock skew reads as "just now", never a negative age).
  final int ageMs;

  /// True once `ageMs >= staleAfterMs` — the caller should stop
  /// presenting the position as live-current.
  final bool stale;

  /// Coarsened time bucket for display; pair with [value].
  final FreshnessBucket bucket;

  /// The number to show for the bucket (e.g. bucket `minutes`, value 3
  /// → "Updated 3 min ago"). 0 for `now`.
  final int value;

  const Freshness({
    required this.ageMs,
    required this.stale,
    required this.bucket,
    required this.value,
  });
}

Freshness freshnessFor(
  int sentAtMs,
  int nowMs, {
  int staleAfterMs = liveStaleAfterMs,
}) {
  final diff = nowMs - sentAtMs;
  final ageMs = diff < 0 ? 0 : diff;
  final stale = ageMs >= staleAfterMs;
  final s = ageMs ~/ 1000;
  if (s < 10) {
    return Freshness(ageMs: ageMs, stale: stale, bucket: FreshnessBucket.now, value: 0);
  }
  if (s < 60) {
    return Freshness(ageMs: ageMs, stale: stale, bucket: FreshnessBucket.seconds, value: s);
  }
  final min = s ~/ 60;
  if (min < 60) {
    return Freshness(ageMs: ageMs, stale: stale, bucket: FreshnessBucket.minutes, value: min);
  }
  final h = min ~/ 60;
  if (h < 24) {
    return Freshness(ageMs: ageMs, stale: stale, bucket: FreshnessBucket.hours, value: h);
  }
  return Freshness(ageMs: ageMs, stale: stale, bucket: FreshnessBucket.days, value: h ~/ 24);
}
