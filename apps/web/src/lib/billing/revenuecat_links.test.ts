// Tests for the pure RevenueCat hosted-checkout URL builder.
// `revenuecat.ts` (which imports `$env/dynamic/public`) can't be imported
// under node:test — this helper carries the testable behaviour.
//   npx tsx --test src/lib/billing/revenuecat_links.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { buildCheckoutUrl } from './revenuecat_links';

const BASE = 'https://pay.rev.cat/abc123';

test('appends the user id as the App User ID path segment', () => {
	assert.equal(buildCheckoutUrl(BASE, 'user-1'), `${BASE}/user-1`);
});

test('URL-encodes the user id (App User IDs can contain reserved chars)', () => {
	assert.equal(buildCheckoutUrl(BASE, 'a b/c'), `${BASE}/a%20b%2Fc`);
});

test('strips a trailing slash on the base before appending', () => {
	assert.equal(buildCheckoutUrl(`${BASE}/`, 'user-1'), `${BASE}/user-1`);
	assert.equal(buildCheckoutUrl(`${BASE}///`, 'user-1'), `${BASE}/user-1`);
});

test('appends a URL-encoded redirect_url when supplied', () => {
	const url = buildCheckoutUrl(BASE, 'user-1', 'https://app.example.com/settings/upgrade');
	assert.equal(
		url,
		`${BASE}/user-1?redirect_url=${encodeURIComponent('https://app.example.com/settings/upgrade')}`,
	);
});

test('omits the redirect_url query when no return URL is given', () => {
	const url = buildCheckoutUrl(BASE, 'user-1');
	assert.ok(!url?.includes('redirect_url'));
});

test('returns null when the base is empty (fail-closed / unconfigured)', () => {
	assert.equal(buildCheckoutUrl('', 'user-1'), null);
	assert.equal(buildCheckoutUrl('   ', 'user-1', 'https://x/y'), null);
});
