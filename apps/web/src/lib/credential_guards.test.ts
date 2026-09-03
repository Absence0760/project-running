// Where a secret comes from, who may decrypt it, and what a handler does
// when it is absent. A credential read from source is not a credential; a
// handler that proceeds without one is worse than one that refuses.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('KMS Decrypt principal ARN matches the Lambda role name', () => {
	// Reason: the kms_secrets policy in infra/modules/web-stack/main.tf
	// builds the Lambda role ARN as a deterministic string
	// (`${prefix}-coach-lambda`) instead of referencing aws_iam_role.lambda
	// — the reference would create a key→role→key cycle. Audit pass 3
	// caught a regression where the policy said `-lambda` but the actual
	// role is named `-coach-lambda`, leaving the running Lambda unable
	// to decrypt secrets at cold-start. Pin the suffix on both sides so
	// a future rename of the role forces a deliberate edit on the
	// policy too.
	const source = read('../../infra/modules/web-stack/main.tf');
	const policySuffixMatch = source.match(
		/identifiers\s*=\s*compact\(\[[\s\S]*?role\/\$\{local\.resource_prefix\}-([a-z0-9-]+)/m,
	);
	assert.ok(
		policySuffixMatch,
		'Could not extract the role-name suffix from the kms_secrets policy in infra/modules/web-stack/main.tf — has the AllowLambdaAndDeployRolesToDecrypt statement moved?',
	);
	const policySuffix = policySuffixMatch![1];
	const roleNameMatch = source.match(
		/resource\s+"aws_iam_role"\s+"lambda"\s*\{[\s\S]*?name\s*=\s*"\$\{local\.resource_prefix\}-([a-z0-9-]+)"/m,
	);
	assert.ok(
		roleNameMatch,
		'Could not extract the Lambda role name from infra/modules/web-stack/main.tf — has aws_iam_role.lambda moved?',
	);
	const roleSuffix = roleNameMatch![1];
	assert.equal(
		policySuffix,
		roleSuffix,
		`KMS policy ARN suffix (${policySuffix}) must match aws_iam_role.lambda name suffix (${roleSuffix}). A mismatch leaves the Lambda unable to call kms:Decrypt at cold-start. See infra/modules/web-stack/main.tf and the audit-pass-3 commit ${'8424dec'}.`,
	);
});

test('refresh-tokens fails closed (503) when CRON_SECRET env is absent', () => {
	// Reason: the function returns 503 `cron_not_configured` when
	// `Deno.env.get('CRON_SECRET')` is null — i.e. a misconfigured
	// production deployment refuses to do any work rather than
	// proceeding with "no auth check at all." The 403 path
	// (wrong/missing bearer with the env var present) is covered by
	// integration tests in handler_envelope.test.ts; the 503 branch
	// is a config-state property best pinned at the source level.
	//
	// The rollback path matters even more: refresh-tokens is the
	// deprecated-but-kept rollback for the Go service per
	// apps/backend/CLAUDE.md. If a future edit dropped the 503 guard
	// and just fell through to `auth.startsWith('Bearer ')` against an
	// undefined secret, an unauthenticated POST could trigger the
	// integrations loop with no auth (which is the exact bug that
	// commit b3373c6 originally closed).
	const source = read('../backend/supabase/functions/refresh-tokens/index.ts');
	// 1. Reads CRON_SECRET via Deno.env.get.
	assert.match(
		source,
		/Deno\.env\.get\(['"]CRON_SECRET['"]\)/,
		'refresh-tokens must read CRON_SECRET from env.',
	);
	// 2. Has an explicit fail-closed branch returning 503 when the
	//    env var is missing — before the bearer check.
	assert.match(
		source,
		/if\s*\(\s*!\s*cronSecret\s*\)\s*\{[\s\S]*?status:\s*503/,
		'refresh-tokens must return 503 fail-closed when CRON_SECRET is unset, BEFORE the bearer check. ' +
			'Falling through with an undefined secret would let an unauthenticated POST proceed.',
	);
	// 3. Drains the request body BEFORE the auth check (the body-
	//    drain commit e56cd48). A regression that removed
	//    discardBody() re-opens the slow-loris DoS window.
	const bodyDrainIdx = source.indexOf('discardBody(req)');
	const cronCheckIdx = source.search(/Deno\.env\.get\(['"]CRON_SECRET['"]\)/);
	assert.notStrictEqual(bodyDrainIdx, -1,
		'refresh-tokens must call discardBody(req) — the body-drain helper from _shared/body_limit.ts.');
	assert.ok(
		bodyDrainIdx < cronCheckIdx,
		'discardBody(req) must come BEFORE the CRON_SECRET env read — otherwise a chunked-body POST holds the connection open until the runtime timeout even on the auth-reject path.',
	);
});

test('refresh-tokens refuses a CRON_SECRET too short to be one, and CI supplies one that clears the floor', () => {
	// Reason: refresh-tokens is `verify_jwt = false`, so the bearer is the
	// only thing in front of a loop over the whole `integrations` table
	// against Strava's OAuth endpoint. `timingSafeEqual` closes the per-byte
	// channel; it does nothing about a secret short enough to guess offline,
	// and the case that actually happens is a misconfigured deploy
	// (`CRON_SECRET=test`). strava-webhook — same posture, same gate class —
	// has carried a 32-char floor since the May 2026 audit; this one had none.
	//
	// The second assertion is the point of pinning this at the source level
	// rather than only in the function. The floor could not land while
	// ci.yml set a 15-character CRON_SECRET for the served-envelope lane,
	// and the tempting fix is to lower the floor to fit the fixture — which
	// is not a floor. So the fixture is read here too: if someone shortens
	// it back, this fails rather than the authorized leg of the envelope
	// suite quietly starting to 503.
	const source = read('../backend/supabase/functions/refresh-tokens/index.ts');
	assert.match(
		source,
		/cronSecret\.length\s*<\s*32/,
		'refresh-tokens must refuse a CRON_SECRET shorter than 32 characters, matching strava-webhook.',
	);
	const floorIdx = source.search(/cronSecret\.length\s*<\s*32/);
	// The CALL, not the import — `timingSafeEqual` appears at the top of the
	// file as a named import, so a bare indexOf finds line 1 and this
	// ordering check can never fail.
	const compareIdx = source.search(/timingSafeEqual\s*\(/);
	assert.ok(
		floorIdx !== -1 && compareIdx !== -1 && floorIdx < compareIdx,
		'The length floor must come BEFORE the timing-safe compare — a floor checked after the compare has already spent the work it exists to refuse.',
	);

	const webhook = read('../backend/supabase/functions/strava-webhook/index.ts');
	assert.match(
		webhook,
		/webhookSecret\.length\s*<\s*32/,
		'strava-webhook must keep its own 32-char floor — the two are deliberately symmetric.',
	);

	const workflow = read('../../.github/workflows/ci.yml');
	const m = workflow.match(/CRON_SECRET=(\S+)/);
	assert.ok(m, 'ci.yml must set a CRON_SECRET for the served-envelope lane.');
	assert.ok(
		m[1].length >= 32,
		`ci.yml's CRON_SECRET is ${m[1].length} characters and the function refuses anything under 32, so the envelope lane would exercise only the 503 branch. Lengthen the fixture; do not lower the floor.`,
	);
});

test('revenuecat-webhook verifies HMAC before constructing the Supabase client', () => {
	// Reason: the webhook is the ONLY legitimate writer of
	// user_profiles.subscription_tier (the lock_subscription_columns
	// trigger from migration 20260624_001 rejects writes from anything
	// other than the service_role). If a refactor reordered the function
	// to construct the service-role `createClient` before the HMAC
	// verify, an attacker who knows the webhook URL could forge a Pro
	// upgrade by POSTing a valid-looking event body with no signature —
	// the client would be alive and ready to write the moment the
	// request handler crossed the (now-out-of-order) HMAC check.
	// Pinning the call order keeps the privilege boundary obvious.
	const source = read('../backend/supabase/functions/revenuecat-webhook/index.ts');
	const lines = source.split('\n');
	const tseqLine = lines.findIndex((l) => /timingSafeEqual\s*\(/.test(l));
	// The optional type argument is not cosmetic: every Edge Function client
	// is `createClient<Database>(...)` since decisions § 762, and a pattern
	// that only matched the bare call stopped locating it at all — this guard
	// failed loudly on that, which is the behaviour the `!== -1` assert below
	// exists to produce, but a narrower ordering guard could have gone quiet.
	const createLine = lines.findIndex((l) => /createClient\s*(?:<[^>]*>)?\s*\(/.test(l));
	assert.notStrictEqual(
		tseqLine,
		-1,
		'Could not locate timingSafeEqual call in revenuecat-webhook/index.ts — has the HMAC check been removed or renamed?',
	);
	assert.notStrictEqual(
		createLine,
		-1,
		'Could not locate createClient call in revenuecat-webhook/index.ts.',
	);
	assert.ok(
		tseqLine < createLine,
		`HMAC timingSafeEqual (line ${tseqLine + 1}) must appear before createClient (line ${createLine + 1}) — ` +
			'a service-role client constructed before HMAC verification opens a forge-Pro-upgrade window via the webhook URL.',
	);
});

test('Watch clients carry no hardcoded SUPABASE_ANON_KEY default', () => {
	// Reason: pass-2 hardening (commit 51046c2) cleared the local-stack
	// publishable key out of both watch fallbacks. The literal still
	// lives in git history, so a reverted "convenience default" lets
	// an unprovisioned debug build silently authenticate against
	// whichever stack the literal pointed at — including production
	// after the value rotates. Empty defaults fail the network call
	// loudly, which is the desired behaviour for a misconfigured build.
	//
	// Wear OS: build.gradle.kts must default SUPABASE_ANON_KEY to "".
	// watchOS: SupabaseService.swift's `private var anonKey` must
	// default to "".
	const wearGradle = read('../watch_wear/android/app/build.gradle.kts');
	assert.match(
		wearGradle,
		/SUPABASE_ANON_KEY['"\s)]+as\s+String\?\)\s*\n?\s*\?\:\s*""/,
		'Wear OS build.gradle.kts must default SUPABASE_ANON_KEY to "" — see audit pass-2 commit 51046c2.',
	);
	// And no JWT-shaped literal anywhere in the file (catches a
	// drive-by paste that re-introduces the hardcoded key).
	assert.doesNotMatch(
		wearGradle,
		/eyJ[A-Za-z0-9_-]{20,}/,
		'Wear OS build.gradle.kts must not contain any JWT-shaped literal — that pattern is a hardcoded supabase anon key.',
	);
	const watchSwift = read('../watch_ios/WatchApp/SupabaseService.swift');
	assert.match(
		watchSwift,
		/private\s+var\s+anonKey\s*=\s*""/,
		'watchOS SupabaseService.swift must default `anonKey` to "" — see audit pass-2 commit 51046c2.',
	);
	assert.doesNotMatch(
		watchSwift,
		/eyJ[A-Za-z0-9_-]{20,}/,
		'watchOS SupabaseService.swift must not contain any JWT-shaped literal — that pattern is a hardcoded supabase anon key.',
	);
});

test('the three sops operator scripts agree on the estate path and the placeholder token', () => {
	const sopsInit = read('../../bin/sops-init.sh');
	const secretSet = read('../../bin/secret-set.sh');
	const keyRotate = read('../../bin/key-rotate.sh');

	const slugs = new Map<string, string>();
	for (const [name, src] of [
		['sops-init.sh', sopsInit],
		['secret-set.sh', secretSet],
		['key-rotate.sh', keyRotate],
	] as const) {
		const slug = src.match(/^PROJECT_SLUG="([a-z0-9-]+)"$/m)?.[1];
		assert.ok(slug, `${name} declares no PROJECT_SLUG — it addresses the estate repo by hand.`);
		slugs.set(name, slug!);
		assert.match(
			src,
			/\$INFRA_SECRETS_DIR\/\$PROJECT_SLUG\//,
			`${name} must build the estate path from $PROJECT_SLUG, not spell the subdirectory out.`,
		);
	}
	assert.equal(
		new Set(slugs.values()).size,
		1,
		`the scripts disagree about the estate subdirectory: ${[...slugs].map(([k, v]) => `${k}=${v}`).join(', ')}`,
	);
	const slug = [...slugs.values()][0];

	// What sops-init.sh actually writes into the estate config, per env.
	const written = new Map<string, string>();
	for (const m of sopsInit.matchAll(/^\s*([a-z]+]?)\)\s*echo "([A-Z0-9_]+)"\s*;;/gm)) {
		written.set(m[1].replace(/\]$/, ''), m[2]);
	}
	assert.ok(
		written.size >= 2,
		`read only ${written.size} placeholder token(s) out of sops-init.sh — parser broken?`,
	);

	// What key-rotate.sh derives. The derivation is required to be a derivation
	// rather than a literal, so a third env cannot be added to one script alone.
	assert.match(
		keyRotate,
		/placeholder="KMS_\$\(echo "\$\{PROJECT_SLUG\}_\$\{ENV_NAME\}" \| tr '\[:lower:\]-' '\[:upper:\]_'\)_ARN_PLACEHOLDER"/,
		'key-rotate.sh must derive the placeholder token from the slug and the env, ' +
			'the way sops-init.sh names it — a literal here is how the two came apart.',
	);
	for (const [env, token] of written) {
		const derived = `KMS_${slug}_${env}`.toUpperCase().replace(/-/g, '_') + '_ARN_PLACEHOLDER';
		assert.equal(
			derived,
			token,
			`key-rotate.sh would look for ${derived} where sops-init.sh writes ${token} for ${env}.`,
		);
	}

	// The rule it reads back must be the one naming this file, not a path from
	// a layout that no longer exists.
	assert.match(
		keyRotate,
		/rule_anchor="\$PROJECT_SLUG\/\$ENV_NAME"/,
		'key-rotate.sh must anchor on the estate rule for its own file.',
	);
	for (const stale of ['preview/secrets', 'prod/secrets', 'REPLACE_PROD_KMS_ARN']) {
		assert.ok(
			!keyRotate.includes(stale),
			`key-rotate.sh still refers to ${stale}, which no estate config contains.`,
		);
	}
});
