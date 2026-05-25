// Regression test for the server-side Sentry consent gate.
// audit/cookie-consent + audit/third-party-data-flows (May 2026).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import {
	isConsentGiven,
	isConsentGivenFromCookieHeader,
} from './consent_cookie';

const __dirname = dirname(fileURLToPath(import.meta.url));

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

test(
	'CRITICAL: a 5xx error must NOT reach Sentry without consent — ' +
		'documented gate covers handleError too',
	() => {
		// Reason: the first iteration of the consent fix only wrapped
		// `handle` and left `handleError = Sentry.handleErrorWithSentry()`
		// untouched. captureException fires unconditionally inside
		// handleErrorWithSentry (verified by reading the @sentry/sveltekit
		// source). The self-audit follow-up wrapped handleError too. This
		// test is source-grep only — actually instantiating Sentry +
		// faking an error would require the Svelte runtime, which the
		// tsx unit test runner can't load.
		const src = readFileSync(
			resolve(__dirname, '..', 'hooks.server.ts'),
			'utf8',
		);
		assert.match(
			src,
			/export const handleError\s*:\s*HandleServerError\s*=/,
			'hooks.server.ts must export a TYPED handleError so the ' +
				'wrapped consent-gated version replaces the raw ' +
				'handleErrorWithSentry. Bare ' +
				'`export const handleError = Sentry.handleErrorWithSentry()` ' +
				'lets 5xx errors leak to Sentry without consent.',
		);
		assert.match(
			src,
			/isConsentGiven\(input\.event\.request\)/,
			'handleError must check isConsentGiven on the request before ' +
				'delegating to Sentry.',
		);
		// Belt-and-braces: there should be NO bare assignment of
		// handleError to Sentry.handleErrorWithSentry().
		assert.doesNotMatch(
			src,
			/export const handleError\s*=\s*Sentry\.handleErrorWithSentry\(\)/,
			'hooks.server.ts must not export the raw Sentry handleError ' +
				'without a consent gate.',
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
