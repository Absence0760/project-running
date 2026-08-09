// Versioned AI-disclosure consent — the gate every endpoint that ships a
// user's data to Anthropic runs before it fans out. GDPR Art 6(1)(a).
//
// The consent record is `user_profiles.ai_disclosure_version` (which
// disclosure was accepted) paired with `coach_consent_at` (when). Neither
// is in the public-safe column grant, so the record is read through the
// SECURITY DEFINER `get_my_profile()` RPC and written only by
// `record_ai_disclosure_consent()` (migration 20270511_001).
//
// Versions are a monotone ladder — each one is a strict superset of the
// last — which is what makes "accepted >= required" sound:
//
//   1  AI Coach only.
//   2  All AI features: the Coach plus the AI route assistant.
//
// Every AI endpoint declares its minimum. Adding the next AI feature means
// a new version with new copy, not a new boolean column and not quietly
// widening what an existing acceptance covers.
//
// This module lives outside `$lib/coach` on purpose: the route-AI handlers
// need it, and importing from the coach barrel drags the Anthropic SDK
// into bundles that have no business carrying it.

/** Minimum disclosure version /api/coach requires. */
export const AI_DISCLOSURE_VERSION_COACH = 1;

/**
 * Minimum disclosure version the AI route assistant requires
 * (/api/coach/route-describe + /api/coach/route-request). Higher than the
 * Coach's because the route endpoints send a different payload — the typed
 * request text and a coarse location label — for a different purpose than
 * the Coach copy described.
 */
export const AI_DISCLOSURE_VERSION_ROUTE_AI = 2;

/**
 * The newest disclosure this build knows how to present. Must equal the
 * SQL `ai_disclosure_current_version()`; `ai_disclosure.test.ts` reads the
 * migration and fails if they drift.
 */
export const AI_DISCLOSURE_CURRENT_VERSION = AI_DISCLOSURE_VERSION_ROUTE_AI;

/** Machine-readable `error` code every AI endpoint uses on a consent denial. */
export const AI_DISCLOSURE_ERROR = 'ai_disclosure_required';

/**
 * - `missing` — nothing on record (never accepted, or withdrawn).
 * - `stale`   — accepted an older disclosure that did not cover this use.
 * - `unknown` — the record is unreadable or names a version this build
 *               cannot describe. Denied rather than trusted: a disclosure
 *               we cannot render is a disclosure we cannot prove was made.
 */
export type AiDisclosureDenial = 'missing' | 'stale' | 'unknown';

export interface AiDisclosureRecord {
	version: unknown;
	acceptedAt: unknown;
}

export type AiDisclosureCheck =
	| { ok: true; version: number }
	| { ok: false; reason: AiDisclosureDenial };

/** Pull the consent record out of a `get_my_profile()` row of unknown shape. */
export function aiDisclosureFromProfileRow(row: unknown): AiDisclosureRecord {
	if (!row || typeof row !== 'object') return { version: null, acceptedAt: null };
	const o = row as Record<string, unknown>;
	return { version: o.ai_disclosure_version, acceptedAt: o.coach_consent_at };
}

/** Fail-closed: anything that is not a complete, known, sufficient record denies. */
export function checkAiDisclosure(
	record: AiDisclosureRecord,
	requiredVersion: number,
): AiDisclosureCheck {
	const acceptedAt = record.acceptedAt;
	const hasAcceptedAt = typeof acceptedAt === 'string' && acceptedAt.length > 0;
	if (record.version == null || !hasAcceptedAt) return { ok: false, reason: 'missing' };
	const version = record.version;
	if (typeof version !== 'number' || !Number.isInteger(version)) {
		return { ok: false, reason: 'unknown' };
	}
	if (version < 1 || version > AI_DISCLOSURE_CURRENT_VERSION) {
		return { ok: false, reason: 'unknown' };
	}
	if (version < requiredVersion) return { ok: false, reason: 'stale' };
	return { ok: true, version };
}

/** Body every AI endpoint returns with its 403 so clients can prompt, not just fail. */
export function aiDisclosureDenialBody(requiredVersion: number): Record<string, unknown> {
	return { error: AI_DISCLOSURE_ERROR, required_version: requiredVersion };
}

type ProfileLookup = () => Promise<{
	data: unknown;
	error: { code?: string; message?: string } | null;
}>;

export type AiDisclosureGate =
	| { ok: true; version: number }
	| { ok: false; status: 500; reason: 'lookup_failed' }
	| { ok: false; status: 403; reason: AiDisclosureDenial };

/**
 * Load the caller's consent record and grade it. Takes the loader rather
 * than the Supabase client so a handler can pass
 * `() => supabase.rpc('get_my_profile').maybeSingle()` and a test can pass
 * a stub without standing up a client.
 */
export async function gateAiDisclosure(
	loadProfile: ProfileLookup,
	requiredVersion: number,
	logTag: string,
): Promise<AiDisclosureGate> {
	let res: Awaited<ReturnType<ProfileLookup>>;
	try {
		res = await loadProfile();
	} catch (e) {
		console.error(`[${logTag}] ai disclosure lookup threw`, {
			message: e instanceof Error ? e.message : String(e),
		});
		return { ok: false, status: 500, reason: 'lookup_failed' };
	}
	if (res.error) {
		console.error(`[${logTag}] ai disclosure lookup failed`, {
			code: res.error.code,
			message: res.error.message,
		});
		return { ok: false, status: 500, reason: 'lookup_failed' };
	}
	const check = checkAiDisclosure(aiDisclosureFromProfileRow(res.data), requiredVersion);
	if (!check.ok) {
		// `unknown` means the stored version is outside this build's ladder —
		// a corrupt record or a deployment lagging the database. It denies
		// like the others, but an operator needs to be able to tell them
		// apart, so the reason is on the log line.
		console.error(`[${logTag}] ai disclosure denied`, {
			reason: check.reason,
			required_version: requiredVersion,
		});
		return { ok: false, status: 403, reason: check.reason };
	}
	return check;
}
