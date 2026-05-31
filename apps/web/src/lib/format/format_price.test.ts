import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatPrice } from './format_price.js';

test('formatPrice: en-US uses $9.99', () => {
	assert.equal(formatPrice(9.99, { locale: 'en-US' }), '$9.99');
});

test('formatPrice: de-DE uses German number format but USD, NOT a fake euro symbol', () => {
	// The price is an unconverted USD amount — showing € over it would
	// misrepresent the charge (EU Omnibus). Locale drives the NUMBER format
	// (comma decimal), currency stays USD. audit-findings 2026-05-30 Medium.
	const formatted = formatPrice(9.99, { locale: 'de-DE' });
	assert.ok(formatted.includes('9,99'), `expected German decimal in ${formatted}`);
	assert.ok(!formatted.includes('€'), `must NOT show a euro symbol over a USD amount: ${formatted}`);
	assert.ok(/\$/.test(formatted), `expected a USD ($) marker in ${formatted}`);
});

test('formatPrice: en-GB shows USD, NOT a fake £', () => {
	const formatted = formatPrice(9.99, { locale: 'en-GB' });
	assert.ok(formatted.includes('9.99'), `expected 9.99 in ${formatted}`);
	assert.ok(!formatted.includes('£'), `must NOT show £ over a USD amount: ${formatted}`);
});

test('formatPrice: ja-JP shows USD with cents (amount is dollars, not yen)', () => {
	const formatted = formatPrice(9.99, { locale: 'ja-JP' });
	assert.ok(formatted.includes('9.99'), `expected 9.99 in ${formatted}`);
});

test('formatPrice: explicit currency override beats the USD default (real localized price path)', () => {
	assert.equal(formatPrice(9.99, { locale: 'en-US', currency: 'EUR' }), '€9.99');
});
