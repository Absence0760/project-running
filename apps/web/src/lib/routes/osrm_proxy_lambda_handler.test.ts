// The osrm-proxy Lambda's own wrapper layer.
//
// `$lib/routes/osrm_proxy/handler.ts` is the transport-agnostic core and is
// covered by its own suite; this is the production Function URL wrapper around
// it, and nothing had ever executed it — the same gap decisions § 896 closed
// for the coach and generate-route wrappers, still open on the third.
//
// The wrapper owns four things the core cannot see, and each one fails
// silently if it stops working: the GET-only gate, the `/api/routes/osrm`
// prefix strip that turns a Function URL path into the OSRM-shaped sub-path
// the core parses, the hardcoded `allowDemoFallback: false` that stops an
// unconfigured production deploy from posting the runner's waypoints to the
// public community endpoint, and the outer envelope that turns any unexpected
// throw into a generic 503 rather than the Node runtime's default error body.
//
// Every case stops before a network call. With `OSRM_URL` unset the core
// answers 501 before the auth gate; with it set, an absent
// `x-supabase-authorization` is a 401 before any Supabase client is built.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { handler } from '../../../lambda/osrm-proxy/src/index.js';

process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';

/**
 * What this wrapper actually returns. `LambdaFunctionURLResult` is a union
 * that also admits a bare string, so it exposes none of these fields.
 */
interface FunctionUrlResponse {
	statusCode: number;
	headers?: Record<string, string>;
	body?: string;
}

const ROUTE_PATH = '/api/routes/osrm/route/v1/foot/-0.1,51.5;-0.12,51.51';

/// The log lines the last `invoke` produced. The auth gate is the only thing
/// in this path that logs, so its absence is how a case says the request never
/// reached it.
let logged: string[] = [];

async function invoke(
	event: Record<string, unknown>,
	env: Record<string, string | undefined> = {},
): Promise<FunctionUrlResponse> {
	const saved: Record<string, string | undefined> = {};
	for (const [k, v] of Object.entries(env)) {
		saved[k] = process.env[k];
		if (v === undefined) delete process.env[k];
		else process.env[k] = v;
	}
	logged = [];
	const realError = console.error;
	const realWarn = console.warn;
	console.error = (...args: unknown[]) => void logged.push(String(args[0]));
	console.warn = (...args: unknown[]) => void logged.push(String(args[0]));
	try {
		return (await handler({
			requestContext: { http: { method: 'GET' } },
			headers: {},
			rawPath: ROUTE_PATH,
			...event,
		} as never)) as FunctionUrlResponse;
	} finally {
		console.error = realError;
		console.warn = realWarn;
		for (const [k, v] of Object.entries(saved)) {
			if (v === undefined) delete process.env[k];
			else process.env[k] = v;
		}
	}
}

function body(out: FunctionUrlResponse): unknown {
	return JSON.parse(String(out.body));
}

test('a non-GET is refused before the auth gate or any engine call', async () => {
	for (const method of ['POST', 'PUT', 'PATCH', 'DELETE', 'HEAD', 'OPTIONS']) {
		const out = await invoke({ requestContext: { http: { method } } });
		assert.equal(out.statusCode, 405, `${method} must not reach the proxy core`);
		assert.deepEqual(body(out), { error: 'method not allowed' });
		// RFC 9110 15.5.6 requires Allow on a 405, and this behaviour's
		// CloudFront allowed_methods include POST/PUT/PATCH/DELETE — so a
		// non-GET really does arrive here rather than being refused at the edge.
		assert.equal(out.headers?.allow, 'GET');
	}
});

test('a path outside the /api/routes/osrm prefix is refused by the wrapper', async () => {
	for (const rawPath of ['/api/routes/generate', '/route/v1/foot/0,0;1,1', '/']) {
		const out = await invoke({ rawPath });
		assert.equal(out.statusCode, 400, rawPath);
		assert.deepEqual(body(out), { error: 'unsupported OSRM path' });
	}
});

