// A file-level import refusal travels as data, and both importers raise it.
// Invocation:
//   npx tsx --test src/lib/integrations/import_refusal.test.ts
//
// The narrowing is executed here; the two importers and the page that renders
// them are read as source, because both import supabase-js (and the page is
// Svelte) and neither can be executed under raw tsx. What each source claim
// buys is stated where it is made.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';
import {
	asImportRefusal,
	ImportRefusedError,
	IMPORT_REFUSAL_REASONS,
	type ImportRefusalReason,
} from './import_refusal';

/// Which importer may raise which reason. Derived against
/// `IMPORT_REFUSAL_REASONS` below, so a reason added without a thrower — or a
/// thrower deleted — fails rather than quietly leaving a catalogue key that
/// nothing can ever show.
const RAISED_BY: Record<ImportRefusalReason, string[]> = {
	not_signed_in: ['strava-zip.ts', 'garmin-zip.ts'],
	strava_zip_too_large: ['strava-zip.ts'],
	strava_zip_not_an_export: ['strava-zip.ts'],
	strava_zip_no_rows: ['strava-zip.ts'],
	strava_zip_missing_columns: ['strava-zip.ts'],
	garmin_unsupported_file: ['garmin-zip.ts'],
};

/// The region of each importer that refuses the FILE, before any row is
/// touched. A per-row failure is `import_failures.ts`'s job and keeps its own
/// diagnostic English `detail`; only this region is the one message an
/// operator gets when nothing at all imports.
const FILE_LEVEL_REGION: Record<string, [string, string]> = {
	'strava-zip.ts': ['export async function importStravaZip(', 'const dataRows = rows.slice(1)'],
	'garmin-zip.ts': [
		'export async function importGarminBundle(',
		'const zip = await JSZip.loadAsync(file)',
	],
};

function source(file: string): string {
	return stripComments(readFileSync(resolve(`src/lib/integrations/${file}`), 'utf-8'));
}

test('a refusal narrows to its reason and its data', () => {
	const err = new ImportRefusedError('strava_zip_missing_columns', { columns: ['Filename'] });
	assert.ok(err instanceof Error, 'a refusal must still be an Error for every generic catch');
	assert.equal(err.message, 'strava_zip_missing_columns', 'the message is the identifier');
	assert.deepEqual(asImportRefusal(err), {
		reason: 'strava_zip_missing_columns',
		data: { columns: ['Filename'] },
	});
});

test('a refusal carrying no data narrows to an empty bag, never to null', () => {
	assert.deepEqual(asImportRefusal(new ImportRefusedError('not_signed_in')), {
		reason: 'not_signed_in',
		data: {},
	});
	assert.deepEqual(
		asImportRefusal(Object.assign(new Error('x'), { reason: 'not_signed_in', data: 'nope' })),
		{ reason: 'not_signed_in', data: {} },
		'a data field of the wrong shape must not reach the render layer',
	);
});

test('anything that is not one of our reasons narrows to null', () => {
	for (const value of [
		null,
		undefined,
		'not_signed_in',
		42,
		new Error('Not signed in'),
		Object.assign(new Error('x'), { reason: 'strava_zip_haunted' }),
		Object.assign(new Error('x'), { reason: 7 }),
	]) {
		assert.equal(asImportRefusal(value), null, `${String(value)} narrowed to a refusal`);
	}
});

test('every reason is raised by an importer, and every raise names a reason', () => {
	assert.deepEqual(
		Object.keys(RAISED_BY).sort(),
		[...IMPORT_REFUSAL_REASONS].sort(),
		'RAISED_BY and the shipped reason set must name the same refusals',
	);
	const raisedInSource = new Set<string>();
	for (const file of Object.keys(FILE_LEVEL_REGION)) {
		for (const m of source(file).matchAll(/new ImportRefusedError\(\s*'([a-z_]+)'/g)) {
			raisedInSource.add(`${m[1]}@${file}`);
			assert.ok(
				IMPORT_REFUSAL_REASONS.includes(m[1] as ImportRefusalReason),
				`${file} raises "${m[1]}", which no catalogue has a sentence for`,
			);
		}
	}
	for (const [reason, files] of Object.entries(RAISED_BY)) {
		for (const file of files) {
			assert.ok(
				raisedInSource.has(`${reason}@${file}`),
				`${file} no longer raises ${reason} — either it moved or the refusal ` +
					'went back to being an English sentence',
			);
		}
	}
});

test('neither importer throws a bare Error where the whole file is refused', () => {
	for (const [file, [from, to]] of Object.entries(FILE_LEVEL_REGION)) {
		const s = source(file);
		const start = s.indexOf(from);
		const end = s.indexOf(to);
		assert.notEqual(start, -1, `${file}: the entry point moved — re-anchor this`);
		assert.ok(end > start, `${file}: the file-level region is inverted — re-anchor this`);
		assert.doesNotMatch(
			s.slice(start, end),
			/throw new Error\(/,
			`${file} refuses the whole archive with an English sentence. It is the only ` +
				'message the operator gets, and it is the one string on the page that ' +
				'would not translate.',
		);
	}
});

test('the page renders both refusals through the catalogue, not through err.message', () => {
	const page = stripComments(
		readFileSync(resolve('src/routes/settings/integrations/+page.svelte'), 'utf-8'),
	);
	for (const slot of ['zipError', 'garminError']) {
		assert.match(
			page,
			new RegExp(`${slot} = importRefusalMessage\\(`),
			`${slot} must be assembled from the catalogue`,
		);
		assert.doesNotMatch(
			page,
			new RegExp(`${slot}\\s*=\\s*err\\b`),
			`${slot} is assigned the raw thrown value again`,
		);
	}
});
