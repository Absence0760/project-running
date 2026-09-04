// A Strava export era that renames a column does not make the importer fail —
// `indexHeader` answers -1, `row[-1]` is `undefined`, and each read of it
// FABRICATES a value for every row in the archive while the summary still says
// "imported". decisions § 979 closed that for `Activity Type`; the same chain
// was live for the date, the duration and the distance.
//
// Both halves are EXECUTED now. `missingRequiredStravaColumns` lives beside
// `indexHeader` in the header module — which exists precisely so header logic
// can be unit-tested for real — so the refusal's own answer is measured rather
// than read off `strava-zip.ts` as text. The one thing left as source is that
// the importer still asks it, and asks before it reads anything.
//
// Invocation:
//   npx tsx --test src/lib/integrations/strava_zip_required_columns.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';

import { indexHeader, missingRequiredStravaColumns } from './strava-zip-header';

const IMPORTER = 'src/lib/integrations/strava-zip.ts';

/// Comments name the very shapes being refused, so they are blanked before any
/// scan — through the one shared stripper, never a `.replace` chain of our own
/// (decisions § 971 + § 1000; `source_scanner_guards.test.ts` enforces it).
function source(): string {
	return stripComments(readFileSync(resolve(IMPORTER), 'utf-8'));
}

const FULL_HEADER = [
	'Activity ID',
	'Activity Date',
	'Activity Name',
	'Activity Type',
	'Distance',
	'Moving Time',
	'Filename',
	'Elevation Gain',
];

/// Every required column, paired with the header cell whose absence makes
/// `indexHeader` answer -1 for it and the label the refusal must name.
const REQUIRED: { drop: string[]; field: keyof ReturnType<typeof indexHeader>; label: string }[] = [
	{ drop: ['Activity ID'], field: 'id', label: 'Activity ID' },
	{ drop: ['Filename'], field: 'filename', label: 'Filename' },
	// Both aliases have to go: `type` falls back to Sport Type (§ 979).
	{ drop: ['Activity Type'], field: 'type', label: 'Activity Type' },
	{ drop: ['Activity Date'], field: 'date', label: 'Activity Date' },
	{ drop: ['Moving Time'], field: 'movingTime', label: 'Moving Time' },
];

test('an omitted column resolves to -1, which is the whole hazard', () => {
	for (const { drop, field, label } of REQUIRED) {
		const idx = indexHeader(FULL_HEADER.filter((h) => !drop.includes(h)));
		assert.equal(idx[field], -1, `${label} still resolves without its header cell`);
		// And it resolves when present, or the guard would refuse every export.
		assert.ok(
			(indexHeader(FULL_HEADER)[field] as number) >= 0,
			`${label} does not resolve on a complete header`,
		);
	}
});

test('a header naming no distance column at all resolves neither index', () => {
	const idx = indexHeader(FULL_HEADER.filter((h) => h !== 'Distance'));
	assert.equal(idx.distance, -1);
	assert.equal(idx.distanceMetres, -1);
});

test('one Distance column is enough — the raw metric block is optional', () => {
	// The requirement is "either block", not both: an era carrying only the
	// display-unit column is importable at the athlete's own unit, and refusing
	// it would reject a legitimate export.
	const single = indexHeader(FULL_HEADER);
	assert.ok(single.distance >= 0);
	assert.equal(single.distanceMetres, -1);
	const both = indexHeader([...FULL_HEADER, 'Distance']);
	assert.ok(both.distance >= 0 && both.distanceMetres >= 0);
	assert.deepEqual(missingRequiredStravaColumns(both), []);
});

test('a complete header is importable', () => {
	assert.deepEqual(missingRequiredStravaColumns(indexHeader(FULL_HEADER)), []);
});

test('every column whose absence fabricates a value is refused, by name', () => {
	for (const { drop, label } of REQUIRED) {
		assert.deepEqual(
			missingRequiredStravaColumns(indexHeader(FULL_HEADER.filter((h) => !drop.includes(h)))),
			[label],
			`a missing ${label} column is not refused — every row would carry a ` +
				'fabricated value with nothing reporting a failure',
		);
	}
});

test('a header with no distance column at all is refused naming Distance', () => {
	assert.deepEqual(
		missingRequiredStravaColumns(indexHeader(FULL_HEADER.filter((h) => h !== 'Distance'))),
		['Distance'],
		'with neither block resolved every run imports at zero distance',
	);
});

test('a header naming none of them lists every one the operator has to look for', () => {
	assert.deepEqual(missingRequiredStravaColumns(indexHeader([])), [
		'Activity ID',
		'Filename',
		'Activity Type',
		'Activity Date',
		'Moving Time',
		'Distance',
	]);
});

test('a Sport-Type-only export still satisfies the activity-type requirement', () => {
	// § 979: `type` falls back to Sport Type, so an era that drops the coarse
	// column is importable and must not be refused.
	const header = FULL_HEADER.map((h) => (h === 'Activity Type' ? 'Sport Type' : h));
	assert.deepEqual(missingRequiredStravaColumns(indexHeader(header)), []);
});

test('the importer refuses on the shared answer, before it reads anything', () => {
	const s = source();
	const from = s.indexOf('const idx = indexHeader(header)');
	const to = s.indexOf('const seen = await');
	assert.notEqual(from, -1, 'the header index no longer resolved here');
	assert.notEqual(to, -1, 'the required-column check no longer precedes the dedupe read');
	assert.ok(to > from, 'the guard region is inverted — re-anchor this');
	const guard = s.slice(from, to);
	assert.match(
		guard,
		/missingRequiredStravaColumns\(idx\)/,
		'the importer must ask the header module, not re-derive the list inline — ' +
			'an inline copy is the shape that kept this guard unexecutable',
	);
	assert.match(
		guard,
		/throw new ImportRefusedError\('strava_zip_missing_columns', \{ columns: missing \}\)/,
		'the refusal must carry the column list as DATA so the page can say it in ' +
			"the reader's own language",
	);
});

test('a row whose date cannot be read is refused, not stamped with the import moment', () => {
	const s = source();
	const from = s.indexOf('async function importOne(');
	const to = s.indexOf('const distanceM = stravaDistanceMetres(row, idx)');
	assert.ok(from !== -1 && to > from, 'importOne moved — re-anchor this');
	const head = s.slice(from, to);
	assert.match(
		head,
		/const startedAt = parseStravaCsvDateToIso\(row\[idx\.date\]\)/,
		'the row must resolve its own start instant before anything else uses it',
	);
	assert.match(
		head,
		/startedAt === null[\s\S]{0,200}?throw new Error/,
		'an unreadable date must refuse the row; the per-row catch reports it',
	);
	assert.doesNotMatch(
		s,
		/started_at:[^\n]*new Date\(\)\.toISOString\(\)/,
		'a fabricated start filed a 2019 run under this morning and corrupted ' +
			'every window that reads started_at, silently',
	);
});
