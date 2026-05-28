import { test } from 'node:test';
import assert from 'node:assert/strict';

import {
	hasGpcSignal,
	hasGpcSignalFromHeader,
	isConsentGiven,
	isConsentGivenFromCookieHeader,
	CONSENT_COOKIE_NAME,
} from './consent_cookie';

// ───────────────────────── cookie helper ─────────────────────────

test('isConsentGivenFromCookieHeader: empty / null → false', () => {
	assert.equal(isConsentGivenFromCookieHeader(null), false);
	assert.equal(isConsentGivenFromCookieHeader(undefined), false);
	assert.equal(isConsentGivenFromCookieHeader(''), false);
});

test('isConsentGivenFromCookieHeader: accepted cookie → true', () => {
	assert.equal(
		isConsentGivenFromCookieHeader(`${CONSENT_COOKIE_NAME}=accepted`),
		true,
	);
});

test('isConsentGivenFromCookieHeader: rejected cookie → false', () => {
	assert.equal(
		isConsentGivenFromCookieHeader(`${CONSENT_COOKIE_NAME}=rejected`),
		false,
	);
});

test('isConsentGivenFromCookieHeader: case-sensitive cookie name per RFC 6265', () => {
	assert.equal(
		isConsentGivenFromCookieHeader('Cookie_Consent=accepted'),
		false,
	);
});

// ───────────────────────── GPC helper ─────────────────────────

test('hasGpcSignalFromHeader: "1" → true (the only active signal per spec)', () => {
	assert.equal(hasGpcSignalFromHeader('1'), true);
	// Leading / trailing whitespace tolerated — middleware sometimes
	// pads header values.
	assert.equal(hasGpcSignalFromHeader('  1  '), true);
});

test('hasGpcSignalFromHeader: "0" → false', () => {
	// Some clients send `Sec-GPC: 0` to actively signal "no opt-out".
	// We MUST treat that as not-signalled rather than fall through to
	// an else branch that lights up on any non-empty value.
	assert.equal(hasGpcSignalFromHeader('0'), false);
});

test('hasGpcSignalFromHeader: missing / null / empty → false', () => {
	assert.equal(hasGpcSignalFromHeader(null), false);
	assert.equal(hasGpcSignalFromHeader(undefined), false);
	assert.equal(hasGpcSignalFromHeader(''), false);
});

test('hasGpcSignal: reads sec-gpc from a Request', () => {
	const req = new Request('https://threkir.com/', {
		headers: { 'sec-gpc': '1' },
	});
	assert.equal(hasGpcSignal(req), true);
});

test('hasGpcSignal: case-insensitive header lookup (Headers normalises)', () => {
	const req = new Request('https://threkir.com/', {
		headers: { 'Sec-GPC': '1' },
	});
	assert.equal(hasGpcSignal(req), true);
});

// ────────────────── combined isConsentGiven gate ──────────────────

test('isConsentGiven: accepted cookie + no GPC → true', () => {
	const req = new Request('https://threkir.com/', {
		headers: { cookie: `${CONSENT_COOKIE_NAME}=accepted` },
	});
	assert.equal(isConsentGiven(req), true);
});

test('isConsentGiven: GPC signal hard-overrides an accepted cookie', () => {
	// Persona-hunt Round 3 finding Privacy #4. A user who once
	// accepted but later flipped their browser-level GPC toggle has
	// withdrawn consent. The server MUST honour the new signal
	// immediately, not on next manual visit to the banner.
	const req = new Request('https://threkir.com/', {
		headers: {
			cookie: `${CONSENT_COOKIE_NAME}=accepted`,
			'sec-gpc': '1',
		},
	});
	assert.equal(isConsentGiven(req), false);
});

test('isConsentGiven: no cookie + GPC=0 → false (no opt-out, but never accepted)', () => {
	const req = new Request('https://threkir.com/', {
		headers: { 'sec-gpc': '0' },
	});
	assert.equal(isConsentGiven(req), false);
});

test('isConsentGiven: no cookie + no GPC → false (the default)', () => {
	assert.equal(isConsentGiven(new Request('https://threkir.com/')), false);
});
