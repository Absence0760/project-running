/// Spectator freshness: how old the last live ping is, and whether it
/// is stale enough that the position can no longer be trusted as the
/// runner's *current* location. The live surface receives a `sent_at_ms`
/// (Go hub) / `at` (Supabase path) timestamp on every ping but historically
/// never consumed it, so a runner who lost signal hours ago rendered as a
/// permanently-fresh "LIVE" dot — fatal for a spectator asking "is my
/// person OK?" and for a SAR actor deciding whether a last-known position
/// is current. This computes an honest age + a stale flag.
///
/// Returns a *structured* result (no language) so web (`m()`) and the Dart
/// twin (ARB) localize identically. TS↔Dart parity pair with
/// `apps/mobile_android/lib/live_freshness.dart` — keep in lockstep.

/// A ping older than this is treated as stale. ~18 missed 5s broadcaster
/// pings: long enough to ride out ordinary cellular flakiness, short
/// enough that a real signal loss surfaces within a minute and a half.
export const LIVE_STALE_AFTER_MS = 90_000;

export type FreshnessBucket = 'now' | 'seconds' | 'minutes' | 'hours' | 'days';

export interface Freshness {
	/// Age of the last ping in ms, clamped to >= 0 (a future-dated ping
	/// from clock skew reads as "just now", never a negative age).
	ageMs: number;
	/// True once `ageMs >= staleAfterMs` — the caller should stop
	/// presenting the position as live-current.
	stale: boolean;
	/// Coarsened time bucket for display; pair with `value`.
	bucket: FreshnessBucket;
	/// The number to show for the bucket (e.g. bucket `minutes`, value 3
	/// → "Updated 3 min ago"). 0 for `now`.
	value: number;
}

export function freshnessFor(
	sentAtMs: number,
	nowMs: number,
	staleAfterMs: number = LIVE_STALE_AFTER_MS,
): Freshness {
	const ageMs = Math.max(0, nowMs - sentAtMs);
	const stale = ageMs >= staleAfterMs;
	const s = Math.floor(ageMs / 1000);
	if (s < 10) return { ageMs, stale, bucket: 'now', value: 0 };
	if (s < 60) return { ageMs, stale, bucket: 'seconds', value: s };
	const min = Math.floor(s / 60);
	if (min < 60) return { ageMs, stale, bucket: 'minutes', value: min };
	const h = Math.floor(min / 60);
	if (h < 24) return { ageMs, stale, bucket: 'hours', value: h };
	return { ageMs, stale, bucket: 'days', value: Math.floor(h / 24) };
}
