// The contract between a CloudFront behaviour and the Lambda behind it.
// The two halves are written in different languages in different
// directories and only these guards read both: which methods arrive and
// which are refused, the body cap on each wrapper, the signature over the
// payload, the header the caller's JWT travels in, and what a refusal may
// say back.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { stripComments } from './core/strip_comments';

const __dirname = dirname(fileURLToPath(import.meta.url));

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('Lambda /api/coach hardcodes bypassPaywallEnabled: false (no env read)', () => {
	// Reason: the SvelteKit `/api/coach/+server.ts` runs in local dev and
	// honours BYPASS_PAYWALL behind a three-condition AND gate (pinned
	// above). The production AWS Lambda wrapper at
	// `apps/web/lambda/coach/src/index.ts` is the only path that runs
	// against a real Supabase project, and it MUST hardcode the flag to
	// `false` regardless of any env var. A subtle regression — switching
	// to `process.env.BYPASS_PAYWALL === 'true'` to "match the SvelteKit
	// gate" — would let a stray Lambda env var unlock the daily cap for
	// every free user in production. The three-condition AND gate in the
	// SvelteKit handler is irrelevant in Lambda because the conditions
	// don't apply (Lambda is `NODE_ENV=production`, points at a real
	// Supabase URL), but the right defence is to never read the env at
	// all in the Lambda path.
	const source = read('lambda/coach/src/index.ts');
	const cfgMatch = source.match(/bypassPaywallEnabled\s*:\s*([^,\n]+)/);
	assert.ok(
		cfgMatch,
		'Could not locate bypassPaywallEnabled in lambda/coach/src/index.ts CoachConfig — has the field been renamed?',
	);
	const value = cfgMatch![1].trim();
	assert.strictEqual(
		value,
		'false',
		`Lambda CoachConfig.bypassPaywallEnabled must be the literal "false", was "${value}". ` +
			'Reading process.env or a runtime flag here lets a stray Lambda env var unlock the paywall for every prod user.',
	);
	// Belt-and-braces: no `process.env.BYPASS_PAYWALL` anywhere in the
	// Lambda source, even off the config object.
	assert.doesNotMatch(
		source,
		/process\.env\.[A-Z_]*BYPASS_PAYWALL/,
		'Lambda must not reference process.env.BYPASS_PAYWALL (or PUBLIC_BYPASS_PAYWALL) at all — there is no dev-mode condition that would safely guard it in a Lambda runtime.',
	);
});

