// Every spend-bearing or abuse-bearing write is bucketed, and every refusal
// reaches the caller as a sentence rather than as a raw P0001.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));

function read(...parts: string[]): string {
	return readFileSync(resolve(...parts), 'utf-8');
}

test('clip-public-track rate-limit calls fail closed on RPC error', () => {
	// Reason: pass-3 commit d10deeb flipped both buckets (per-user and
	// per-IP-anon) to failClosed: true. The anon path is the abuse
	// surface — a transient DB blip on the rate-limit RPC must not
	// remove the only IP-level guard. fail-open here would let an
	// attacker bypass the cap during any DB hiccup.
	const ef = read('../backend/supabase/functions/clip-public-track/index.ts');
	// Find every checkRateLimit call and assert each carries
	// failClosed: true. Use a regex that captures the option block.
	const calls = [...ef.matchAll(/checkRateLimit\([\s\S]*?\)/g)];
	assert.ok(
		calls.length >= 2,
		'Expected at least two checkRateLimit calls in clip-public-track (per-user + anon).',
	);
	for (const m of calls) {
		assert.match(
			m[0],
			/failClosed:\s*true/,
			'Every checkRateLimit call in clip-public-track must pass failClosed: true — pass-3 commit d10deeb.',
		);
	}
});

test('createClub + saveRoute + submitReport + createChallenge all translate P0001 via the shared helper', () => {
	// Reason: every P0001 rate-limit bucket on the web client must route
	// through `rateLimitErrorMessage` so users see a "wait N minutes" line
	// instead of the raw `rate limit exceeded for <bucket>, retry in Ns`
	// postgres exception. Previously each call-site carried its own ad-hoc
	// translation (e.g. submitReport's old "Too many reports — please wait
	// a few minutes"); centralising the rule means a future bucket lands
	// in one place + behaves identically across clubs / routes / reports.
	// Since decisions § 744 the wording lives in the catalogue, so the
	// helper is the i18n one and the localizer is passed in — a call that
	// dropped `m` would compile against a stray Translate and hand a
	// non-English reader English. Twin path on Dart is enforced by
	// mobile_android's architecture-guard suite.
	const source = read('src/lib/core/data.ts');
	assert.match(
		source,
		/import\s+\{\s*rateLimitErrorMessage\s*\}\s+from\s+['"]\.\.\/i18n\/rate_limit_message['"]/,
		'data.ts must import rateLimitErrorMessage from ../i18n/rate_limit_message.',
	);
	assert.match(
		source,
		/import\s+\{\s*m\s*\}\s+from\s+['"]\.\.\/i18n\/store\.svelte['"]/,
		'data.ts must import the message lookup `m` — it is the localizer every rate-limit sentence is resolved through.',
	);
	// Slice each function body and assert the helper appears with the
	// "throw new Error(friendly)" follow-up. Using the same bodyAfter
	// landmark approach as the public-runs test above so a nested type
	// literal can't trip a naive `^}` regex.
	function bodyAfter(needle: string, until: string): string {
		const start = source.indexOf(needle);
		assert.ok(start >= 0, `Could not locate '${needle}' — rename?`);
		const end = source.indexOf(until, start + needle.length);
		assert.ok(
			end > start,
			`Could not locate landmark '${until}' after '${needle}'`,
		);
		return source.slice(start, end);
	}
	const saveRouteBody = bodyAfter(
		'export async function saveRoute(',
		'export async function deleteRoute(',
	);
	const createClubBody = bodyAfter(
		'export async function createClub(',
		'function genToken(',
	);
	const submitReportBody = bodyAfter(
		'export async function submitReport(',
		// submitReport returns `data as string` and ends — the next
		// landmark after the function is the closing semicolon's newline.
		// Anchor on the helper's RETURN statement so the slice is bounded.
		'return data as string;',
	);
	const createChallengeBody = bodyAfter(
		'export async function createChallenge(',
		'return challengeFromRow(data);',
	);
	for (const [name, body] of [
		['saveRoute', saveRouteBody],
		['createClub', createClubBody],
		['submitReport', submitReportBody],
		['createChallenge', createChallengeBody],
	] as const) {
		assert.match(
			body,
			/rateLimitErrorMessage\(m,/,
			`${name} must call rateLimitErrorMessage(m, …) — every P0001 bucket goes through the shared helper, with the localizer passed in.`,
		);
		assert.match(
			body,
			/if\s*\(friendly\)\s*throw\s+new\s+Error\(friendly\)/,
			`${name} must throw the friendly string when the helper recognises the bucket. Skipping the throw drops back to the raw postgres exception.`,
		);
	}
});

test('template-clone / publish RPC wrappers translate P0001 via the shared helper', () => {
	// Reason: the clone_plan_template / clone_public_plan /
	// clone_session_template / clone_gym_routine_template /
	// publish_gym_routine_as_template RPCs all raise the same
	// enforce_create_rate_limit P0001 exception as create_club /
	// create_route. Their data.ts wrappers used to `if (error) throw
	// error` the raw postgres string straight into the caller's toast
	// (e.g. plans/new, plans/library, clubs/[slug] adopt). Pin that
	// each wrapper now routes the error through rateLimitErrorMessage +
	// re-throws the friendly string, matching createClub / saveRoute /
	// submitReport above.
	const source = read('src/lib/core/data.ts');
	function bodyOf(needle: string): string {
		const start = source.indexOf(needle);
		assert.ok(start >= 0, `Could not locate '${needle}' — rename?`);
		const end = source.indexOf('return data as string;', start + needle.length);
		assert.ok(end > start, `Could not locate the return landmark after '${needle}'`);
		return source.slice(start, end);
	}
	for (const name of [
		'export async function clonePlanTemplate(',
		'export async function clonePublicPlan(',
		'export async function cloneSessionTemplate(',
		'export async function publishGymRoutineAsTemplate(',
		'export async function cloneGymRoutineTemplate(',
	]) {
		const body = bodyOf(name);
		assert.match(
			body,
			/rateLimitErrorMessage\(m,/,
			`${name} must call rateLimitErrorMessage(m, …) — every P0001 rate-limit bucket goes through the shared helper, with the localizer passed in.`,
		);
		assert.match(
			body,
			/if\s*\(friendly\)\s*throw\s+new\s+Error\(friendly\)/,
			`${name} must throw the friendly string when the helper recognises the bucket. Skipping the throw drops back to the raw postgres exception.`,
		);
	}
});

test('sendDm translates the direct_messages send buckets via the shared helper', () => {
	// Reason: migration 20270608_001 put two P0001 buckets on the
	// `direct_messages` INSERT itself, so the /messages composer and
	// SendRouteDialog can both hit one. Both surfaces render the thrown
	// `e.message` verbatim in a role="alert" line, so a wrapper that
	// re-threw the PostgrestError would print `rate limit exceeded for
	// send_direct_message_burst, retry in 41s` at a sender. The 42501
	// branch must still come first: a follow-graph refusal is a
	// different answer from "too fast" and only one of them is worth
	// waiting out.
	const source = read('src/lib/core/data.ts');
	const start = source.indexOf('export async function sendDm(');
	assert.ok(start >= 0, 'Could not locate sendDm — rename?');
	const end = source.indexOf('export async function markDmThreadRead(', start);
	assert.ok(end > start, 'Could not locate the markDmThreadRead landmark after sendDm');
	const body = source.slice(start, end);
	assert.match(
		body,
		/rateLimitErrorMessage\(m,/,
		'sendDm must call rateLimitErrorMessage(m, …) — every P0001 bucket goes through the shared helper, with the localizer passed in.',
	);
	assert.match(
		body,
		/if\s*\(friendly\)\s*throw\s+new\s+Error\(friendly\)/,
		'sendDm must throw the friendly string when the helper recognises the bucket.',
	);
	assert.ok(
		body.indexOf("=== '42501'") < body.indexOf('rateLimitErrorMessage(m,'),
		'the 42501 follow-graph branch must be checked before the rate-limit branch.',
	);
});

test('every rate-limit trigger raises through enforce_create_rate_limit', () => {
	// Reason: the parsers match one literal — `rate limit exceeded for
	// <bucket>, retry in Ns`. A trigger that calls `check_rate_limit`
	// itself and raises its own string produces a P0001 no client can
	// read, which is what `challenges` did between 20270308_001 and
	// 20270610_001: it raised the bare `challenge_create_rate_limited`,
	// with no bucket and no retry figure, and the only surface that could
	// have shown it fell through to a generic toast instead. Guarding the
	// producer at the class level rather than pinning that one bucket:
	// this is the check the next throttle has to pass too.
	//
	// "Later migration wins" — the map is keyed on the function name, so a
	// grandfathered body is fine as long as a newer migration replaces it.
	const MIGRATIONS = resolve(__dirname, '..', '..', '..', '..', 'apps/backend/supabase/migrations');
	const files = readdirSync(MIGRATIONS)
		.filter((f) => f.endsWith('.sql'))
		.sort();
	const latestBody = new Map<string, { file: string; body: string }>();
	for (const file of files) {
		const sql = readFileSync(resolve(MIGRATIONS, file), 'utf-8');
		for (const match of sql.matchAll(
			/create\s+or\s+replace\s+function\s+(\w+)\s*\(\s*\)\s*\n?\s*returns\s+trigger[\s\S]*?\n\$\$;/gi,
		)) {
			latestBody.set(match[1], { file, body: match[0] });
		}
	}
	assert.ok(latestBody.size > 0, 'no trigger functions parsed out of the migrations — did the regex rot?');
	let checked = 0;
	for (const [name, { file, body }] of latestBody) {
		if (!/rate_limit/i.test(body)) continue;
		checked += 1;
		assert.match(
			body,
			/perform\s+enforce_create_rate_limit\(/i,
			`${name} (last defined in ${file}) throttles without calling enforce_create_rate_limit — route it through the shared helper so the refusal carries the bucket + retry figure the client parsers read.`,
		);
		assert.doesNotMatch(
			body,
			/\bcheck_rate_limit\s*\(/i,
			`${name} (last defined in ${file}) calls check_rate_limit directly. Only enforce_create_rate_limit may do that — it is what raises the parseable message and carries the service-role / null-auth / forged-owner skips.`,
		);
	}
	assert.ok(
		checked >= 4,
		`expected at least the clubs / routes / direct_messages / challenges throttles, found ${checked} rate-limit trigger functions`,
	);
});

test('every LLM-spending endpoint carries a per-user rate-limit bucket', () => {
	// Reason: Pro is a monthly price, not a per-call one. `/api/coach` is
	// capped by increment_coach_usage and the two route-engine handlers by
	// checkRouteRateLimit, but route-describe and route-request shipped with
	// neither — a single subscription (or one leaked Pro JWT) bought unbounded
	// claude-opus-4-8 calls on the operator's key. The only backstop was the
	// per-IP WAF rule in infra/modules/web-stack/waf.tf, which by construction
	// cannot see one JWT spread across an IP pool — the exact hole
	// $lib/routes/rate_limit.ts was written for. Every handler that reaches a
	// billed provider must hold a durable per-user ceiling, and it must be
	// taken BEFORE the provider call.
	for (const [file, marker] of [
		['src/lib/routes/route_describe/handler.ts', 'anthropic.messages.create'],
		['src/lib/routes/route_request/handler.ts', 'anthropic.messages.create'],
		['src/lib/routes/generate/handler.ts', 'const fetcher: Fetcher'],
		['src/lib/routes/osrm_proxy/handler.ts', 'const fetcher: Fetcher'],
	] as const) {
		const source = read(file);
		assert.match(
			source,
			/checkRouteRateLimit\(/,
			`${file} calls a billed provider and must take a per-user rate-limit slot ` +
				'via checkRouteRateLimit — the per-IP WAF rule is not a per-user ceiling.',
		);
		const gateIdx = source.indexOf('checkRouteRateLimit(');
		const spendIdx = source.indexOf(marker);
		assert.ok(
			gateIdx > 0 && spendIdx > 0 && gateIdx < spendIdx,
			`${file}: the rate-limit check must precede the billed call (${marker}).`,
		);
		// The verdict is a three-value union; anything other than 'ok' has to
		// deny, or a fail-closed 'error' silently grants the spend.
		assert.match(
			source,
			/rl !== 'ok'|verdict === 'limited'/,
			`${file} must deny on a non-'ok' rate-limit verdict (fail closed on 'error').`,
		);
	}
});
