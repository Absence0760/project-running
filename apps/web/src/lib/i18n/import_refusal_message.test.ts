// The sentence a refused bulk import shows, in every locale we ship.
// Invocation:
//   npx tsx --test src/lib/i18n/import_refusal_message.test.ts
//
// The defect this pins: `strava-zip.ts` threw four English sentences and
// `settings/integrations/+page.svelte` assigned `err.message` straight into
// the error slot, so the most informative message in the migration flow was
// the only string on that page that never translated.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { CATALOGUE_LOADERS } from './catalogues';
import { SUPPORTED_LOCALES } from './locale';
import { interpolate } from './interpolate';
import type { MessageKey } from './messages';
import { importRefusalMessage, type Translate } from './import_refusal_message';
import {
	ImportRefusedError,
	IMPORT_REFUSAL_REASONS,
	type ImportRefusalData,
	type ImportRefusalReason,
} from '../integrations/import_refusal';

/// One refusal per reason, carrying the data that reason travels with.
const SAMPLE: Record<ImportRefusalReason, ImportRefusalData> = {
	not_signed_in: {},
	strava_zip_too_large: { megabytes: 812, limitMegabytes: 500 },
	strava_zip_not_an_export: {},
	strava_zip_no_rows: {},
	strava_zip_missing_columns: { columns: ['Activity Type', 'Moving Time'] },
	garmin_unsupported_file: {},
};

const FALLBACK: MessageKey = 'settingsIntegrations.stravaZipImportFailed';

async function translatorFor(loc: (typeof SUPPORTED_LOCALES)[number]): Promise<Translate> {
	const dict = (await CATALOGUE_LOADERS[loc]()) as Record<string, string>;
	return (key, params) => interpolate(dict[key] ?? key, params, loc);
}

test('every shipped reason has a sample, and every sample a reason', () => {
	assert.deepEqual(
		Object.keys(SAMPLE).sort(),
		[...IMPORT_REFUSAL_REASONS].sort(),
		'a reason without a sample here is a reason no locale is measured against',
	);
});

for (const loc of SUPPORTED_LOCALES) {
	test(`${loc}: every refusal renders a filled, translated sentence`, async () => {
		const t = await translatorFor(loc);
		for (const reason of IMPORT_REFUSAL_REASONS) {
			const rendered = importRefusalMessage(
				t,
				new ImportRefusedError(reason, SAMPLE[reason]),
				FALLBACK,
			);
			assert.ok(rendered.trim().length > 0, `${loc}.${reason} renders empty`);
			assert.ok(
				!rendered.includes('importRefusal.'),
				`${loc}.${reason} rendered the key — the catalogue has no string for it`,
			);
			assert.ok(
				rendered !== reason,
				`${loc}.${reason} rendered the machine identifier at the reader`,
			);
			assert.doesNotMatch(
				rendered,
				/\{[a-zA-Z0-9_]+\}/,
				`${loc}.${reason} left a placeholder unfilled — the sentence names a ` +
					'slot the reason carries no data for',
			);
		}
	});

	test(`${loc}: the figures and the column list reach the reader`, async () => {
		const t = await translatorFor(loc);
		const tooLarge = importRefusalMessage(
			t,
			new ImportRefusedError('strava_zip_too_large', SAMPLE.strava_zip_too_large),
			FALLBACK,
		);
		assert.ok(tooLarge.includes('812'), `${loc} drops the archive's own size`);
		assert.ok(tooLarge.includes('500'), `${loc} drops the cap it passed`);

		const missing = importRefusalMessage(
			t,
			new ImportRefusedError('strava_zip_missing_columns', SAMPLE.strava_zip_missing_columns),
			FALLBACK,
		);
		// The column labels are literal `activities.csv` header cells, so they
		// are the same in every locale — an operator has to find them in a file
		// we did not write.
		assert.ok(missing.includes('Activity Type'), `${loc} drops a missing column`);
		assert.ok(missing.includes('Moving Time'), `${loc} drops a missing column`);
	});

	test(`${loc}: a thrown value that is not a refusal is framed, not shown bare`, async () => {
		const t = await translatorFor(loc);
		const raw = 'Failed to fetch';
		const rendered = importRefusalMessage(t, new Error(raw), FALLBACK);
		assert.ok(rendered.includes(raw), `${loc} loses the underlying error`);
		assert.notEqual(rendered.trim(), raw, `${loc} surfaces a bare backend string`);
		assert.ok(rendered.length > raw.length, `${loc} adds no translated framing`);
	});
}

test('a reason this build does not know falls through to the framing, not to a bare key', async () => {
	// Fail-closed: a refusal minted by a newer deployment of the importer, or a
	// thrown object that merely happens to carry a `reason` field, must not
	// reach the reader as an untranslated identifier.
	const t = await translatorFor('en');
	for (const impostor of [
		Object.assign(new Error('boom'), { reason: 'strava_zip_haunted' }),
		Object.assign(new Error('boom'), { reason: 42 }),
	]) {
		const rendered = importRefusalMessage(t, impostor, FALLBACK);
		assert.ok(rendered.includes('boom'), `an unknown reason must be framed: ${rendered}`);
		assert.ok(!rendered.includes('importRefusal.'), 'a bare key reached the reader');
	}
});

test('a plain object carrying a known reason is a refusal, not a stranger', async () => {
	// The narrowing is structural on purpose, so a value that crossed a module
	// boundary still renders its own sentence rather than its own message.
	const t = await translatorFor('en');
	const rendered = importRefusalMessage(t, { reason: 'not_signed_in', message: 'boom' }, FALLBACK);
	assert.ok(!rendered.includes('boom'));
	assert.equal(
		rendered,
		importRefusalMessage(t, new ImportRefusedError('not_signed_in'), FALLBACK),
	);
});

test('a non-Error thrown value still says something', async () => {
	const t = await translatorFor('en');
	assert.ok(importRefusalMessage(t, 'plain string', FALLBACK).includes('plain string'));
	assert.ok(importRefusalMessage(t, null, FALLBACK).trim().length > 0);
});
