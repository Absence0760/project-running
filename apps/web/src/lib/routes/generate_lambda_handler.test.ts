// The generate-route Lambda's own wrapper layer.
//
// `$lib/routes/generate/handler.ts` is the transport-agnostic core; this is
// the production Function URL wrapper around it, and nothing had ever executed
// it (decisions § 896). Its own responsibilities are the ones measured here:
// the method gate, the 4 KB body cap enforced against decoded BYTES, the
// base64 decode, the hardcoded `bypassPaywallEnabled: false`, and the outer
// envelope that turns any unexpected throw into a generic 503 rather than the
// runtime's default error body.
//
// Every case stops before a network call: the core refuses an unauthenticated
// caller before it constructs a Supabase client.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Buffer } from 'node:buffer';

import { handler } from '../../../lambda/generate-route/src/index.js';

process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';

const BODY_LIMIT_BYTES = 4 * 1024;
const REQUEST = JSON.stringify({ start: { lat: 51.5, lng: -0.1 }, targetDistanceM: 5000 });

/**
 * What this wrapper actually returns. `LambdaFunctionURLResult` is a union that
 * also admits a bare string, so it exposes none of these fields; the wrapper
 * only ever returns the response object.
 */
interface FunctionUrlResponse {
	statusCode: number;
	headers?: Record<string, string>;
	body?: string;
}

async function invoke(event: Record<string, unknown>): Promise<FunctionUrlResponse> {
	const realError = console.error;
	console.error = () => {};
	try {
		return (await handler({
			requestContext: { http: { method: 'POST' } },
			headers: {},
			...event,
		} as never)) as FunctionUrlResponse;
	} finally {
		console.error = realError;
	}
}

test('a non-POST is refused before the Pro gate or any engine call', async () => {
	for (const method of ['GET', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
		const out = await invoke({ body: REQUEST, requestContext: { http: { method } } });
		assert.equal(out.statusCode, 405, `${method} must not reach the generate core`);
		assert.equal(out.headers?.allow, 'POST');
		// A refusal is not a document, and this one had no cache directive at all
		// until it went through the shared gate (decisions § 1035).
		assert.equal(out.headers?.['cache-control'], 'no-store');
		assert.deepEqual(JSON.parse(String(out.body)), { error: 'method not allowed' });
	}
});

test('a well-formed POST reaches the core rather than a wrapper refusal', async () => {
	// With no engine configured the core answers its own 501 — which is the
	// point: the status is the CORE's, so the wrapper handed the request over
	// instead of answering for it. `bypassPaywallEnabled` is hardcoded false
	// here, so nothing in the environment can turn the Pro gate off.
	const out = await invoke({ body: REQUEST });
	assert.equal(out.statusCode, 501);
	assert.deepEqual(JSON.parse(String(out.body)), {
		error: 'route generation is not configured',
	});
});

test('an unparseable body is a 400, not a 5xx', async () => {
	const out = await invoke({ body: '{oops' });
	assert.equal(out.statusCode, 400);
	assert.deepEqual(JSON.parse(String(out.body)), { error: 'invalid JSON' });
});

test('the 4 KB cap is measured in decoded bytes, not string length', async () => {
	const over = await invoke({ body: 'x'.repeat(BODY_LIMIT_BYTES + 1) });
	assert.equal(over.statusCode, 413);

	// Half the cap in three-byte characters: under it by `String.length`, over
	// it in bytes — the same regression the coach body helper was written for.
	const multibyte = 'ࠀ'.repeat(BODY_LIMIT_BYTES / 2);
	assert.ok(multibyte.length < BODY_LIMIT_BYTES);
	assert.ok(Buffer.byteLength(multibyte, 'utf8') > BODY_LIMIT_BYTES);
	assert.equal((await invoke({ body: multibyte })).statusCode, 413);

	// Inside the cap, it fails on its content instead — which is what proves
	// the cap is the cap and not a blanket refusal.
	assert.notEqual((await invoke({ body: 'x'.repeat(BODY_LIMIT_BYTES - 1) })).statusCode, 413);
});

test('a base64 body is decoded, and is not decoded when it is not flagged', async () => {
	const encoded = Buffer.from(REQUEST, 'utf8').toString('base64');
	const plain = await invoke({ body: REQUEST });

	// Flagged: decoded, so it lands wherever the identical plain body lands.
	assert.equal((await invoke({ body: encoded, isBase64Encoded: true })).statusCode, plain.statusCode);

	// Unflagged: the same bytes are not base64 to this handler, so they are
	// unparseable JSON. A wrapper that decoded regardless of the flag would
	// answer the same as the case above and this would not discriminate.
	assert.equal((await invoke({ body: encoded })).statusCode, 400);
});

test('every response is JSON, so a client never has to guess at a refusal', async () => {
	for (const event of [
		{ body: REQUEST, requestContext: { http: { method: 'GET' } } },
		{ body: '{oops' },
		{ body: 'x'.repeat(BODY_LIMIT_BYTES + 1) },
		{ body: REQUEST },
	]) {
		const out = await invoke(event);
		assert.equal(out.headers?.['content-type'], 'application/json');
		assert.doesNotThrow(() => JSON.parse(String(out.body)));
	}
});
