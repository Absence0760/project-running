// The one 405 every Lambda in this tree answers with.
//
// Invocation:
//   npx tsx --test src/lib/core/method_gate.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { methodRefusal } from './method_gate';
import { shareMethodRefusal, SHARE_ALLOWED_METHODS } from '../share/share_method_gate';

test('an allowed method proceeds and everything else is refused', () => {
	assert.equal(methodRefusal('POST', ['POST']), null);
	assert.equal(methodRefusal('GET', ['GET', 'HEAD']), null);
	assert.equal(methodRefusal('HEAD', ['GET', 'HEAD']), null);
	for (const method of ['GET', 'HEAD', 'PUT', 'PATCH', 'DELETE', 'OPTIONS', 'TRACE']) {
		assert.equal(methodRefusal(method, ['POST'])?.statusCode, 405, method);
	}
});

test('the comparison is exact — no case folding, no prefix match', () => {
	// A Function URL hands the method up verbatim. Folding `post` in would
	// accept a method no HTTP intermediary treats as POST.
	for (const method of ['post', 'Post', 'POSTX', ' POST', 'POST ']) {
		assert.equal(methodRefusal(method, ['POST'])?.statusCode, 405, method);
	}
});

test('an absent method is refused, not waved through', () => {
	// Fail-closed: a malformed event must not resolve to "allowed".
	assert.equal(methodRefusal(undefined, ['POST'])?.statusCode, 405);
	assert.equal(methodRefusal('', ['POST'])?.statusCode, 405);
	assert.equal(shareMethodRefusal(undefined)?.statusCode, 405);
});

test('the refusal names what is allowed and forbids caching it', () => {
	// `Allow` is required on a 405 (RFC 9110 15.5.6) and is the only part that
	// differs per caller. `no-store` because a cached refusal outlives its fix
	// — the API Lambdas each sent one without it until this module existed.
	const one = methodRefusal('GET', ['POST']);
	assert.equal(one?.headers.allow, 'POST');
	assert.equal(one?.headers['cache-control'], 'no-store');
	assert.equal(one?.headers['content-type'], 'application/json');
	assert.deepEqual(JSON.parse(String(one?.body)), { error: 'method not allowed' });

	const many = methodRefusal('DELETE', ['GET', 'HEAD']);
	assert.equal(many?.headers.allow, 'GET, HEAD');
});

test('the share gate is this gate, instantiated', () => {
	// Re-export shape, like auth_gates' password floor: the surface keeps
	// naming its own rule while the refusal stays single-sourced.
	assert.deepEqual([...SHARE_ALLOWED_METHODS], ['GET', 'HEAD']);
	for (const method of ['GET', 'HEAD', 'POST', 'PUT', 'OPTIONS', undefined]) {
		assert.deepEqual(shareMethodRefusal(method), methodRefusal(method, SHARE_ALLOWED_METHODS));
	}
});
