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

Deno.test('handler calls deauthorizeGarmin before admin.deleteUser', () => {
	// Garmin OAuth is deferred (no tokens today → deauthorizeGarmin
	// no-ops to 'skipped'), but the call is wired + ordered like Strava
	// so deletion revokes the grant the moment OAuth lands rather than
	// silently forgetting Garmin (audit-findings 2026-05-30 High).
	// Reason: the integrations row is needed for the token lookup, so it
	// must run before the auth-row cascade — same constraint as Strava.
	const deauth = SRC.indexOf('deauthorizeGarmin(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(
		deauth !== -1,
		'handler must call deauthorizeGarmin so the deletion sweep accounts ' +
			'for Garmin OAuth once it ships (audit/gdpr Art 17)',
	);
	assert(
		deauth < del,
		'deauthorizeGarmin must run BEFORE admin.deleteUser; the integrations ' +
			'row is needed to look up the Garmin access token',
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

Deno.test('handler walks every user-content bucket in the mandatory drain', () => {
	// The avatars bucket is best-effort outside the main try/catch
	// because the bucket doesn't exist yet; the other four drains are
	// mandatory. route-photos + club-photos rows cascade with the auth
	// user, so dropping either bucket from this loop retains the photo
	// bytes forever — the GDPR Art 17 gap audit/storage 2026-07 found.
	assert(
		/for\s+\(const\s+bucket\s+of\s+\['runs',\s*'run-photos',\s*'route-photos',\s*'club-photos'\]\)/
			.test(SRC),
		'handler must iterate runs + run-photos + route-photos + club-photos ' +
			'in the mandatory bucket-drain loop',
	);
	assert(
		/deletePrefix\(adminClient,\s*'avatars'/.test(SRC),
		'handler must also attempt the avatars bucket (best-effort, audit/account-deletion-completeness)',
	);
});

Deno.test('handler writes an audit row on every path that can succeed or fail', () => {
	// Seven recordAudit call sites after the May 2026 closeouts:
	// ok + vault + reports + jobs + segments + storage + auth.
	const matches = SRC.match(/recordAudit\(/g) ?? [];
	assert(
		matches.length >= 7,
		`handler must call recordAudit on every outcome (ok + vault + ` +
			`reports + jobs + segments + storage + auth); found ` +
			`${matches.length} call sites`,
	);
});

Deno.test('handler drains user jobs pre-cascade (audit/account-deletion-completeness High)', () => {
	// jobs.payload->>'user_id' is the user's UUID embedded in a jsonb
	// queue payload. No FK to auth.users — the cascade leaves it
	// behind forever if we don't delete first.
	const drain = SRC.indexOf('drainUserJobs(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(drain !== -1, 'handler must call drainUserJobs');
	assert(drain < del, 'drainUserJobs must run before admin.deleteUser');
});

Deno.test('handler anonymises authored segments pre-cascade (audit/account-deletion-completeness Medium)', () => {
	// segments.author_id FK is `on delete set null`. Without an
	// explicit anonymise, the deleted user's contributed segments
	// survive with their (potentially PII-bearing) names.
	const anon = SRC.indexOf('anonymiseAuthoredSegments(adminClient, user.id)');
	const del = SRC.indexOf('adminClient.auth.admin.deleteUser(user.id)');
	assert(anon !== -1, 'handler must call anonymiseAuthoredSegments');
	assert(anon < del, 'anonymiseAuthoredSegments must run before admin.deleteUser');
});

Deno.test('handler builds a third_party_outcomes record from the best-effort calls', () => {
	// GDPR Art 17(2) evidence trail — each call's outcome must land
	// in deletion_audit_log.third_party_outcomes via recordAudit's
	// fifth argument. garmin_deauth is wired even though Garmin OAuth is
	// deferred (it no-ops to 'skipped' today) so the deletion path can't
	// silently forget Garmin once OAuth lands — audit-findings 2026-05-30.
	const built = /const\s+thirdPartyOutcomes\s*:\s*ThirdPartyOutcomes\s*=\s*\{[^}]*strava_deauth[^}]*garmin_deauth[^}]*revenuecat_delete[^}]*fcm_remove[^}]*\}/m
		.test(SRC);
	assert(
		built,
		'handler must build a ThirdPartyOutcomes record from deauthorizeStrava + ' +
			'deauthorizeGarmin + deleteRevenueCatSubscriber + invalidatePushTokens results',
	);
	// And recordAudit must receive it on every call site. Count the
	// argument uses (`thirdPartyOutcomes` immediately followed by `,` or
	// `)`) rather than matching a specific indentation — the ok-path call
	// is multi-line now that it also threads the deleted-counts note.
	const argUses = SRC.match(/thirdPartyOutcomes[,)]/g) ?? [];
	const callSites = SRC.match(/recordAudit\(/g) ?? [];
	assert(
		argUses.length >= callSites.length - 1,
		`every recordAudit call must thread thirdPartyOutcomes as its final ` +
			`argument; found ${argUses.length} arg uses for ${callSites.length - 1} ` +
			`call sites (one recordAudit match is the function definition)`,
	);
});

Deno.test('handler records per-table deleted-row counts on the ok path', () => {
	// audit/account-deletion-completeness — the bare `ok` result code
	// said nothing about WHAT was erased. The handler now accumulates a
	// deletedCounts map (jobs / rate_limits / reports / segments / the
	// two Storage buckets) and threads it through formatDeletedCounts
	// into the audit row so the Art 5(2) accountability trail is
	// quantitative. A refactor that drops the accumulation would silently
	// regress the evidence trail.
	assert(
		/const\s+deletedCounts\s*:\s*Record<string,\s*number>\s*=\s*\{\}/.test(SRC),
		'handler must declare a deletedCounts accumulator',
	);
	for (const key of [
		'deletedCounts.reports',
		'deletedCounts.jobs',
		'deletedCounts.rate_limits',
		'deletedCounts.segments_anonymised',
	]) {
		assert(
			SRC.includes(`${key} =`),
			`handler must record ${key} after the matching drain succeeds`,
		);
	}
	assert(
		/deletedCounts\[`storage_\$\{bucket\}`\]\s*=\s*await\s+deletePrefix/.test(SRC),
		'handler must record a per-bucket Storage object count from deletePrefix',
	);
	const okAudit = SRC.match(
		/recordAudit\(\s*adminClient,\s*user\.id,\s*'ok',\s*formatDeletedCounts\(deletedCounts\),/m,
	);
	assert(
		okAudit,
		"the ok-path recordAudit must pass formatDeletedCounts(deletedCounts) as its notes argument",
	);
});

Deno.test('count-returning drains request an exact row count', () => {
	// The per-table counts are only meaningful if the delete/update
	// calls actually ask PostgREST for the affected-row count. A
	// refactor that drops `{ count: 'exact' }` would silently report 0
	// for every table.
	for (const helper of ['jobs', 'rate_limits']) {
		assert(
			SRC.includes(`.from('${helper}')`),
			`expected a drain against ${helper}`,
		);
	}
	const exactDeletes = SRC.match(/\.delete\(\{ count: 'exact' \}\)/g) ?? [];
	assert(
		exactDeletes.length >= 3,
		`jobs + rate_limits + reports drains must use .delete({ count: 'exact' }); ` +
			`found ${exactDeletes.length}`,
	);
	assert(
		/\.update\(\s*\{[^}]*\},\s*\{ count: 'exact' \}\s*\)/.test(SRC),
		"segments anonymise must use .update(values, { count: 'exact' }) to report its row count",
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
