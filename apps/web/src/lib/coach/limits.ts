// Pure helpers extracted from `coach/handler.ts` so the validation /
// clamping / header logic can be unit-tested without booting Supabase.
// `handler.ts` re-imports these so behaviour is identical to the old
// inlined code paths.

import { TIER_LIMITS, type Tier } from './types';

export const DEFAULT_RUNS_LIMIT = 20;

/// Strip the `Bearer ` prefix from a Supabase JWT carried in
/// `X-Supabase-Authorization`. Returns `null` when the input is null,
/// empty, or doesn't yield a token after the prefix is removed.
/// Case-insensitive on the prefix because some clients capitalise
/// "Bearer", others don't.
export function parseAuthHeader(authHeader: string | null | undefined): string | null {
	if (!authHeader) return null;
	const trimmed = authHeader.replace(/^Bearer\s+/i, '');
	return trimmed.length > 0 ? trimmed : null;
}

/// Clamp the caller's requested `recent_runs_limit` against the tier
/// max (free: 30, pro: 200). Falls back to `DEFAULT_RUNS_LIMIT` when
/// the input is missing or non-finite. Floors at 1 — a zero-runs
/// context is never useful for the coach.
export function clampRunsLimit(requested: unknown, tier: Tier): number {
	const max = TIER_LIMITS[tier].maxRunsLimit;
	const n = Number(requested ?? DEFAULT_RUNS_LIMIT);
	if (!Number.isFinite(n)) return DEFAULT_RUNS_LIMIT;
	return Math.min(max, Math.max(1, Math.trunc(n)));
}

/// Reject explicitly-bogus `recent_runs_limit` values BEFORE the
/// handler hits the daily-cap RPC + Anthropic. `undefined` / `null`
/// fall through to the default; everything else must coerce to a
/// finite positive integer (otherwise the caller is sending garbage
/// and the handler 400s rather than silently flooring to 1). Audit/
/// coach May 2026 Low #17.
export function validateRunsLimit(
	requested: unknown,
): { ok: true } | { ok: false; reason: string } {
	if (requested === undefined || requested === null) return { ok: true };
	if (typeof requested === 'boolean') {
		return { ok: false, reason: 'recent_runs_limit must be a number' };
	}
	const n = Number(requested);
	if (!Number.isFinite(n)) {
		return { ok: false, reason: 'recent_runs_limit must be a finite number' };
	}
	if (n < 1) {
		return { ok: false, reason: 'recent_runs_limit must be >= 1' };
	}
	// Sanity cap above any reasonable tier max. Catches a -1e308 / 1e308
	// payload that would otherwise silently min() down without raising.
	if (n > 1_000_000) {
		return { ok: false, reason: 'recent_runs_limit is unreasonably large' };
	}
	return { ok: true };
}

/// Pre-stream JSON error response shape. Re-used by every guard
/// branch in the handler (auth missing, body invalid, daily-limit
/// hit, provider call failed). Caller passes through `extra` for
/// structured fields like `detail`.
export function jsonError(
	status: number,
	error: string,
	extra: Record<string, unknown> = {},
): {
	kind: 'json';
	status: number;
	headers: Record<string, string>;
	body: string;
} {
	return {
		kind: 'json',
		status,
		headers: { 'content-type': 'application/json' },
		body: JSON.stringify({ error, ...extra }),
	};
}

/// `X-Coach-Tier` + `X-RateLimit-*` headers attached to every coach
/// response. Both tiers now carry a finite daily cap, so the limit
/// fields always serialise as a number.
///
/// Pass `kind: 'sse'` for the streaming response branch — the
/// SSE payload includes a `meta` event that re-encodes the same
/// limits, so the headers are useful diagnostics on top. Pass
/// `kind: 'json'` for the error / cap-hit branches — the body
/// already carries `tier` + `used` + `limit` when relevant, so
/// the bare `X-Coach-Tier` header (a free billing-tier oracle to
/// any network observer between the user and CloudFront over TLS)
/// is suppressed. Audit/coach May 2026 Low #13.
export function rateLimitHeaders(
	tier: Tier,
	usedToday: number,
	opts: { kind?: 'sse' | 'json' } = { kind: 'sse' },
): Record<string, string> {
	const limits = TIER_LIMITS[tier];
	const headers: Record<string, string> = {
		'X-RateLimit-Limit': String(limits.dailyLimit),
		'X-RateLimit-Remaining': String(Math.max(0, limits.dailyLimit - usedToday)),
		'X-RateLimit-MaxTokens': String(limits.maxTokens),
		'X-RateLimit-MaxRuns': String(limits.maxRunsLimit),
	};
	if (opts.kind === 'sse') headers['X-Coach-Tier'] = tier;
	return headers;
}

/// Per-message size cap, split by role. Pre-pass-3 the cap was a
/// single 16 KB ceiling for every role, which broke conversation
/// resumption when the assistant emitted a full plan as one message.
/// User input is bounded tightly (anti-abuse — legitimate planning
/// prompts rarely exceed 4 KB); assistant output is bounded loosely.
/// The list-length and aggregate-content caps still bound the total
/// prompt token cost regardless of role mix.
export const MAX_COACH_MESSAGES = 100;
export const MAX_COACH_USER_CONTENT_BYTES = 8 * 1024;
export const MAX_COACH_ASSISTANT_CONTENT_BYTES = 64 * 1024;
export const MAX_COACH_TOTAL_CONTENT_BYTES = 512 * 1024;

/// Validate the messages array off the coach request body. Returns
/// `{ ok: true }` if the array is well-formed and within every cap;
/// otherwise `{ ok: false, reason }` with a short tag identifying which
/// cap fired. The handler turns any non-ok return into a 400
/// "invalid messages" — the reason tag is for tests + future telemetry,
/// not the wire response.
export function validateCoachMessages(
	messages: unknown,
): { ok: true } | { ok: false; reason: string } {
	if (!Array.isArray(messages)) return { ok: false, reason: 'not-array' };
	if (messages.length > MAX_COACH_MESSAGES) return { ok: false, reason: 'too-many' };
	let total = 0;
	for (const m of messages) {
		const content = (m as { content?: unknown } | null | undefined)?.content;
		if (typeof content !== 'string') return { ok: false, reason: 'content-not-string' };
		const role = (m as { role?: unknown }).role;
		const cap =
			role === 'assistant'
				? MAX_COACH_ASSISTANT_CONTENT_BYTES
				: MAX_COACH_USER_CONTENT_BYTES;
		if (content.length > cap) return { ok: false, reason: 'per-message-too-long' };
		total += content.length;
	}
	if (total > MAX_COACH_TOTAL_CONTENT_BYTES) return { ok: false, reason: 'aggregate-too-long' };
	return { ok: true };
}

/// Build the personality addendum appended to the system prompt when
/// the runner has set a non-default `coach_personality` preference.
/// Empty string for the default / unknown styles so the system prompt
/// is unchanged from baseline.
export function personalityAddendum(coachStyle: string | null | undefined): string {
	if (coachStyle === 'drill_sergeant') {
		return '\n\nTone override: be blunt, demanding, and no-nonsense. Push the runner hard. Short sentences. No coddling. Think military coach.';
	}
	if (coachStyle === 'analytical') {
		return '\n\nTone override: be data-driven and precise. Lead with numbers, percentages, and trends. Cite specific paces, distances, and dates. Think sports scientist.';
	}
	return '';
}