test('RouteBuilder sends the generate JWT in `x-supabase-authorization`, not `Authorization`', () => {
	// Reason: same collision as the coach clients — the production Lambda
	// Function URL is AWS_IAM-auth and CloudFront's OAC signs `Authorization`
	// via sigv4, so the viewer JWT must ride the custom header. Server-side
	// generation is a Pro perk (decisions §204); putting the JWT in
	// Authorization would 403 at the origin and silently downgrade every Pro
	// user to the in-browser heuristic with no local-dev signal (dev reads
	// the same custom header).
	const source = read('src/lib/components/RouteBuilder.svelte');
	const generateFetch = source.match(/fetch\('\/api\/routes\/generate'[\s\S]*?\}\);/);
	assert.ok(generateFetch, 'Could not locate the /api/routes/generate fetch in RouteBuilder.');
	assert.match(
		generateFetch![0],
		/['"]X-Supabase-Authorization['"]/,
		'RouteBuilder must send the user JWT in the x-supabase-authorization header.',
	);
	assert.doesNotMatch(
		generateFetch![0],
		/['"]Authorization['"]:/,
		'RouteBuilder must not put the viewer JWT in Authorization — CloudFront OAC owns that header.',
	);
});

test('every web POST through a CloudFront Lambda behavior sends the sigv4 payload hash', () => {
	// Reason: OAC-signed Lambda Function URLs reject unsigned payloads and
	// CloudFront cannot hash a body it streams through, so the CLIENT must
	// send `x-amz-content-sha256` on any request that carries a body —
	// without it every POST 403s at the origin and the SPA error fallback
	// masks the failure as a 200 shell (issue #590 defect 3). GET surfaces
	// (share/OG, osrm-proxy) carry no body and are exempt.
	for (const path of [
		'src/lib/components/CoachChat.svelte',
		'src/lib/components/RouteBuilder.svelte',
		'src/lib/routes/route_describe_client.ts',
		'src/lib/routes/route_request_client.ts',
	]) {
		const source = read(path);
		assert.match(
			source,
			/['"]x-amz-content-sha256['"]/,
			`${path} POSTs through a CloudFront Lambda behavior and must send x-amz-content-sha256 (payloadSha256Hex over the exact body).`,
		);
		assert.match(
			source,
			/payloadSha256Hex/,
			`${path} must compute the payload hash via payloadSha256Hex so the digest always matches the posted bytes.`,
		);
	}
});

test('mobile POST seams to the CloudFront Lambda behaviors send the sigv4 payload hash', () => {
	// Reason: same OAC unsigned-payload rejection as the web seams — the
	// mobile clients POST to https://threkir.com/api/coach* through the
	// same distribution, so they need the same header (issue #590).
	for (const path of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
		'../mobile_android/lib/route_describe_client.dart',
		'../mobile_ios/lib/route_describe_client.dart',
	]) {
		const source = read(path);
		assert.match(
			source,
			/['"]x-amz-content-sha256['"]/,
			`${path} POSTs through a CloudFront Lambda behavior and must send x-amz-content-sha256.`,
		);
	}
});

test('Mobile coach screen sends `x-supabase-authorization`, not `Authorization`', () => {
	// Reason: production Lambda's Function URL is AWS_IAM-auth — CloudFront
	// signs `Authorization` via sigv4, so forwarding the viewer JWT in
	// that slot collides with the signature. The pass-2 fix (commit
	// 46ea5b5) flipped the mobile client to send `x-supabase-authorization`
	// matching the dev SvelteKit endpoint. Pinned because reverting to
	// `Authorization` fails for every production user with no local-dev
	// signal.
	for (const path of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const source = read(path);
		assert.match(
			source,
			/['"]x-supabase-authorization['"]/,
			`${path} must send the user JWT in the x-supabase-authorization header — production Lambda OAC signs Authorization.`,
		);
	}
});

test('every two-wrapper endpoint enforces one shared body cap, on both wrappers', () => {
	// Reason: pass-2 commit a2ea656 added COACH_BODY_LIMIT_BYTES to both
	// wrappers of /api/coach — the SvelteKit dev +server.ts and the production
	// Lambda. audit/auth (May 2026) then found the Lambda checking
	// `bodyStr.length` (UTF-16 code units) while the cap was in bytes, letting
	// a multi-byte payload ~3x the cap through. The two wrappers had diverged
	// because each owned its own copy of the check.
	//
	// The fix put one constant and one helper in $lib/coach/body.ts — but the
	// guard that pinned it named only the coach PATH, so the same shape sat
	// untouched one endpoint over for as long: /api/routes/generate spelled a
	// 4 KB cap twice and re-implemented the decode, and the coach's own two
	// sub-paths spelled theirs as a named constant in the dev wrapper and a
	// bare literal in the Lambda (decisions § 968).
	//
	// Derived, not listed: any wrapper that caps a body must IMPORT the cap and
	// call the shared helper, so a new endpoint inlining its own fails here
	// without anyone remembering to register it.
	const body = read('src/lib/coach/body.ts');
	assert.match(
		body,
		/COACH_BODY_LIMIT_BYTES\s*=\s*256\s*\*\s*1024/,
		'$lib/coach/body.ts must declare COACH_BODY_LIMIT_BYTES = 256 * 1024.',
	);

	const wrappers: string[] = [];
	function collect(dir: string, match: (name: string) => boolean): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const full = resolve(dir, entry.name);
			if (entry.isDirectory()) collect(full, match);
			else if (match(entry.name)) wrappers.push(full);
		}
	}
	collect(resolve(__dirname, '..', 'routes', 'api'), (n) => n === '+server.ts');
	collect(resolve(__dirname, '..', '..', 'lambda'), (n) => n === 'index.ts');

	// Population: a walker that found nothing would satisfy every assertion
	// below while proving nothing (decisions § 534).
	assert.ok(
		wrappers.length >= 8,
		`found only ${wrappers.length} endpoint wrappers — walker broken?`,
	);

	const offenders: string[] = [];
	let capped = 0;
	for (const file of wrappers) {
		const rel = file.slice(file.indexOf('apps/web/') + 'apps/web/'.length);
		const src = stripComments(readFileSync(file, 'utf-8'));
		if (!/BODY_LIMIT_BYTES/.test(src)) continue;
		capped++;

		if (/^\s*const\s+\w*BODY_LIMIT_BYTES\s*=/m.test(src)) {
			offenders.push(`${rel}: declares its own cap instead of importing one`);
		}
		if (!/import\s*\{[^}]*BODY_LIMIT_BYTES[^}]*\}/s.test(src)) {
			offenders.push(`${rel}: does not import the cap it enforces`);
		}
		if (!/(decodeLambdaBody|checkBodyByteLimit)\s*\(/.test(src)) {
			offenders.push(
				`${rel}: hand-rolls the size check — call decodeLambdaBody (Lambda) or ` +
					'checkBodyByteLimit (SvelteKit), which count bytes',
			);
		}
		if (/\d+\s*\*\s*1024/.test(src)) {
			offenders.push(`${rel}: spells a byte cap inline — import it instead`);
		}
	}

	assert.ok(capped >= 5, `only ${capped} wrappers enforce a body cap — walker broken?`);
	assert.deepEqual(
		offenders.sort(),
		[],
		'these re-decide a body cap the shared module already owns. One copy per ' +
			'wrapper is what let the coach pair drift on UTF-16 code units vs bytes.',
	);
});

