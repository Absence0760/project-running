import { test } from 'node:test';
import assert from 'node:assert/strict';

import type { LambdaFunctionURLEvent } from 'aws-lambda';

import { decodeKey, handler } from '../../../lambda/share-entity/src/index';

/// `/share/club/%zz` carries a percent-escape that isn't one, so
/// `decodeURIComponent` throws a URIError. Unguarded it fell to the Lambda's
/// outer catch and answered 503 — a server error, and a retry signal telling
/// crawlers to come back for a link that will never resolve. Every other
/// unresolvable entity answers the branded `noindex` 404, and so must this.

// Configured, so a 404 below can only come from the key — not from the
// missing-Supabase-config branch that also yields one. A malformed key is
// rejected before any lookup runs, so nothing reaches the network.
process.env.PUBLIC_SUPABASE_URL = 'http://supabase.invalid';
process.env.PUBLIC_SUPABASE_ANON_KEY = 'anon';

/// A GET, because the handler gates its method since decisions § 1005 and a
/// real Function URL event always carries one. These cases are about the path.
function urlEvent(rawPath: string): LambdaFunctionURLEvent {
	return {
		rawPath,
		requestContext: { http: { method: 'GET' } },
	} as unknown as LambdaFunctionURLEvent;
}

test('decodeKey returns null on a malformed percent-escape, decodes otherwise', () => {
	assert.equal(decodeKey('%zz'), null);
	assert.equal(decodeKey('%'), null);
	assert.equal(decodeKey('%E0%A4%A'), null);
	assert.equal(decodeKey('morning%20club'), 'morning club');
	assert.equal(decodeKey('plain-slug'), 'plain-slug');
});

test('a malformed path answers the branded noindex 404, never a 5xx', async () => {
	for (const path of [
		'/share/club/%zz',
		'/share/profile/%E0%A4%A',
		'/share/race/%',
		'/share/session/%zz',
		'/share/workout/%zz',
		'/share/event/%zz',
	]) {
		const res = await handler(urlEvent(path));
		assert.notEqual(typeof res, 'string');
		const r = res as { statusCode: number; body?: string; headers?: Record<string, string> };
		assert.equal(r.statusCode, 404, `${path} must not answer ${r.statusCode}`);
		assert.match(r.headers?.['content-type'] ?? '', /text\/html/);
		assert.match(r.body ?? '', /name="robots" content="noindex"/);
	}
});

test('a path outside the dispatcher still answers the JSON 404', async () => {
	const res = (await handler(urlEvent('/share/nothing/abc'))) as { statusCode: number };
	assert.equal(res.statusCode, 404);
});
