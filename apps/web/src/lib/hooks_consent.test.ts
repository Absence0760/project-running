// Regression test for the server-side Sentry consent gate.
// audit/cookie-consent + audit/third-party-data-flows (May 2026).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
	isConsentGiven,
	isConsentGivenFromCookieHeader,
} from './consent_cookie.ts';

function reqWithCookie(cookie: string | null): Request {
	const headers = new Headers();
	if (cookie !== null) headers.set('cookie', cookie);
	return new Request('http://localhost/', { headers });
}

test('isConsentGiven — no cookie header returns false', () => {
	assert.equal(isConsentGiven(reqWithCookie(null)), false);
});

test('isConsentGiven — empty cookie header returns false', () => {
	assert.equal(isConsentGiven(reqWithCookie('')), false);
});

test('isConsentGiven — unrelated cookies return false', () => {
	assert.equal(
		isConsentGiven(reqWithCookie('sb-access-token=abc; theme=dark')),
		false,
	);
});

test('isConsentGiven — accepted cookie returns true', () => {
	assert.equal(
		isConsentGiven(reqWithCookie('cookie_consent=accepted')),
		true,
	);
});

test('isConsentGiven — accepted cookie alongside others returns true', () => {
	assert.equal(
		isConsentGiven(
			reqWithCookie('sb-access-token=abc; cookie_consent=accepted; theme=dark'),
		),
		true,
	);
});

test('isConsentGiven — rejected cookie returns false', () => {
	assert.equal(
		isConsentGiven(reqWithCookie('cookie_consent=rejected')),
		false,
	);
});

test('isConsentGiven — unknown consent value returns false', () => {
	assert.equal(
		isConsentGiven(reqWithCookie('cookie_consent=maybe')),
		false,
	);
});

test(
	'isConsentGiven — cookie name is case-sensitive (RFC 6265) so ' +
		'COOKIE_CONSENT does not match',
	() => {
		assert.equal(
			isConsentGiven(reqWithCookie('COOKIE_CONSENT=accepted')),
			false,
		);
	},
);

test('isConsentGivenFromCookieHeader — accepts the raw header form', () => {
	assert.equal(
		isConsentGivenFromCookieHeader('cookie_consent=accepted; foo=bar'),
		true,
	);
	assert.equal(
		isConsentGivenFromCookieHeader('something_else=v'),
		false,
	);
	assert.equal(isConsentGivenFromCookieHeader(null), false);
	assert.equal(isConsentGivenFromCookieHeader(undefined), false);
});