test('Coach 401 / 503 error responses don\'t leak provider / GoTrue internals', () => {
	// Reason: pass-2 commits 2d2a24a + a2ea656 stripped operator hints
	// from the user-visible 401 / 503 messages. The 503 used to echo
	// the raw COACH_PROVIDER env-var name to any unauthenticated
	// caller; the 401 used to return GoTrue's error string which can
	// carry JWT-shape details an attacker can use as a probe oracle.
	// Both are now generic on the wire and verbose only in
	// console.error / CloudWatch.
	const handler = read('src/lib/coach/handler.ts');
	// 503: must NOT contain a string-template that interpolates the
	// provider name into the user-facing error.
	assert.doesNotMatch(
		handler,
		/jsonError\(503,\s*[`'"][^'"`]*\$\{[^}]*provider[^}]*\}/,
		'503 user-facing message must not interpolate the provider value (operator hint goes to console.error).',
	);
	// 401: the user-facing string must be the static "not
	// authenticated" — no GoTrue error spread into the body.
	assert.match(
		handler,
		/jsonError\(401,\s*['"]not authenticated['"]\s*\)/,
		'401 must return the static "not authenticated" — pass-2 commit a2ea656 closed the GoTrue oracle.',
	);
	// 502 + the mid-stream SSE error: neither may put the caught provider
	// error's `.message` on the wire. On the Anthropic path that string is
	// the upstream status envelope (model id, error taxonomy, and the
	// `messages.N` index that counts the turns we inject ahead of the
	// caller's); on the OpenAI-compatible path `humaniseUpstreamError` falls
	// back to the raw upstream response body.
	assert.doesNotMatch(
		handler,
		/jsonError\(502,\s*msg\s*\)/,
		'the 502 must not echo the provider error message — log it, return a static string.',
	);
	assert.doesNotMatch(
		handler,
		/sendEvent\('error',\s*\{\s*message/,
		'the mid-stream SSE error event must not carry the provider error message.',
	);
});

test('Coach pre-handshake daily-limit placeholder matches the server free cap', () => {
	// Reason: pass-2 commit a2ea656 fixed a drift where the web placeholder
	// said "10 of 10 remaining" while the server returned "5". The
	// placeholder matters because users see it for the half-second
	// before the SSE meta event lands. Pinned so a future tier change
	// (5→8) updates both surfaces in lockstep with the server.
	// Source of truth: TIER_LIMITS.free.dailyLimit in coach/types.ts.
	const types = read('src/lib/coach/types.ts');
	const tierMatch = types.match(/free:\s*\{[^}]*dailyLimit:\s*(\d+)/);
	assert.ok(tierMatch, 'Could not extract TIER_LIMITS.free.dailyLimit from coach/types.ts.');
	const serverCap = tierMatch![1];
	// Source-of-truth check: the value MUST be a positive small
	// integer (sanity guard; drifting to "0" or "10000" would be a
	// product mistake worth catching). The exact value (2 today,
	// reduced from 5 in commit 144d2a9 as a cost-control measure) is
	// not pinned here — the cross-checks below verify the placeholder
	// matches whatever the server says. The literal-value pin used to
	// be `=== '5'`; replaced after audit:cost-controls + the
	// 144d2a9 product change drifted past it without updating the
	// test. The lockstep-with-server property is what actually matters.
	assert.match(
		serverCap,
		/^[1-9]\d{0,2}$/,
		`TIER_LIMITS.free.dailyLimit should be a small positive integer (1–999), was "${serverCap}".`,
	);
	// Web placeholder. The current shape reads
	// `TIER_LIMITS.free.dailyLimit` directly from the imported source-
	// of-truth, which is structurally better than the old local
	// `DEFAULT_DAILY_LIMIT` constant — a server-cap change updates
	// both at once because the placeholder IS the server cap. Pin the
	// import path instead of a literal value.
	const chat = read('src/lib/components/CoachChat.svelte');
	assert.match(
		chat,
		/TIER_LIMITS\.free\.dailyLimit/,
		'CoachChat.svelte must use TIER_LIMITS.free.dailyLimit as the pre-handshake placeholder so the placeholder updates in lockstep with the server cap.',
	);
	// Mobile placeholder, both Dart twins. Same shape pin — the
	// `_freeDailyLimit` local constant must be the literal value
	// (Dart can't import from TS), so cross-check it against the
	// server cap extracted above.
	for (const p of [
		'../mobile_android/lib/screens/coach_screen.dart',
		'../mobile_ios/lib/screens/coach_screen.dart',
	]) {
		const dart = read(p);
		assert.match(
			dart,
			new RegExp(`_freeDailyLimit\\s*=\\s*${serverCap}\\b`),
			`${p} _freeDailyLimit must equal the server cap (${serverCap}). ` +
				'If the server tier was changed in coach/types.ts, mirror it here.',
		);
	}
});

test('every production Lambda gates its own HTTP method', () => {
	// Reason: each of the eight handlers is reached by a CloudFront behaviour
	// whose `allowed_methods` is the only other thing deciding what arrives, and
	// the two are written in different languages in different directories. All
	// eight gate today and each one's gate is driven behaviourally by its own
	// suite — but by five different files, with nothing naming the class. A
	// ninth Lambda added without a gate would be caught by none of them, which
	// is how the five share handlers went without one until § 1005: their
	// safety sat entirely in the Terraform list § 972 finally asserted.
	//
	// Source-level rather than behavioural because the shapes do not generalise:
	// the coach wrapper writes to a response STREAM and cannot be driven through
	// the same envelope as its siblings. All eight now share the REFUSAL itself
	// (`core/method_gate`, decisions § 1035) — the stream caller passes its
	// parts to `HttpResponseStream.from` — but a ninth handler could still
	// spell its own, so both shapes stay accepted here.
	const dir = resolve(__dirname, '..', '..', 'lambda');
	const handlers = readdirSync(dir, { withFileTypes: true })
		.filter((e) => e.isDirectory())
		.map((e) => `${e.name}/src/index.ts`)
		.filter((rel) => existsSync(resolve(dir, rel)));

	// Population: a walker that found nothing would satisfy the assertion below
	// while proving nothing (decisions § 534).
	assert.ok(handlers.length >= 8, `found only ${handlers.length} Lambda handlers — walker broken?`);

	// Either the handler spells its own comparison and the 405 it answers with,
	// or it delegates to the shared refusal (directly, or through the share
	// surface's own instantiation of it).
	const OWN_GATE = /requestContext\??\.http\??\.method\s*!==/;
	const SHARED_GATE = /\b(share)?[Mm]ethodRefusal\(/;

	const ungated = handlers.filter((rel) => {
		const src = stripComments(readFileSync(resolve(dir, rel), 'utf-8'));
		if (SHARED_GATE.test(src)) return false;
		return !(OWN_GATE.test(src) && /\b405\b/.test(src));
	});

	assert.deepEqual(
		ungated.sort(),
		[],
		'these Lambda handlers do work on any method their CloudFront behaviour ' +
			'lets through. Call `methodRefusal` from $lib/core/method_gate with the ' +
			'set this handler allows — it carries the `Allow` header RFC 9110 15.5.6 ' +
			'requires and the `no-store` a refusal needs.',
	);
});
