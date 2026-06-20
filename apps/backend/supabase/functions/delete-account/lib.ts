// Helpers for the delete-account Edge Function. Audit/account-
// deletion-completeness (May 2026) expanded the handler from
// "drain Storage + admin.deleteUser" to a full third-party cleanup
// sweep. The pure parts of that expansion live here so they can be
// unit-tested without a Supabase / OAuth / RevenueCat / FCM stack.

// ─── third-party endpoints ───

export const STRAVA_DEAUTHORIZE_URL =
	'https://www.strava.com/oauth/deauthorize';

export function revenueCatSubscriberUrl(userId: string): string {
	// RevenueCat REST API: DELETE /v1/subscribers/{app_user_id}.
	// userId is a Supabase UUID — URL-safe but encode defensively in
	// case a future scheme uses non-URL chars.
	return `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(userId)}`;
}

export const FCM_BATCH_REMOVE_URL =
	'https://iid.googleapis.com/iid/v1:batchRemove';

export function fcmBatchRemoveBody(tokens: string[]): string {
	// Defensive cap: 1000 tokens is FCM's documented batch maximum.
	// The deletion path should never hit this in practice (a user
	// rarely has more than a handful of devices), but truncate
	// silently rather than 400 on a freak case.
	const capped = tokens.slice(0, 1000).filter((t) => t.length > 0);
	return JSON.stringify({ registration_tokens: capped });
}

// ─── audit-log key derivation ───

/**
 * Pseudonymous hash of the user id, written to deletion_audit_log
 * so the table isn't itself a directory of deleted accounts.
 *
 * Two modes (keyed by whether `DELETION_AUDIT_KEY` is set):
 *
 *   * **Keyed (recommended)**: HMAC-SHA256(key, userId). An adversary
 *     who has a UUID and wants to test "was this user deleted?"
 *     cannot reproduce the hash without the key — the audit log
 *     becomes meaningfully pseudonymous. Set the env var to any
 *     ≥ 32-byte secret (operator task; see deployment.md).
 *
 *   * **Unkeyed (legacy)**: SHA-256(salt || userId). Same scheme as
 *     the original 20260917_001 audit log. Acceptable in the short
 *     term because the table is service-role only, but a holder of
 *     the UUID can reconstruct the hash and confirm deletion. The
 *     `audit/account-deletion-completeness` finding documents this.
 *
 * The mode is chosen per-call: existing rows under the legacy salt
 * are still resolvable by passing no key; new rows written after
 * the operator sets the env var use HMAC. Hex output either way.
 */
export async function hashUserIdForAudit(
	userId: string,
	options: { key?: string | undefined; salt?: string } = {},
): Promise<string> {
	const key = options.key ?? Deno.env.get('DELETION_AUDIT_KEY') ?? '';
	const enc = new TextEncoder();
	let digest: ArrayBuffer;
	if (key.length > 0) {
		const cryptoKey = await crypto.subtle.importKey(
			'raw',
			enc.encode(key),
			{ name: 'HMAC', hash: 'SHA-256' },
			false,
			['sign'],
		);
		digest = await crypto.subtle.sign('HMAC', cryptoKey, enc.encode(userId));
	} else {
		const salt = options.salt ?? 'threkir-deletion-audit-v1';
		digest = await crypto.subtle.digest('SHA-256', enc.encode(`${salt}:${userId}`));
	}
	const bytes = new Uint8Array(digest);
	let hex = '';
	for (const b of bytes) hex += b.toString(16).padStart(2, '0');
	return hex;
}

// ─── per-table deleted-row counts ───

/**
 * Compact JSON encoding of the per-table row counts the delete-account
 * saga removed (or anonymised) before the auth-row cascade, written to
 * `deletion_audit_log.notes` on a successful erasure. It is the Art
 * 5(2) accountability counterpart to `third_party_outcomes`: a
 * structured "we deleted N jobs, M rate-limit rows, K reports, …" so a
 * regulator's "what did you actually erase for user X?" has an answer
 * beyond a bare `ok`.
 *
 * It rides in `notes` (rather than a dedicated column) because the
 * audit row's `result` already disambiguates: `result='ok'` → notes is
 * this counts JSON; a `*_failed` result → notes is the failure reason.
 * Only the tables the EF drains explicitly are counted — the rows that
 * vanish inside `auth.admin.deleteUser`'s FK cascade are not
 * individually visible to the handler.
 *
 * Returns null for an empty map (nothing was drained). Stays inside the
 * column's 200-char CHECK: the key set is small + bounded, but if a
 * freak total ever overruns we emit a still-valid-JSON summary rather
 * than risk a 23514 that would lose the whole audit row.
 */
