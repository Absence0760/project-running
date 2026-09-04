import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { probeSaysConfigured } from './provider_probe';

test('only the absence of an error reports a leg as configured', () => {
	assert.equal(probeSaysConfigured(null), true);
	assert.equal(probeSaysConfigured(undefined), true);
});

test('every failure shape a probe can come back with reports unavailable', () => {
	// The four the grader this replaced answered differently, plus the two it
	// already answered the same way. A 401 and a 400 are raised BEFORE the
	// Edge Function reads a credential, so neither is evidence of one.
	const shapes: Array<[string, unknown]> = [
		['503 provider_not_configured', { context: new Response('{"error":"provider_not_configured"}', { status: 503 }) }],
		['503 with an unreadable body', { context: new Response('<html>', { status: 503 }) }],
		['429 rate limited', { context: new Response('{"error":"rate_limited"}', { status: 429 }) }],
		['500 upstream', { context: new Response('', { status: 500 }) }],
		['401 signed out', { context: new Response('{"error":"unauthorized"}', { status: 401 }) }],
		['400 unknown_provider', { context: new Response('{"error":"unknown_provider"}', { status: 400 }) }],
		['404', { context: new Response('', { status: 404 }) }],
		['transport failure, no readable status', new TypeError('Failed to fetch')],
		['an opaque status-0 response', { context: { status: 0 } }],
		['a bare string', 'boom'],
	];
	for (const [name, error] of shapes) {
		assert.equal(probeSaysConfigured(error), false, `${name} must not report configured`);
	}
});
