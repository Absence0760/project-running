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
///
/// The `unknown` bucket is deliberately web-only: Dart's `int` parameters
/// cannot represent NaN, so the twin has no way to be handed an age it
/// cannot establish. Adding the enum value there would be dead code.

/// A ping older than this is treated as stale. ~18 missed 5s broadcaster
/// pings: long enough to ride out ordinary cellular flakiness, short
/// enough that a real signal loss surfaces within a minute and a half.
export const LIVE_STALE_AFTER_MS = 90_000;

export type FreshnessBucket = 'now' | 'seconds' | 'minutes' | 'hours' | 'days' | 'unknown';

/// Discriminated on `bucket` so a caller that switches on it narrows `value`
/// to a real number on every displayable branch, and cannot pass the
/// unknown-age null into a formatter expecting one.
export type Freshness =
	| {
			/// Age of the last ping in ms, clamped to >= 0 (a future-dated ping
			/// from clock skew reads as "just now", never a negative age).
			ageMs: number;
			/// True once `ageMs >= staleAfterMs` — the caller should stop
			/// presenting the position as live-current.
			stale: boolean;
			/// Coarsened time bucket for display; pair with `value`.
			bucket: Exclude<FreshnessBucket, 'unknown'>;
			/// The number to show for the bucket (e.g. bucket `minutes`, value 3
			/// → "Updated 3 min ago"). 0 for `now`.
			value: number;
	  }
	| {
			/// The age could not be established at all.
			ageMs: null;
			/// Always true — an unknown age fails closed.
			stale: true;
			bucket: 'unknown';
			value: null;
	  };

export function freshnessFor(
	sentAtMs: number,
	nowMs: number,
	staleAfterMs: number = LIVE_STALE_AFTER_MS,
): Freshness {
	// A malformed `at` column / missing `sent_at_ms` yields NaN here, and every
	// downstream comparison against NaN is false — so an age we cannot establish
	// would render as a green LIVE dot, the exact failure this module exists to
	// prevent. Fail closed: unknown age is stale.
	if (!Number.isFinite(sentAtMs) || !Number.isFinite(nowMs)) {
		return { ageMs: null, stale: true, bucket: 'unknown', value: null };
	}
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

/// The race clock as it reads *now*, from the elapsed time the last ping
/// reported plus how long ago that ping was.
///
/// A cut-off is a deadline measured from the runner's start, and it keeps
/// running while they are out of signal. Driving cut-off maths straight off
/// the last ping's `elapsed_s` freezes the clock the moment the pings stop —
/// so a runner who went dark 40 min before their cut-off would still show the
/// budget they had at the last fix, and a limit that has since expired would
/// never register. Advance the clock by the ping age instead: no new distance
/// is invented (the position stays at the last fix), only time that has
/// genuinely passed.
///
/// An age we cannot establish advances nothing — the caller is already in the
/// `unknown`/stale branch above, which labels the readout rather than
/// guessing at it.
export function liveElapsedS(anchorElapsedS: number, ageMs: number | null): number {
	const base = Number.isFinite(anchorElapsedS) ? Math.max(0, anchorElapsedS) : 0;
	if (ageMs == null || !Number.isFinite(ageMs) || ageMs <= 0) return base;
	return base + Math.floor(ageMs / 1000);
}