test('a missing rawPath is refused rather than defaulting to the empty sub-path', async () => {
	const out = await invoke({ rawPath: undefined });
	assert.equal(out.statusCode, 400);
});

// The prefix strip is the wrapper's whole routing job: the core parses
// `{service}/v1/{profile}/{coords}` and would reject the full Function URL
// path. A 501 here is the CORE's answer to an unconfigured engine, which it
// only reaches once the path has parsed — so the status proves the strip
// happened, where a 400 would prove it did not.
test('the prefix is stripped, so a well-formed path reaches the core', async () => {
	const out = await invoke({}, { OSRM_URL: undefined });
	assert.equal(out.statusCode, 501);
	assert.deepEqual(body(out), { error: 'waypoint routing is not configured' });
});

test('a malformed sub-path is the core 400, not a wrapper 400', async () => {
	const out = await invoke({ rawPath: '/api/routes/osrm/route/v1/foot/999,999' });
	assert.equal(out.statusCode, 400);
	assert.deepEqual(body(out), { error: 'unsupported OSRM path' });
});

// `allowDemoFallback: false` is hardcoded here, not read from the environment:
// an unset OSRM_URL must answer 501, never quietly relay the runner's waypoint
// coordinates — routinely their home — to router.project-osrm.org, which we
// have no contract with (issue #198, decisions § 242).
test('an unconfigured engine is a 501, never the public demo endpoint', async () => {
	for (const value of [undefined, '']) {
		const out = await invoke({}, { OSRM_URL: value });
		assert.equal(out.statusCode, 501, `OSRM_URL=${JSON.stringify(value)}`);
	}
});

test('a configured engine still refuses an unauthenticated caller', async () => {
	const out = await invoke({}, { OSRM_URL: 'http://osrm.invalid' });
	assert.equal(out.statusCode, 401);
	assert.deepEqual(body(out), { error: 'not authenticated' });
});

test('the viewer JWT is read from x-supabase-authorization, not Authorization', async () => {
	// CloudFront's Lambda OAC owns `Authorization` for its sigv4 signature, so
	// a JWT arriving there is the signature and must not be read as a token.
	//
	// The status alone cannot say this: reading the wrong header yields a
	// token, and GoTrue then refuses it with the same 401 — measured, the
	// status-only form of this test survived swapping the header name. What
	// separates them is that reading the wrong header SPENDS a GoTrue round
	// trip on the sigv4 signature and logs the refusal; the right one answers
	// before any client is built.
	const out = await invoke(
		{ headers: { authorization: 'Bearer viewer-jwt' } },
		{ OSRM_URL: 'http://osrm.invalid' },
	);
	assert.equal(out.statusCode, 401, 'a JWT in Authorization must not authenticate the caller');
	assert.deepEqual(logged, [], 'the auth gate ran, so the signature header was read as a token');
});

test('query parameters reach the core, which validates them', async () => {
	const out = await invoke(
		{ queryStringParameters: { radiuses: 'not-a-number' } },
		{ OSRM_URL: 'http://osrm.invalid' },
	);
	assert.equal(out.statusCode, 400);
	assert.deepEqual(body(out), { error: 'invalid query parameter' });
});

test('an absent queryStringParameters is an empty query, not a throw', async () => {
	const out = await invoke({ queryStringParameters: undefined }, { OSRM_URL: undefined });
	assert.equal(out.statusCode, 501, 'the core was reached, so the wrapper substituted {}');
});

// The outer envelope: anything unexpected becomes a generic 503 and a tagged
// operator log line, never the Lambda runtime's default error body — which
// would put the throw's message on the wire.
test('an unexpected throw is a generic 503, not the runtime error envelope', async () => {
	const out = await invoke({ requestContext: undefined });
	assert.equal(out.statusCode, 503);
	assert.deepEqual(body(out), { error: 'waypoint routing is temporarily unavailable' });
});
