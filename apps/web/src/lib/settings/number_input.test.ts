import assert from 'node:assert/strict';
import test from 'node:test';

import { numberInputValue } from './number_input';

// ── numberInputValue ────────────────────────────────────────────────────────
// Regression: round 43's max-HR write gate read the bound state with
// `.trim()`. `bind:value` on `<input type="number">` had already replaced it
// with a number, so the derived threw on every keystroke, the save never ran,
// and a valid 182 was silently dropped. The number case is the one that
// mattered, so it is asserted first.
test('numberInputValue: a number-input binding yields a number, not a throw', () => {
	assert.equal(numberInputValue(182), 182);
	assert.equal(numberInputValue(0), 0);
});

test('numberInputValue: the pre-keystroke string state still reads', () => {
	assert.equal(numberInputValue('182'), 182);
	assert.equal(numberInputValue(' 182 '), 182);
});

test('numberInputValue: an empty or unparseable field is absent, not zero', () => {
	assert.equal(numberInputValue(''), null);
	assert.equal(numberInputValue('   '), null);
	assert.equal(numberInputValue(null), null);
	assert.equal(numberInputValue(undefined), null);
	assert.equal(numberInputValue('abc'), null);
	assert.equal(numberInputValue(Number.NaN), null);
});

test('numberInputValue: a non-finite binding is absent rather than propagated', () => {
	assert.equal(numberInputValue(Number.POSITIVE_INFINITY), null);
	assert.equal(numberInputValue(Number.NEGATIVE_INFINITY), null);
});
