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

const SETS = '{n, plural, one {# set} other {# sets}}';

test('plural: selects the one branch for count 1 and other for N', () => {
	assert.equal(interpolate(SETS, { n: 1 }, 'en'), '1 set');
	assert.equal(interpolate(SETS, { n: 3 }, 'en'), '3 sets');
});

test('plural: count 0 uses the other branch in English', () => {
	assert.equal(interpolate(SETS, { n: 0 }, 'en'), '0 sets');
});

test('plural: # is replaced by the count inside the chosen branch', () => {
	assert.equal(interpolate('{count, plural, one {# exercise} other {# exercises}}', { count: 12 }, 'en'), '12 exercises');
});

test('plural: a locale whose PluralRules only returns "other" (ja) uses the lone other branch', () => {
	assert.equal(interpolate('{n, plural, other {#セット}}', { n: 1 }, 'ja'), '1セット');
	assert.equal(interpolate('{n, plural, other {#セット}}', { n: 5 }, 'ja'), '5セット');
});

test('plural: French treats 0 and 1 as the one category', () => {
	const days = '{n, plural, one {il y a # jour} other {il y a # jours}}';
	assert.equal(interpolate(days, { n: 0 }, 'fr'), 'il y a 0 jour');
	assert.equal(interpolate(days, { n: 1 }, 'fr'), 'il y a 1 jour');
	assert.equal(interpolate(days, { n: 2 }, 'fr'), 'il y a 2 jours');
});

test('plural: German one vs other', () => {
	const sets = '{n, plural, one {# Satz} other {# Sätze}}';
	assert.equal(interpolate(sets, { n: 1 }, 'de'), '1 Satz');
	assert.equal(interpolate(sets, { n: 4 }, 'de'), '4 Sätze');
});

test('plural: missing selected category falls back to other', () => {
	assert.equal(interpolate('{n, plural, other {# items}}', { n: 1 }, 'en'), '1 items');
});

test('plural: =N exact match wins over the category', () => {
	const tmpl = '{n, plural, =0 {no sets} one {# set} other {# sets}}';
	assert.equal(interpolate(tmpl, { n: 0 }, 'en'), 'no sets');
	assert.equal(interpolate(tmpl, { n: 1 }, 'en'), '1 set');
	assert.equal(interpolate(tmpl, { n: 2 }, 'en'), '2 sets');
});

test('plural: a block embedded in surrounding text', () => {
	assert.equal(
		interpolate('Done ({count, plural, one {# run} other {# runs}}).', { count: 1 }, 'en'),
		'Done (1 run).',
	);
	assert.equal(
		interpolate('Done ({count, plural, one {# run} other {# runs}}).', { count: 9 }, 'en'),
		'Done (9 runs).',
	);
});

test('plural: branch message may carry a named placeholder filled after selection', () => {
	const tmpl = '{n, plural, one {# route near {place}} other {# routes near {place}}}';
	assert.equal(interpolate(tmpl, { n: 1, place: 'home' }, 'en'), '1 route near home');
	assert.equal(interpolate(tmpl, { n: 5, place: 'home' }, 'en'), '5 routes near home');
});

test('plural: unknown locale falls back to English plural rules', () => {
	assert.equal(interpolate(SETS, { n: 1 }, 'zz-XX'), '1 set');
	assert.equal(interpolate(SETS, { n: 2 }, 'zz-XX'), '2 sets');
});

test('plural: defaults to English when no locale is given', () => {
	assert.equal(interpolate(SETS, { n: 1 }), '1 set');
});

test('non-plural templates are unaffected by the plural layer', () => {
	assert.equal(interpolate('{n} kcal', { n: 5 }, 'fr'), '5 kcal');
});
