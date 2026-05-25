// Source-grep architecture guards for the delete-account handler.
//
// The handler itself is hard to unit test in Deno (it needs a live
// Supabase + the actual auth.users / vault / Storage state). The
// audit/account-deletion-completeness (May 2026) fixes are
// behavioural — third-party cleanups, vault drain, reports
// cleanup, audit log — and would silently regress if a future
// refactor moves them around or drops them. These guards pin the
// call sites in source.
//
// Mirrors the source-grep pattern in apps/watch_wear/.../*WiringTest.kt.

import { assert } from 'https://deno.land/std@0.224.0/assert/mod.ts';

const SRC = await Deno.readTextFile(
	new URL('./index.ts', import.meta.url),
);

Deno.test('handler calls deauthorizeStrava before admin.deleteUser', () => {
	const deauth = SRC.indexOf('deauthorizeStrava(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(
		deauth !== -1,
		'handler must call deauthorizeStrava — otherwise Strava keeps the ' +
			"deleted user's token live (audit/gdpr Art 17)",
	);
	assert(
		del !== -1,
		'handler must call adminClient.auth.admin.deleteUser',
	);
	assert(
		deauth < del,
		'deauthorizeStrava must run BEFORE admin.deleteUser; the integrations ' +
			'row is needed to look up the Strava access token',
	);
});

Deno.test('handler calls deleteRevenueCatSubscriber before admin.deleteUser', () => {
	const rc = SRC.indexOf('deleteRevenueCatSubscriber(user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(rc !== -1, 'handler must call deleteRevenueCatSubscriber');
	assert(
		rc < del,
		'deleteRevenueCatSubscriber must run before admin.deleteUser',
	);
});

Deno.test('handler calls invalidatePushTokens before admin.deleteUser', () => {
	const push = SRC.indexOf('invalidatePushTokens(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(push !== -1, 'handler must call invalidatePushTokens');
	assert(
		push < del,
		'invalidatePushTokens must run before admin.deleteUser — the ' +
			'device_tokens rows cascade away with the auth user',
	);
});

Deno.test('invalidatePushTokens enumerates iOS tokens alongside Android', () => {
	// Reason: audit/account-deletion-completeness (2026-05-25). The
	// pre-fix function filtered .eq('platform', 'android'), missing
	// iOS tokens entirely. The current shape selects token + platform
	// and branches inside the loop so the iOS count is logged and
	// the audit trail can correlate.
	const helperBody = SRC.match(/async function invalidatePushTokens[\s\S]*?\n\}/);
	assert(helperBody, 'invalidatePushTokens must exist in delete-account/index.ts');
	const body = helperBody![0];
	assert(
		!body.includes(".eq('platform', 'android')"),
		'invalidatePushTokens must NOT filter on platform=android — that ' +
			'was the pre-fix shape that silently ignored every iOS token',
	);
	assert(
		body.includes("select('token, platform')"),
		'invalidatePushTokens must read the platform column so iOS tokens ' +
			'are enumerated alongside Android',
	);
});

Deno.test('handler calls cleanupVaultSecrets before admin.deleteUser', () => {
	const vault = SRC.indexOf('cleanupVaultSecrets(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(vault !== -1, 'handler must call cleanupVaultSecrets');
	assert(
		vault < del,
		'cleanupVaultSecrets must run before admin.deleteUser — ' +
			"integrations FK is `on delete set null` so the cascade orphans " +
			'vault.secrets rows otherwise',
	);
});

Deno.test('handler calls deleteUserReports before admin.deleteUser', () => {
	const reports = SRC.indexOf('deleteUserReports(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(reports !== -1, 'handler must call deleteUserReports');
	assert(
		reports < del,
		'deleteUserReports must run before admin.deleteUser — ' +
			"reports.target_id is polymorphic with no FK, so cascade " +
			'leaves the deleted user uuid in place forever otherwise',
	);
});

Deno.test('handler walks both runs + run-photos buckets', () => {
	// The avatars bucket is best-effort outside the main try/catch
	// because the bucket doesn't exist yet; the runs + run-photos
	// drains are mandatory.
	assert(
		/for\s+\(const\s+bucket\s+of\s+\['runs',\s*'run-photos'\]\)/.test(SRC),
		'handler must iterate runs + run-photos in the mandatory bucket-drain loop',
	);
	assert(
		/deletePrefix\(adminClient,\s*'avatars'/.test(SRC),
		'handler must also attempt the avatars bucket (best-effort, audit/account-deletion-completeness)',
	);
});

Deno.test('handler writes an audit row on every path that can succeed or fail', () => {
	// Five recordAudit call sites: success + four failure branches.
	const matches = SRC.match(/recordAudit\(/g) ?? [];
	assert(
		matches.length >= 5,
		`handler must call recordAudit on every outcome ` +
			`(ok + vault_cleanup_failed + reports_cleanup_failed + ` +
			`storage_drain_failed + auth_delete_failed); found ` +
			`${matches.length} call sites`,
	);
});

Deno.test('handler uses the shared lib.ts helpers (no duplicated URL constants)', () => {
	// If the URL constants are inlined here, a future audit pass
	// will silently miss a URL-string change in lib.ts.
	assert(
		!/['"]https:\/\/www\.strava\.com\/oauth\/deauthorize['"]/.test(SRC),
		'handler must use STRAVA_DEAUTHORIZE_URL from ./lib.ts, not an inline string',
	);
	assert(
		!/['"]https:\/\/api\.revenuecat\.com\/v1\/subscribers/.test(SRC),
		'handler must use revenueCatSubscriberUrl() from ./lib.ts',
	);
	assert(
		!/['"]https:\/\/iid\.googleapis\.com/.test(SRC),
		'handler must use FCM_BATCH_REMOVE_URL from ./lib.ts',
	);
});
