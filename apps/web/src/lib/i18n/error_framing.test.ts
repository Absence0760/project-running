import { test } from 'node:test';
import assert from 'node:assert/strict';
import { interpolate } from './interpolate';
import { SUPPORTED_LOCALES } from './locale';
import { CATALOGUE_LOADERS } from './catalogues';

// Pins issue #345: the 16 error keys that previously surfaced the raw,
// untranslated Error.message first (`e?.message ?? m('x.yFailed')`) now frame
// the underlying error inside a translated sentence via an {error} slot. A
// non-English user must never see a bare backend string.

const KEYS = [
	'routeConditions.reportFailed',
	'routeConditions.deleteFailed',
	'clubPhotos.uploadFailed',
	'clubPhotos.deleteFailed',
	'clubPhotos.captionUpdateFailed',
	'runPhotos.uploadFailed',
	'runPhotos.deleteFailed',
	'runPhotos.captionUpdateFailed',
	'routePhotos.uploadFailed',
	'routePhotos.deleteFailed',
	'routePhotos.captionUpdateFailed',
	'planMeta.saveFailed',
	'settingsAccount.identitiesLoadFailed',
	'settingsAccount.linkFailed',
	'settingsAccount.unlinkFailed',
	'coachPage.consentRecordError',
] as const;

const RAW = 'new row violates row-level security policy for table "route_conditions"';

test('routeConditions.reportFailed frames the raw error instead of surfacing it bare', async () => {
	const en = (await CATALOGUE_LOADERS.en()) as Record<string, string>;
	const rendered = interpolate(en['routeConditions.reportFailed'], { error: RAW }, 'en');
	assert.ok(rendered.includes(RAW), 'renders the underlying error');
	assert.notEqual(rendered, RAW, 'is not a bare unlabelled backend string');
	assert.ok(rendered.length > RAW.length, 'wraps the error in translated framing copy');
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: all #345 keys exist, are translated, and keep the {error} slot`, async () => {
		const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
		for (const key of KEYS) {
			const template = dict[key];
			assert.ok(template && template.trim().length > 0, `${loc}.${key} is present and non-empty`);
			assert.ok(template.includes('{error}'), `${loc}.${key} keeps the {error} placeholder`);
			const rendered = interpolate(template, { error: 'boom', provider: 'Google' }, loc);
			assert.ok(rendered.includes('boom'), `${loc}.${key} interpolates the error`);
			assert.notEqual(rendered.trim(), 'boom', `${loc}.${key} is not a bare error string`);
		}
	});
}
