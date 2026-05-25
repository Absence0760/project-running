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
 * Salted SHA-256 hash of the user id, written to deletion_audit_log
 * so the table isn't itself a directory of deleted accounts. The
 * salt is fixed (the table is service-role only; a salt that
 * rotates would prevent operators from looking up a known user's
 * row when investigating a delete-request fulfilment). Hex output.
 */
export async function hashUserIdForAudit(
	userId: string,
	salt: string = 'threkir-deletion-audit-v1',
): Promise<string> {
	const data = new TextEncoder().encode(`${salt}:${userId}`);
	const digest = await crypto.subtle.digest('SHA-256', data);
	const bytes = new Uint8Array(digest);
	let hex = '';
	for (const b of bytes) hex += b.toString(16).padStart(2, '0');
	return hex;
}

// ─── result codes (mirror the deletion_audit_log CHECK) ───

export type DeletionAuditResult =
	| 'ok'
	| 'storage_drain_failed'
	| 'auth_delete_failed'
	| 'reports_cleanup_failed'
	| 'vault_cleanup_failed';
