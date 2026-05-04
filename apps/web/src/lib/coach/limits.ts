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
/// response. Pro tier reports "unlimited" for the daily fields since
/// `dailyLimit = Infinity` doesn't serialise meaningfully.
export function rateLimitHeaders(tier: Tier, usedToday: number): Record<string, string> {
	const limits = TIER_LIMITS[tier];
	const limitStr = Number.isFinite(limits.dailyLimit) ? String(limits.dailyLimit) : 'unlimited';
	const remainingStr = Number.isFinite(limits.dailyLimit)
		? String(Math.max(0, limits.dailyLimit - usedToday))
		: 'unlimited';
	return {
		'X-Coach-Tier': tier,
		'X-RateLimit-Limit': limitStr,
		'X-RateLimit-Remaining': remainingStr,
		'X-RateLimit-MaxTokens': String(limits.maxTokens),
		'X-RateLimit-MaxRuns': String(limits.maxRunsLimit),
	};
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
