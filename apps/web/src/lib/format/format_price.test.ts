import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatPrice } from './format_price.js';
import { fromMinorUnits } from './minor_units.js';

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

test('formatPrice: a zero-decimal currency renders whole, with no forced cents', () => {
	const formatted = formatPrice(1000, { locale: 'ja-JP', currency: 'JPY' });
	assert.ok(formatted.includes('1,000'), `expected a whole 1,000 in ${formatted}`);
	assert.ok(!formatted.includes('.00'), `a yen amount has no minor unit: ${formatted}`);
});

test('formatPrice: a ¥1,000 donation round-trips from minor units at full value', () => {
	// Stripe hands a zero-decimal amount over in the BASE unit, so 1000 is
	// ¥1,000. The old blanket `/ 100` rendered this as ¥10.
	const formatted = formatPrice(fromMinorUnits(1000, 'JPY'), {
		locale: 'en-US',
		currency: 'JPY'
	});
	assert.equal(formatted, '¥1,000');
});

test('formatPrice: a three-decimal currency keeps all three', () => {
	const formatted = formatPrice(fromMinorUnits(1500, 'KWD'), {
		locale: 'en-US',
		currency: 'KWD'
	});
	assert.ok(formatted.includes('1.500'), `expected three decimals in ${formatted}`);
});

test('formatPrice: the fallback path names the real currency, never a stray dollar sign', () => {
	// An unusable currency code makes Intl throw. The old fallback printed
	// `$` over whatever the amount actually was.
	const formatted = formatPrice(9.99, { locale: 'en-US', currency: 'ZZ' });
	assert.ok(!formatted.includes('$'), `must not claim dollars: ${formatted}`);
	assert.ok(formatted.includes('9.99'), `expected the amount in ${formatted}`);
	assert.ok(formatted.includes('ZZ'), `expected the currency code in ${formatted}`);
});
