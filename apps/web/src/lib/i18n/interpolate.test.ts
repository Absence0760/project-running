import { test } from 'node:test';
import assert from 'node:assert/strict';
import { interpolate } from './interpolate';

test('returns the template unchanged when there are no params', () => {
	assert.equal(interpolate('Hello world'), 'Hello world');
	assert.equal(interpolate('No {placeholder} filled'), 'No {placeholder} filled');
});

test('substitutes a single placeholder', () => {
	assert.equal(interpolate('{name} — profile and sign out', { name: 'Sam' }), 'Sam — profile and sign out');
});

test('substitutes multiple distinct placeholders', () => {
	assert.equal(
		interpolate('{a} of {b}', { a: 3, b: 10 }),
		'3 of 10',
	);
});

test('replaces every occurrence of a repeated placeholder', () => {
	assert.equal(interpolate('{x}+{x}', { x: 2 }), '2+2');
});

test('coerces numbers to strings', () => {
	assert.equal(interpolate('{n} km', { n: 5 }), '5 km');
});

test('leaves an unreferenced placeholder intact rather than blanking it', () => {
	assert.equal(interpolate('{known} {unknown}', { known: 'a' }), 'a {unknown}');
});

test('substitutes regex-special values verbatim (literal, not regex, replace)', () => {
	assert.equal(interpolate('cost: {price}', { price: '$1.99' }), 'cost: $1.99');
});