export function formatDeletedCounts(
	counts: Record<string, number>,
): string | null {
	const keys = Object.keys(counts);
	if (keys.length === 0) return null;
	const json = JSON.stringify(counts);
	if (json.length <= 200) return json;
	const total = keys.reduce((sum, k) => sum + (counts[k] ?? 0), 0);
	return JSON.stringify({ tables: keys.length, total_rows: total });
}

// ─── result codes (mirror the deletion_audit_log CHECK) ───

// Keep in lockstep with the deletion_audit_log result CHECK
// (20260917_001 + 20261111_001). Each saga step that can fail before the
// auth-row cascade has its own code so the Art 17(2) trail says which step
// failed (audit-findings 2026-05-30 Medium).
export type DeletionAuditResult =
	| 'ok'
	| 'storage_drain_failed'
	| 'auth_delete_failed'
	| 'reports_cleanup_failed'
	| 'vault_cleanup_failed'
	| 'jobs_drain_failed'
	| 'rate_limits_drain_failed'
	| 'segments_anonymise_failed';

// ─── per-third-party outcome record (lands in deletion_audit_log.third_party_outcomes) ───

/**
 * GDPR Art 17(2) recipient-notification evidence trail. The
 * delete-account EF calls third parties as best-effort; this
 * record makes the outcome of each call auditable post-fact.
 *
 *   * `ok`       — the call succeeded.
 *   * `skipped`  — there was nothing to clean (no token / no
 *                  Android device / RevenueCat key unset). Distinct
 *                  from `failed` because no recipient notification
 *                  was required.
 *   * `failed`   — the call raised. Operator can replay.
 */
export type ThirdPartyOutcome = 'ok' | 'skipped' | 'failed';

export interface ThirdPartyOutcomes {
	strava_deauth: ThirdPartyOutcome;
	garmin_deauth: ThirdPartyOutcome;
	revenuecat_delete: ThirdPartyOutcome;
	fcm_remove: ThirdPartyOutcome;
}

// ─── account-deletion receipt enqueue ───

// normalizeReceiptLocale mirrors the worker's normalizeEmailLocale
// (apps/job_worker/internal/email_i18n.go): map an arbitrary BCP-47-ish
// `user_settings.prefs.locale` to one of the six supported email locales,
// else 'en'. Doing it here keeps a junk pref value out of the job payload;
// the worker normalizes again defensively.
export function normalizeReceiptLocale(tag: unknown): string {
	if (typeof tag !== 'string') return 'en';
	const t = tag.trim().toLowerCase();
	if (t === '') return 'en';
	if (t.startsWith('pt')) return 'pt-BR';
	const base = t.split(/[-_]/)[0];
	switch (base) {
		case 'en':
		case 'de':
		case 'fr':
		case 'es':
		case 'ja':
			return base;
		default:
			return 'en';
	}
}

// accountDeletionReceiptJobPayload builds the `lifecycle_email` job the
// delete-account handler enqueues AFTER the auth-row cascade, carrying the
// address + locale INLINE (the user is gone — the worker can't look the
// address up via GoTrue). Crucially it carries NO `user_id`: the handler's
// job-drain filters on `payload->>user_id`, so a payload without that key is
// naturally exempt and won't be swept by a concurrent re-run. The worker
// dedups on a hash of the address (account_deletion_receipts), not the
// now-gone user id. decisions §121.
export function accountDeletionReceiptJobPayload(
	email: string,
	locale: string,
): { kind: string; payload: Record<string, string> } {
	return {
		kind: 'lifecycle_email',
		payload: {
			template: 'account_deleted',
			email,
			locale: normalizeReceiptLocale(locale),
		},
	};
}
