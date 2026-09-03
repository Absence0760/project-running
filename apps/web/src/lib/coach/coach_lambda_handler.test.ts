// The production coach Lambda's OWN layer — the part `handler.test.ts` cannot
// reach.
//
// `apps/web/src/lib/coach/handler.ts` is the transport-agnostic core and is
// well covered. `apps/web/lambda/coach/src/index.ts` is the wrapper that
// actually runs in production, and it owns everything the core does not: which
// sub-path a request dispatches to, which byte cap that sub-path gets, the
// base64 body decode, the custom auth header, the hardcoded
// `bypassPaywallEnabled: false`, and the outer fail-closed envelope an audit
// finding installed. None of it had ever been executed — of the eight Lambdas
// under `apps/web/lambda/`, only `share-entity` was driven by a test at all
// (decisions § 896).
//
// The module reads a runtime-provided `awslambda` global at import time, so the
// stub below is installed before the dynamic import rather than at the top of
// the file. Every case here stops before any network call: the wrapper's own
// refusals, plus the core's `parseAuthHeader` 401, which fires before the first
// Supabase client is constructed.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

import { COACH_BODY_LIMIT_BYTES } from './body.js';
import { stripComments } from '../core/strip_comments';

interface Written {
	status: number | undefined;
	headers: Record<string, string> | undefined;
	body: string;
}

let written: Written;

const responseStream = {
	write(chunk: string | Uint8Array): boolean {
		written.body += typeof chunk === 'string' ? chunk : Buffer.from(chunk).toString('utf8');
		return true;
	},
	end(): void {},
};

(globalThis as unknown as { awslambda: unknown }).awslambda = {
	streamifyResponse: <T>(fn: T): T => fn,
	HttpResponseStream: {
		from(stream: typeof responseStream, metadata: { statusCode: number; headers?: Record<string, string> }) {
			written.status = metadata.statusCode;
			written.headers = metadata.headers;
			return stream;
		},
	},
};

process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';
process.env.ANTHROPIC_API_KEY = 'sk-test-not-used';
delete process.env.COACH_PROVIDER;

const { handler } = (await import('../../../lambda/coach/src/index.js')) as {
	handler: (event: unknown, stream: unknown, context: unknown) => Promise<void>;
};

/** Drive the Lambda once and return what it wrote, with logs silenced. */
async function invoke(event: Record<string, unknown>): Promise<Written> {
	written = { status: undefined, headers: undefined, body: '' };
	const realError = console.error;
	console.error = () => {};
	try {
		await handler({ requestContext: { http: { method: 'POST' } }, headers: {}, ...event }, responseStream, {});
	} finally {
		console.error = realError;
	}
	return written;
}

const CHAT_BODY = JSON.stringify({ messages: [{ role: 'user', content: 'hi' }] });

