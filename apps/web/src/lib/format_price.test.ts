import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectCurrency, formatPrice } from './format_price.js';

test('detectCurrency: en-US → USD', () => {
	assert.equal(detectCurrency('en-US'), 'USD');
});

test('detectCurrency: en-GB → GBP', () => {
	assert.equal(detectCurrency('en-GB'), 'GBP');
});

test('detectCurrency: de-DE → EUR', () => {
	assert.equal(detectCurrency('de-DE'), 'EUR');
});

test('detectCurrency: ja-JP → JPY', () => {
	assert.equal(detectCurrency('ja-JP'), 'JPY');
});

test('detectCurrency: pt-BR → BRL', () => {
	assert.equal(detectCurrency('pt-BR'), 'BRL');
});

test('detectCurrency: language-only locale → USD fallback', () => {
	assert.equal(detectCurrency('fr'), 'USD');
});

test('detectCurrency: unknown region → USD fallback', () => {
	assert.equal(detectCurrency('en-ZW'), 'USD');
});

test('formatPrice: en-US uses $9.99', () => {
	assert.equal(formatPrice(9.99, { locale: 'en-US' }), '$9.99');
});

test('formatPrice: de-DE uses comma decimal + euro suffix', () => {
	const formatted = formatPrice(9.99, { locale: 'de-DE' });
	assert.ok(formatted.includes('9,99'), `expected German decimal in ${formatted}`);
	assert.ok(formatted.includes('€'), `expected euro sign in ${formatted}`);
});

test('formatPrice: en-GB renders £', () => {
	const formatted = formatPrice(9.99, { locale: 'en-GB' });
	assert.ok(formatted.includes('£9.99'), `expected £ in ${formatted}`);
});

test('formatPrice: ja-JP rounds yen (no decimals)', () => {
	const formatted = formatPrice(999, { locale: 'ja-JP' });
	assert.ok(formatted.includes('999'), `expected 999 in ${formatted}`);
});

test('formatPrice: explicit currency override beats locale detection', () => {
	assert.equal(formatPrice(9.99, { locale: 'en-US', currency: 'EUR' }), '€9.99');
});
