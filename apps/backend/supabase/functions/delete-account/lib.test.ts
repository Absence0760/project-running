import {
	assert,
	assertEquals,
	assertMatch,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	FCM_BATCH_REMOVE_URL,
	STRAVA_DEAUTHORIZE_URL,
	fcmBatchRemoveBody,
	hashUserIdForAudit,
	revenueCatSubscriberUrl,
} from './lib.ts';

Deno.test('STRAVA_DEAUTHORIZE_URL is the canonical Strava endpoint', () => {
	assertEquals(STRAVA_DEAUTHORIZE_URL, 'https://www.strava.com/oauth/deauthorize');
});

Deno.test('revenueCatSubscriberUrl interpolates the user id', () => {
	const url = revenueCatSubscriberUrl('abc123');
	assertEquals(url, 'https://api.revenuecat.com/v1/subscribers/abc123');
});

Deno.test('revenueCatSubscriberUrl percent-encodes non-URL-safe chars', () => {
	const url = revenueCatSubscriberUrl('user/with spaces?and=ampersands');
	// encodeURIComponent escapes /, space, ?, =, &
	assertMatch(url, /user%2Fwith%20spaces%3Fand%3Dampersands$/);
});

Deno.test('FCM_BATCH_REMOVE_URL is the canonical FCM endpoint', () => {
	assertEquals(FCM_BATCH_REMOVE_URL, 'https://iid.googleapis.com/iid/v1:batchRemove');
});

Deno.test('fcmBatchRemoveBody wraps tokens in registration_tokens', () => {
	const body = fcmBatchRemoveBody(['t1', 't2']);
	assertEquals(JSON.parse(body), { registration_tokens: ['t1', 't2'] });
});

Deno.test('fcmBatchRemoveBody drops empty tokens', () => {
	const body = fcmBatchRemoveBody(['', 'real', '']);
	assertEquals(JSON.parse(body), { registration_tokens: ['real'] });
});

Deno.test('fcmBatchRemoveBody truncates at 1000 tokens', () => {
	const many = Array.from({ length: 1500 }, (_, i) => `t${i}`);
	const body = fcmBatchRemoveBody(many);
	const parsed = JSON.parse(body) as { registration_tokens: string[] };
	assertEquals(parsed.registration_tokens.length, 1000);
});

Deno.test('hashUserIdForAudit returns 64-char hex (SHA-256)', async () => {
	const hex = await hashUserIdForAudit('00000000-0000-0000-0000-000000000001');
	assertEquals(hex.length, 64);
	assertMatch(hex, /^[0-9a-f]{64}$/);
});

Deno.test('hashUserIdForAudit is stable across calls', async () => {
	const a = await hashUserIdForAudit('abc');
	const b = await hashUserIdForAudit('abc');
	assertEquals(a, b);
});

Deno.test('hashUserIdForAudit differentiates inputs', async () => {
	const a = await hashUserIdForAudit('user-a');
	const b = await hashUserIdForAudit('user-b');
	assert(a !== b, 'different inputs must yield different hashes');
});

Deno.test('hashUserIdForAudit honours a custom salt for testability', async () => {
	const defaultHash = await hashUserIdForAudit('user', { salt: 'threkir-deletion-audit-v1' });
	const customHash = await hashUserIdForAudit('user', { salt: 'rotated-salt-v2' });
	assert(defaultHash !== customHash, 'salt change must alter the hash');
});

Deno.test('hashUserIdForAudit matches the deletion_audit_log CHECK regex', async () => {
	// The migration's CHECK is ~ '^[0-9a-f]{64}$' — anything we
	// produce must satisfy it or the INSERT raises 23514.
	const hex = await hashUserIdForAudit('any-user');
	assertMatch(hex, /^[0-9a-f]{64}$/);
});

Deno.test('hashUserIdForAudit flips to HMAC mode when a key is passed', async () => {
	// audit/account-deletion-completeness May 2026 Low closeout. The
	// keyed mode is meaningfully pseudonymous against an adversary who
	// holds the UUID. Unkeyed result must differ from any keyed result
	// (different primitive: SHA-256 vs HMAC-SHA256).
	const unkeyed = await hashUserIdForAudit('user');
	const keyedA = await hashUserIdForAudit('user', { key: 'secret-a-32-bytes-min-yyyyyyyyyy' });
	const keyedB = await hashUserIdForAudit('user', { key: 'secret-b-32-bytes-min-zzzzzzzzzz' });
	assert(unkeyed !== keyedA, 'keyed hash must differ from unkeyed');
	assert(keyedA !== keyedB, 'different keys must produce different hashes');
	assertMatch(keyedA, /^[0-9a-f]{64}$/);
});

Deno.test('hashUserIdForAudit empty-string key falls back to unkeyed mode', async () => {
	// The EF reads Deno.env.get('DELETION_AUDIT_KEY') ?? '' — an unset
	// env var must NOT engage HMAC (a zero-length key would be a
	// reproducible non-secret). Empty string must behave identically
	// to no `key` option at all.
	const empty = await hashUserIdForAudit('user', { key: '' });
	const unset = await hashUserIdForAudit('user');
	assertEquals(empty, unset);
});
