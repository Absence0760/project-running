// A Strava export era that renames a column does not make the importer fail —
// `indexHeader` answers -1, `row[-1]` is `undefined`, and each read of it
// FABRICATES a value for every row in the archive while the summary still says
// "imported". decisions § 979 closed that for `Activity Type`; the same chain
// was live for the date, the duration and the distance.
//
// Two halves, because only one of them can be executed here. `indexHeader` is
// pure, so the PREMISE — that an omitted column resolves to -1 — is measured.
// `strava-zip.ts` imports supabase-js and is unexecutable under raw tsx (the
// reason `strava_zip_strictness.test.ts` reads it as text too), so the guard's
// own shape is read off the source.
//
// Invocation:
//   npx tsx --test src/lib/integrations/strava_zip_required_columns.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { stripComments } from '../core/strip_comments';

import { indexHeader } from './strava-zip-header';

const IMPORTER = 'src/lib/integrations/strava-zip.ts';

/// Comments name the very shapes being refused, so they are blanked before any
/// scan — through the one shared stripper, never a `.replace` chain of our own
/// (decisions § 971 + § 1000; `security_guards.test.ts` enforces it).
function source(): string {
	return stripComments(readFileSync(resolve(IMPORTER), 'utf-8'));
}

function headerGuard(s: string): string {
	const from = s.indexOf('const idx = indexHeader(header)');
	const to = s.indexOf('const seen = await');
	assert.notEqual(from, -1, 'the header index no longer resolved here');
	assert.notEqual(to, -1, 'the required-column check no longer precedes the dedupe read');
	assert.ok(to > from, 'the guard region is inverted — re-anchor this');
	return s.slice(from, to);
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
});

test('the header guard tests every column whose absence fabricates a value', () => {
	const guard = headerGuard(source());
	for (const field of ['id', 'filename', 'type', 'date', 'movingTime'] as const) {
		assert.match(
			guard,
			new RegExp(`idx\\.${field} < 0`),
			`a missing ${field} column is not refused — every row would carry a ` +
				`fabricated value with nothing reporting a failure`,
		);
	}
	assert.match(
		guard,
		/idx\.distance < 0 && idx\.distanceMetres < 0/,
		'the distance requirement must be satisfied by EITHER block, and must ' +
			'exist: with neither resolved every run imports at zero distance',
	);
});

test('the refusal names each column the operator has to look for', () => {
	const guard = headerGuard(source());
	for (const { label } of REQUIRED) {
		assert.ok(
			guard.includes(`'${label}'`),
			`the refusal does not name ${label}, so the operator cannot act on it`,
		);
	}
	assert.ok(guard.includes("'Distance'"));
	assert.match(guard, /missing required columns/, 'the message no longer says what is wrong');
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
