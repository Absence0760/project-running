import { test } from 'node:test';
import assert from 'node:assert/strict';
import { formatDecimal, formatInteger } from './number';

// de uses "." for grouping + "," for decimal; en/ja use "," + ".". fr uses a
// narrow no-break space for grouping (ICU-version-sensitive), so fr is
// asserted on the decimal separator only, not the group separator.

test('formatDecimal: fixed fraction digits per locale', () => {
	assert.equal(formatDecimal(5.21, 2, 'en'), '5.21');
	assert.equal(formatDecimal(5.21, 2, 'de'), '5,21');
	assert.equal(formatDecimal(5.21, 2, 'ja'), '5.21');
	assert.equal(formatDecimal(5.21, 2, 'pt-BR'), '5,21');
	// Pads to the requested width like toFixed did.
	assert.equal(formatDecimal(5, 2, 'en'), '5.00');
	assert.equal(formatDecimal(6.5, 2, 'de'), '6,50');
	assert.equal(formatDecimal(8.123, 1, 'en'), '8.1');
});

test('formatDecimal: comma-decimal locales use a comma', () => {
	for (const loc of ['de', 'fr', 'es', 'pt-BR']) {
		assert.match(formatDecimal(5.21, 2, loc), /^5,21$/, loc);
	}
});

test('formatDecimal: grouping + decimal together', () => {
	assert.equal(formatDecimal(1234.5, 1, 'en'), '1,234.5');
	assert.equal(formatDecimal(1234.5, 1, 'de'), '1.234,5');
});

test('formatInteger: groups thousands per locale', () => {
	assert.equal(formatInteger(1234, 'en'), '1,234');
	assert.equal(formatInteger(1234, 'de'), '1.234');
	assert.equal(formatInteger(1234, 'ja'), '1,234');
	// Sub-thousand values are ungrouped everywhere.
	assert.equal(formatInteger(842, 'en'), '842');
	assert.equal(formatInteger(842, 'de'), '842');
});

test('default (undefined) locale returns a string without throwing', () => {
	assert.equal(typeof formatDecimal(5.21, 2), 'string');
	assert.equal(typeof formatInteger(1234), 'string');
});

test('repeated calls are stable (memoised formatter)', () => {
	assert.equal(formatDecimal(5.21, 2, 'de'), formatDecimal(5.21, 2, 'de'));
	assert.equal(formatInteger(1234, 'en'), formatInteger(1234, 'en'));
});
