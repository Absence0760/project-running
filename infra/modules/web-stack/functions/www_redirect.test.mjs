// Behavioural tests for the `www_redirect` CloudFront Function.
//
// This function runs at the edge on EVERY viewer request to the site — it is
// associated with every cache behaviour on the distribution (a dozen
// `function_association` blocks in main.tf), so it is the first code any
// visitor, crawler or API client touches. Until now nothing executed it.
// `tsconfig.cloudfront.json` typechecked it (decisions § 757) and that is a
// real rung, but a typecheck cannot tell a redirect that fires from one that
// silently does not.
//
// The function has no module system — `cloudfront-js-2.0` uploads a bare
// `function handler(event)` declaration and calls it by name — so there is
// nothing to import. The harness evaluates the source and pulls `handler` out
// of the resulting scope, which also pins that the file really does declare a
// top-level `handler` (a `const handler = …` or an `export` would not be
// callable at the edge).
//
// Run: `node --test infra/modules/web-stack/functions/www_redirect.test.mjs`
// CI:  the `parity-types` job in .github/workflows/ci.yml.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

const SOURCE = resolve(import.meta.dirname, 'www_redirect.js');

/** @returns {(event: any) => any} */
function loadHandler() {
	const src = readFileSync(SOURCE, 'utf8');
	// eslint-disable-next-line no-new-func
	const factory = new Function(`${src}\nreturn typeof handler === 'function' ? handler : null;`);
	const fn = factory();
	assert.ok(
		fn,
		'www_redirect.js must declare a top-level `function handler` — CloudFront ' +
			'calls the entry point by that name and there is no module system at the edge.',
	);
	return fn;
}

const handler = loadHandler();

/**
 * A viewer-request event. `querystring` is given in the runtime's parsed
 * shape: one entry per name, `multiValue` present only on repeats.
 * @param {{ host?: string, uri?: string, querystring?: Record<string, any>, method?: string }} over
 */
function viewerRequest(over = {}) {
	return {
		version: '1.0',
		context: {
			distributionDomainName: 'd111111abcdef8.cloudfront.net',
			distributionId: 'EDFDVBD6EXAMPLE',
			eventType: 'viewer-request',
			requestId: 'test',
		},
		viewer: { ip: '198.51.100.1' },
		request: {
			method: over.method ?? 'GET',
			uri: over.uri ?? '/',
			querystring: over.querystring ?? {},
			headers: over.host === undefined ? {} : { host: { value: over.host } },
			cookies: {},
		},
	};
}

/** @param {any} result */
function isRedirect(result) {
	return typeof result.statusCode === 'number';
}

/** @param {any} result */
function location(result) {
	return result.headers.location.value;
}

test('a www host redirects to the bare apex, preserving path and query', () => {
	const out = handler(
		viewerRequest({
			host: 'www.threkir.com',
			uri: '/routes/abc',
			querystring: { tab: { value: 'explore' } },
		}),
	);
	assert.ok(isRedirect(out));
	assert.equal(out.statusCode, 301);
	assert.equal(location(out), 'https://threkir.com/routes/abc?tab=explore');
});

test('a non-www host passes through untouched', () => {
	const event = viewerRequest({ host: 'threkir.com', uri: '/dashboard' });
	const out = handler(event);
	assert.equal(out, event.request, 'the request object itself must be returned, not a copy');
});

test('a missing Host header passes through rather than redirecting to https:///', () => {
	const event = viewerRequest({ uri: '/' });
	assert.equal(handler(event), event.request);
});

test('repeated query parameters all survive the redirect', () => {
	const out = handler(
		viewerRequest({
			host: 'www.threkir.com',
			uri: '/feed',
			querystring: {
				tag: { value: 'a', multiValue: [{ value: 'a' }, { value: 'b' }] },
				utm_source: { value: 'newsletter' },
			},
		}),
	);
	assert.equal(location(out), 'https://threkir.com/feed?tag=a&tag=b&utm_source=newsletter');
});

