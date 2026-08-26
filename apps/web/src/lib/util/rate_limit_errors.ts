/// Detect a P0001 raised by the `enforce_create_rate_limit` trigger
/// (migration 20260907_001) and pull the two facts it carries out of
/// the message: which bucket refused, and how long the caller must
/// wait. The trigger raises an exception of the form
/// `rate limit exceeded for <bucket>, retry in <seconds>s` with
/// SQLSTATE P0001 and the hint
/// `You are creating these too quickly. Please wait and try again.`
///
/// Parse only — no prose. The sentence a reader sees is a per-locale
/// decision (the verb phrase inflects, the wait pluralises), so it
/// lives in the message catalogues and is assembled at the render
/// layer: `i18n/rate_limit_message.ts` on web, `rate_limit_message.dart`
/// on mobile. See decisions.md § 744.
///
/// Returns null when the error isn't a rate-limit one — callers should
/// rethrow the original error in that case so unrelated failures (RLS
/// denies, slug collisions, etc.) aren't masked.
///
/// Pure string-in / struct-out — no Supabase, no fetch, no i18n
/// dependency — so it unit-tests without spinning up the stack.

export interface RateLimitInfo {
	/// The bucket name verbatim, as the trigger spelled it. Deliberately a
	/// plain string rather than a union of the buckets that exist today: a
	/// bucket a later migration adds must still reach the render layer as
	/// itself, so that layer can pick the honest generic sentence for it.
	bucket: string;
	/// Whole seconds still to wait, or null when the trigger reported a
	/// non-positive figure. Null is "wait a moment", not "wait zero" — the
	/// render layer has its own copy for it.
	seconds: number | null;
}

export function parseRateLimitError(
	err: { code?: string; message?: string } | null | undefined,
): RateLimitInfo | null {
	if (!err || err.code !== 'P0001' || !err.message) return null;
	const match = err.message.match(/rate limit exceeded for (\w+),\s*retry in\s+(\d+)s/i);
	if (!match) return null;
	const [, bucket, secsStr] = match;
	const secs = Number(secsStr);
	return { bucket, seconds: Number.isFinite(secs) && secs > 0 ? secs : null };
}
