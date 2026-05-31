import { test } from 'node:test';
import assert from 'node:assert/strict';
import { initial, hashHue } from './avatar';

test('initial — first non-whitespace char, uppercased', () => {
	assert.equal(initial('jared'), 'J');
	assert.equal(initial('  morgan'), 'M');
	assert.equal(initial('évie'), 'É');
});

test('initial — fallback to ? for empty/whitespace/nullish', () => {
	assert.equal(initial(null), '?');
	assert.equal(initial(undefined), '?');
	assert.equal(initial(''), '?');
	assert.equal(initial('   '), '?');
});

test('hashHue — deterministic and in [0, 360)', () => {
	const h = hashHue('a1b2c3d4-user');
	assert.equal(h, hashHue('a1b2c3d4-user'));
	assert.ok(Number.isInteger(h) && h >= 0 && h < 360);
	assert.ok(hashHue('') >= 0);
});