test('an already-encoded path is forwarded verbatim, never re-encoded', () => {
	const out = handler(
		viewerRequest({ host: 'www.threkir.com', uri: '/share/club/morning%20run%2Fclub' }),
	);
	assert.equal(location(out), 'https://threkir.com/share/club/morning%20run%2Fclub');
});

test('a traversal-shaped path stays on the apex host', () => {
	const out = handler(viewerRequest({ host: 'www.threkir.com', uri: '/..%2F..%2Fetc/passwd' }));
	assert.ok(
		location(out).startsWith('https://threkir.com/'),
		`Location escaped the apex: ${location(out)}`,
	);
});

test('a protocol-relative-looking path stays on the apex host', () => {
	const out = handler(viewerRequest({ host: 'www.threkir.com', uri: '//evil.example.com/x' }));
	assert.equal(location(out), 'https://threkir.com//evil.example.com/x');
});

// A hostname is case-insensitive (RFC 9110 § 4.2.3, RFC 3986 § 3.2.2), so a
// client may send any casing and CloudFront still routes it to this
// distribution and serves it. Keying the redirect off a case-SENSITIVE prefix
// therefore leaves `WWW.threkir.com` serving the whole site at a second host —
// precisely the duplicate-content split the function exists to close, still
// open to anyone (a crawler, a pasted link, a curl script) who does not
// lowercase first. Nothing in CloudFront's event contract promises a
// lowercased header VALUE; only header NAMES are documented as normalised.
test('a mixed-case www host is redirected, not served at the second host', () => {
	for (const host of ['WWW.threkir.com', 'Www.Threkir.com', 'wWw.threkir.com']) {
		const out = handler(viewerRequest({ host, uri: '/' }));
		assert.ok(isRedirect(out), `${host} was served instead of redirected`);
		assert.equal(location(out), 'https://threkir.com/');
	}
});

test('the apex in Location is lowercased, so one canonical spelling is advertised', () => {
	const out = handler(viewerRequest({ host: 'www.THREKIR.com', uri: '/learn' }));
	assert.equal(location(out), 'https://threkir.com/learn');
});

// A 301 tells the client the resource moved permanently but says nothing about
// preserving the method: every browser and most HTTP clients rewrite a POST to
// a GET and drop the body (RFC 9110 § 15.4.2 explicitly allows this for
// historical reasons). The function is attached to EVERY behaviour on the
// distribution, `/api/coach/*` included, so a POST to the www host is answered
// by a redirect that silently turns it into a bodiless GET. 308 is the
// method-preserving permanent redirect and carries the same "permanent, pass
// the ranking signal on" meaning to search engines.
test('a non-GET request is redirected with a method-preserving 308', () => {
	for (const method of ['POST', 'PUT', 'PATCH', 'DELETE']) {
		const out = handler(
			viewerRequest({ host: 'www.threkir.com', uri: '/api/coach', method }),
		);
		assert.equal(out.statusCode, 308, `${method} must not be downgraded to a GET`);
		assert.equal(location(out), 'https://threkir.com/api/coach');
	}
});

test('GET and HEAD keep the 301 crawlers have always seen', () => {
	for (const method of ['GET', 'HEAD']) {
		const out = handler(viewerRequest({ host: 'www.threkir.com', uri: '/', method }));
		assert.equal(out.statusCode, 301);
		assert.equal(out.statusDescription, 'Moved Permanently');
	}
});

test('a request with no query string yields a Location with no trailing ?', () => {
	const out = handler(viewerRequest({ host: 'www.threkir.com', uri: '/learn' }));
	assert.equal(location(out), 'https://threkir.com/learn');
});

test('a valueless query parameter survives as a bare name', () => {
	const out = handler(
		viewerRequest({ host: 'www.threkir.com', uri: '/', querystring: { debug: {} } }),
	);
	assert.equal(location(out), 'https://threkir.com/?debug');
});

test('a host that merely contains "www." is not treated as a www host', () => {
	const event = viewerRequest({ host: 'notwww.threkir.com', uri: '/' });
	assert.equal(handler(event), event.request);
});
