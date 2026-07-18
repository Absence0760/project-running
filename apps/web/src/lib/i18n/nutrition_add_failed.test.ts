import { test } from 'node:test';
import assert from 'node:assert/strict';
import { interpolate } from './interpolate';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// Pins issue #358: the FoodLogEditor food-entry create path must toast a
// translated, framed sentence — never a bare (English) exception string or
// an empty toast when the error is message-less.

const KEY = 'nutrition.addFailed';

test('nutrition.addFailed resolves to a framed sentence in the default locale', async () => {
	const en = (await CATALOGUE_LOADERS.en()) as Record<string, string>;
	const template = en[KEY];
	assert.ok(template && template.trim().length > 0, 'en template is present and non-empty');

	const rendered = interpolate(template, { error: 'network down' }, 'en');
	assert.ok(rendered.includes('network down'), 'renders the underlying error');
	assert.notEqual(rendered, 'network down', 'is not a bare unlabelled error');
	assert.ok(rendered.length > 'network down'.length, 'wraps the error in framing copy');
});

test('a message-less error never yields an empty toast', async () => {
	const en = (await CATALOGUE_LOADERS.en()) as Record<string, string>;
	const rendered = interpolate(en[KEY], { error: '' }, 'en');
	assert.ok(rendered.trim().length > 0, 'still reads as a sentence with no error text');
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: nutrition.addFailed exists, is translated, and keeps the {error} slot`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		const template = dict[KEY];
		assert.ok(template && template.trim().length > 0, `${loc}.${KEY} is present and non-empty`);
		assert.ok(template.includes('{error}'), `${loc}.${KEY} keeps the {error} placeholder`);
		assert.ok(
			interpolate(template, { error: 'x' }, loc).includes('x'),
			`${loc}.${KEY} interpolates the error`,
		);
	});
}
