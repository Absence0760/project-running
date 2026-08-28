// Unit tests for the CHECK-constraint ↔ TS-union guard.
//
// The last two cases read the COMMITTED tree, so a real drift fails them as
// well as the guard itself — which is why CI runs the guard first and this
// suite second (decisions § 774).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
	PAIRS,
	TYPES_FILE,
	audit,
	loadAllMigrationChecks,
	parseChecks,
	parseTsUnion,
} from './check_constraint_unions.mjs';

/** @param {Map<string, Set<string>>} m */
const plain = (m) => Object.fromEntries([...m].map(([k, v]) => [k, [...v].sort()]));

test('reads a CHECK ... in (...) clause onto the table it belongs to', () => {
	assert.deepEqual(
		plain(
			parseChecks(
				"alter table public.runs add constraint runs_source_ck check (source in ('manual', 'gps'));",
			),
		),
		{ 'runs.source': ['gps', 'manual'] },
	);
});

test('the nullable form and a later redefinition both land', () => {
	const sql = [
		"create table public.routes (surface text, constraint s check (surface is null or surface in ('road')));",
		"alter table public.routes add constraint s2 check (surface is null or surface in ('road', 'trail'));",
	].join('\n');
	assert.deepEqual(plain(parseChecks(sql)), { 'routes.surface': ['road', 'trail'] });
});

test('a genuine trailing line comment is still removed', () => {
	assert.deepEqual(
		plain(
			parseChecks(
				"alter table public.runs -- retarget\n  add constraint c check (source in ('gps'));",
			),
		),
		{ 'runs.source': ['gps'] },
	);
});

// The two reproductions. A regex `--`-to-end-of-line strip returned {} for the
// first and filed the second's clause under `runs`.
test('a `--` inside a string literal does not eat the CHECK clause after it', () => {
	assert.deepEqual(
		plain(
			parseChecks(
				"create table public.runs (note text default 'see docs -- section 4', " +
					"source text, constraint c check (source in ('manual', 'gps')));",
			),
		),
		{ 'runs.source': ['gps', 'manual'] },
	);
});

test('a `--` inside a string literal does not eat the alter-table header of the next statement', () => {
	const sql = [
		'alter table public.runs add column note text;',
		"comment on column public.runs.note is 'legacy -- deprecated'; alter table public.integrations",
		"  add constraint c check (provider in ('strava', 'garmin'));",
	].join('\n');
	assert.deepEqual(plain(parseChecks(sql)), {
		'integrations.provider': ['garmin', 'strava'],
	});
});

test('a block comment carrying a lone quote does not swallow the file', () => {
	assert.deepEqual(
		plain(
			parseChecks(
				"/* it's fine */ alter table public.runs add constraint c check (source in ('gps'));",
			),
		),
		{ 'runs.source': ['gps'] },
	);
});

test('unreadable SQL throws rather than reporting an empty parse', () => {
	assert.throws(() => parseChecks("select 'unterminated"), /unterminated string literal/);
});

test('a single-line TS union and a multi-line one both parse', () => {
	assert.deepEqual([...(parseTsUnion("export type A = 'a' | 'b';", 'A') ?? [])], ['a', 'b']);
	assert.deepEqual(
		[...(parseTsUnion("export type B =\n\t| 'x'\n\t| 'y';", 'B') ?? [])],
		['x', 'y'],
	);
	assert.equal(parseTsUnion("export type A = 'a';", 'Missing'), null);
});

test('audit reports the three failure shapes and stays quiet on agreement', () => {
	const types = "export type S = 'a' | 'b';\nexport type T = 'a';\n";
	const checks = new Map([
		['t.ok', new Set(['a', 'b'])],
		['t.drift', new Set(['a', 'b', 'c'])],
	]);
	const pairs = [
		{ tableColumn: 't.ok', tsUnion: 'S' },
		{ tableColumn: 't.drift', tsUnion: 'S' },
		{ tableColumn: 't.absent', tsUnion: 'S' },
		{ tableColumn: 't.ok', tsUnion: 'NoSuchUnion' },
	];
	const { errors, ok } = audit(checks, types, pairs);
	assert.equal(ok.length, 1);
	assert.equal(errors.length, 3);
	assert.match(errors[0], /drift on t\.drift/);
	assert.match(errors[1], /no CHECK constraint found on "t\.absent"/);
	assert.match(errors[2], /TS union not found/);
});

test('an empty PAIRS list is a failure, not a clean run', () => {
	const { errors } = audit(new Map(), '', []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /compares nothing/);
});

test('every migration in the committed tree lexes, and the pairs are covered', () => {
	const checks = loadAllMigrationChecks();
	assert.ok(checks.size >= PAIRS.length, `parsed only ${checks.size} table.column CHECK sets`);
	for (const { tableColumn } of PAIRS) {
		assert.ok(checks.has(tableColumn), `no CHECK parsed for ${tableColumn}`);
	}
});

test('the committed tree agrees', () => {
	const { errors } = audit(loadAllMigrationChecks(), readFileSync(TYPES_FILE, 'utf-8'));
	assert.deepEqual(errors, []);
});
