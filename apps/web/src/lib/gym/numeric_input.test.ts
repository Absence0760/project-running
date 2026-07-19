import { test } from 'node:test';
import assert from 'node:assert/strict';

import { floatOrNull, intOrNull } from './numeric_input';

// `<input type="number" bind:value>` hands these coercers a NUMBER, not a
// string — the class of bug that silently dropped RoutineEditor progression
// params (#327): the old string-only guard returned null before parsing.
test('floatOrNull passes a number through unchanged', () => {
	assert.equal(floatOrNull(85), 85);
	assert.equal(floatOrNull(150), 150);
	assert.equal(floatOrNull(0.5), 0.5);
});

test('floatOrNull parses a numeric string', () => {
	assert.equal(floatOrNull('85'), 85);
	assert.equal(floatOrNull('2.5'), 2.5);
});

test('floatOrNull rejects blank / non-finite input', () => {
	assert.equal(floatOrNull(''), null);
	assert.equal(floatOrNull('   '), null);
	assert.equal(floatOrNull('abc'), null);
	assert.equal(floatOrNull(Number.NaN), null);
	assert.equal(floatOrNull(Number.POSITIVE_INFINITY), null);
});

test('intOrNull passes a number through, truncating to an integer', () => {
	assert.equal(intOrNull(12), 12);
	assert.equal(intOrNull(12.9), 12);
});

test('intOrNull parses a numeric string and rejects blanks', () => {
	assert.equal(intOrNull('8'), 8);
	assert.equal(intOrNull(''), null);
	assert.equal(intOrNull(Number.NaN), null);
});