test('a non-POST is refused before any work, with an Allow header', async () => {
	for (const method of ['GET', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
		const out = await invoke({
			rawPath: '/api/coach',
			body: CHAT_BODY,
			requestContext: { http: { method } },
		});
		assert.equal(out.status, 405, `${method} must not reach the coach core`);
		assert.equal(out.headers?.allow, 'POST');
		assert.deepEqual(JSON.parse(out.body), { error: 'method not allowed' });
	}
});

test('a POST with no auth header is refused 401 without reaching a provider', async () => {
	const out = await invoke({ rawPath: '/api/coach', body: CHAT_BODY });
	assert.equal(out.status, 401);
	assert.deepEqual(JSON.parse(out.body), { error: 'not authenticated' });
});

test('an unparseable body is a 400, not a 5xx', async () => {
	const out = await invoke({ rawPath: '/api/coach', body: '{oops' });
	assert.equal(out.status, 400);
	assert.deepEqual(JSON.parse(out.body), { error: 'invalid JSON' });
});

test('each sub-path enforces its own byte cap, measured in bytes', async () => {
	// The caps are deliberately unequal — a route-describe body is a few
	// numbers and a name, a coach body is a whole conversation — so a
	// dispatcher wired to the wrong constant is invisible without a case per
	// path. Each pair straddles that path's own cap.
	const cases: Array<[string, number]> = [
		['/api/coach', COACH_BODY_LIMIT_BYTES],
		['/api/coach/route-describe', 32 * 1024],
		['/api/coach/route-request', 16 * 1024],
	];
	for (const [rawPath, limit] of cases) {
		const over = await invoke({ rawPath, body: 'x'.repeat(limit + 1) });
		assert.equal(over.status, 413, `${rawPath} accepted a body past its cap`);
		assert.deepEqual(JSON.parse(over.body), { error: 'request too large' });

		// One byte under the cap gets past the size gate and fails on its
		// content instead, which is what proves the cap is the cap.
		const under = await invoke({ rawPath, body: 'x'.repeat(limit - 1) });
		assert.notEqual(under.status, 413, `${rawPath} rejected a body inside its cap`);
	}
});

test('the cap counts bytes, so a multi-byte body cannot smuggle past it', async () => {
	// Half the cap in three-byte characters is 1.5x the cap in bytes. A
	// `String.length` check would let this through — the regression `body.ts`
	// was written for, here through the wrapper that calls it.
	const body = 'ࠀ'.repeat(COACH_BODY_LIMIT_BYTES / 2);
	assert.ok(body.length < COACH_BODY_LIMIT_BYTES);
	assert.ok(Buffer.byteLength(body, 'utf8') > COACH_BODY_LIMIT_BYTES);
	const out = await invoke({ rawPath: '/api/coach', body });
	assert.equal(out.status, 413);
});

test('a base64 body is decoded before it is parsed', async () => {
	const out = await invoke({
		rawPath: '/api/coach',
		body: Buffer.from(CHAT_BODY, 'utf8').toString('base64'),
		isBase64Encoded: true,
	});
	// Past the JSON parse (which would 400 on the raw base64) and refused by
	// the core's auth gate instead.
	assert.equal(out.status, 401);
	assert.deepEqual(JSON.parse(out.body), { error: 'not authenticated' });
});

test('the same body NOT flagged base64 is rejected as unparseable', async () => {
	const out = await invoke({
		rawPath: '/api/coach',
		body: Buffer.from(CHAT_BODY, 'utf8').toString('base64'),
	});
	assert.equal(out.status, 400);
});

test('the auth header is read from x-supabase-authorization, never Authorization', async () => {
	// CloudFront's Lambda OAC sigv4-signs `Authorization` on every origin
	// request, so a viewer JWT in that slot is not the viewer's — treating it
	// as one would authenticate a request off CloudFront's own signature.
	const out = await invoke({
		rawPath: '/api/coach',
		body: CHAT_BODY,
		headers: { authorization: 'Bearer would-be-cloudfronts-signature' },
	});
	assert.equal(out.status, 401);
	assert.deepEqual(JSON.parse(out.body), { error: 'not authenticated' });
});

test('an unrecognised COACH_PROVIDER refuses the turn rather than guessing', async () => {
	process.env.COACH_PROVIDER = 'not-a-provider';
	try {
		const out = await invoke({ rawPath: '/api/coach', body: CHAT_BODY });
		assert.equal(out.status, 503);
		assert.deepEqual(JSON.parse(out.body), { error: 'Coach is not configured.' });
	} finally {
		delete process.env.COACH_PROVIDER;
	}
});

test('COACH_PROVIDER=openai with no base URL refuses before the quota is spent', async () => {
	// The core defaults an absent base URL to `http://localhost:11434/v1` —
	// right for a developer running Ollama, meaningless in a Lambda sandbox.
	// Without the wrapper's gate the turn passes auth, the paywall check and
	// the daily-quota increment before failing on a connection to a port
	// nothing is listening on.
	process.env.COACH_PROVIDER = 'openai';
	try {
		const out = await invoke({
			rawPath: '/api/coach',
			body: CHAT_BODY,
			headers: { 'x-supabase-authorization': 'Bearer tok' },
		});
		assert.equal(out.status, 503);
		assert.deepEqual(JSON.parse(out.body), { error: 'Coach is not configured.' });

		// With a base URL configured the wrapper hands over, and the refusal
		// that follows is the core's own — which is what shows the gate is the
		// gate rather than a blanket refusal of the openai provider.
		process.env.OPENAI_BASE_URL = 'http://openai.invalid/v1';
		const configured = await invoke({ rawPath: '/api/coach', body: CHAT_BODY });
		assert.equal(configured.status, 401);
	} finally {
		delete process.env.COACH_PROVIDER;
		delete process.env.OPENAI_BASE_URL;
	}
});

test('the provider check does not gate the two route sub-paths', async () => {
	// They are a Pro perk with a templated fallback and no COACH_PROVIDER of
	// their own, so an unconfigured provider must not 503 them.
	process.env.COACH_PROVIDER = 'not-a-provider';
	try {
		for (const rawPath of ['/api/coach/route-describe', '/api/coach/route-request']) {
			const out = await invoke({ rawPath, body: '{}' });
			assert.notEqual(out.status, 503, `${rawPath} was gated on COACH_PROVIDER`);
		}
	} finally {
		delete process.env.COACH_PROVIDER;
	}
});

test('a missing env var answers a generic 503 and never names itself on the wire', async () => {
	// The outer envelope from audit/coach Medium #6: before it, a `requireEnv`
	// throw reached the runtime's default error envelope and put the env-var
	// name in the 502 body. The operator side keeps the detail; the wire does
	// not.
	const saved = process.env.PUBLIC_SUPABASE_URL;
	delete process.env.PUBLIC_SUPABASE_URL;
	try {
		for (const rawPath of ['/api/coach', '/api/coach/route-describe', '/api/coach/route-request']) {
			const out = await invoke({
				rawPath,
				body: rawPath === '/api/coach' ? CHAT_BODY : '{}',
				headers: { 'x-supabase-authorization': 'Bearer tok' },
			});
			assert.equal(out.status, 503, rawPath);
			assert.deepEqual(JSON.parse(out.body), { error: 'Coach is temporarily unavailable.' });
			assert.doesNotMatch(out.body, /PUBLIC_SUPABASE_URL|env var/i, rawPath);
		}
	} finally {
		process.env.PUBLIC_SUPABASE_URL = saved;
	}
});

test('a sub-path refusal forwards the core\'s own status, headers and body', async () => {
	// The streaming coach path forwards `result.headers`; the two non-streaming
	// sub-dispatchers discarded them and re-serialised the body under a
	// hardcoded `content-type`, so anything the core attached to a refusal —
	// a `retry-after`, a `cache-control` — was dropped on the way out, and a
	// body the core did not mean as JSON turned a handled refusal into a 503
	// via the parse. Both cores emit only `content-type` today, so the
	// behavioural half cannot tell the two shapes apart: the discriminating
	// assertion is structural, that neither dispatcher re-derives the response
	// from a parsed copy.
	for (const rawPath of ['/api/coach/route-describe', '/api/coach/route-request']) {
		const out = await invoke({ rawPath, body: '{}' });
		assert.equal(out.headers?.['content-type'], 'application/json', rawPath);
	}

	// Comment bodies blanked, or the prose above `writeResult` explaining what
	// the old shape was would read as the old shape.
	const src = stripComments(
		readFileSync(
			resolve(import.meta.dirname, '..', '..', '..', 'lambda', 'coach', 'src', 'index.ts'),
			'utf-8',
		),
	);
	assert.doesNotMatch(
		src,
		/JSON\.parse\(result\.body\)/,
		'a dispatcher that re-parses the core\'s body has already discarded its headers.',
	);
	assert.equal(
		(src.match(/writeResult\(responseStream, result\)/g) ?? []).length,
		2,
		'both non-streaming sub-dispatchers must forward the core result verbatim.',
	);
});

test('the production config never honours the dev paywall bypass', async () => {
	// A source-level pin lives in security_guards.test.ts; this is the
	// behavioural half — BYPASS_PAYWALL set in the function's environment must
	// change nothing, because the wrapper hardcodes the field.
	process.env.BYPASS_PAYWALL = 'true';
	try {
		const out = await invoke({ rawPath: '/api/coach', body: CHAT_BODY });
		// The bypass would have to get past auth to matter, and it does not
		// reach it: the turn is still refused for the missing JWT.
		assert.equal(out.status, 401);
	} finally {
		delete process.env.BYPASS_PAYWALL;
	}
});

test('a sub-path is matched by its whole path, not by a substring of it', async () => {
	// The dispatch was `rawPath.includes('/route-describe')`, against a dev
	// route table that is exact (`src/routes/api/coach/route-describe/
	// +server.ts`). Measured before the fix: every path below reached the
	// route-describe or route-request handler and answered its own
	// `400 invalid route …`, where dev answers 404 (decisions § 967).
	for (const rawPath of [
		'/api/coach/route-describe-v2',
		'/api/coach/route-describeZZ',
		'/api/coach/x/route-describe',
		'/api/coach/route-describe/extra',
		'/api/coach/route-requestX',
		'/api/coach/route-request/extra',
	]) {
		const out = await invoke({ rawPath, body: CHAT_BODY });
		assert.equal(
			out.status,
			404,
			`${rawPath} was dispatched by a substring of a real sub-path`,
		);
		assert.deepEqual(JSON.parse(out.body), { error: 'not found' });
	}
});

test('an unknown path under the prefix never reaches the coach turn or its larger cap', async () => {
	// CloudFront sends the whole `/api/coach*` prefix here, so a path the dev
	// table does not declare used to fall THROUGH both `includes` tests to the
	// coach core — spending an auth round-trip and a daily-quota increment on a
	// path that does not exist, under the coach's own 256 KB cap rather than
	// the smaller one a `/route-…` name implies.
	const unknown = await invoke({ rawPath: '/api/coach/nonsense', body: CHAT_BODY });
	assert.equal(unknown.status, 404);

	const big = await invoke({
		rawPath: '/api/coach/nonsense',
		body: 'x'.repeat(COACH_BODY_LIMIT_BYTES + 1),
	});
	assert.equal(big.status, 404, 'an unknown path was sized against the coach cap');

	// The three paths the dev table does declare still route, trailing slash
	// included. The status is each handler's own first refusal — 401 for the
	// coach's auth gate, 400 for a sub-path's input check.
	for (const [rawPath, status] of [
		['/api/coach', 401],
		['/api/coach/', 401],
		['/api/coach/route-describe', 400],
		['/api/coach/route-describe/', 400],
		['/api/coach/route-request', 400],
		['/api/coach/route-request/', 400],
	] as Array<[string, number]>) {
		const out = await invoke({ rawPath, body: CHAT_BODY });
		assert.equal(out.status, status, `${rawPath} no longer routes`);
	}
});

test('the Lambda routes exactly the sub-paths the dev route table declares', () => {
	// Two independent spellings of one route set, and a disagreement is
	// invisible locally: SvelteKit runs the dev table, so a fourth sub-path
	// looks finished while production shadows it at whichever pattern matched
	// first. Derived from the directory rather than from a second hand-written
	// list, so adding a route is what fails this — not forgetting to update it.
	const devRoot = resolve(import.meta.dirname, '..', '..', 'routes', 'api', 'coach');
	const devSubPaths = readdirSync(devRoot, { withFileTypes: true })
		.filter((e) => e.isDirectory())
		.map((e) => e.name)
		.sort();
	assert.ok(devSubPaths.length > 0, `no dev sub-routes under ${devRoot} — walker broken?`);

	const src = readFileSync(
		resolve(import.meta.dirname, '..', '..', '..', 'lambda', 'coach', 'src', 'index.ts'),
		'utf-8',
	);
	const table = src.match(/const SUB_PATHS = \[([\s\S]*?)\]\.map\(/);
	assert.ok(table, 'the Lambda must declare its sub-paths in one SUB_PATHS table');
	const routed = [...table[1].matchAll(/segment: '([a-z-]+)'/g)].map((m) => m[1]).sort();

	assert.deepEqual(
		routed,
		devSubPaths,
		'the production path table and the dev route table disagree. A sub-path in ' +
			'one and not the other is a route that works locally and 404s in ' +
			'production, or the reverse.',
	);

	// No survivor of the substring dispatch: a bare `includes` on the path is
	// what let one sub-path shadow another.
	const code = stripComments(src);
	assert.doesNotMatch(
		code,
		/rawPath\.includes\(/,
		'dispatch on an anchored pattern, never on a substring of the path.',
	);
});
