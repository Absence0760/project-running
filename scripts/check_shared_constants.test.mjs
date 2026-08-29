// Unit tests for scripts/check_shared_constants.mjs.
//
// Two halves, and the split matters. The fixture cases drive the comparison
// and the four extractors with text this file owns, so a rule stays exercised
// after the production sources stop containing an example of it — the trap
// `check_watch_ble_uuids.test.mjs` records about its own UNCLAIMED rule. The
// last cases run the real registry against the real tree, which is what makes
// the guard's verdict about this repo rather than about its fixtures.
//
// Run: node --test scripts/check_shared_constants.test.mjs

import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
	REGISTRY,
	check,
	checkEntry,
	defaultContext,
	indexMigrations,
	parseAwarderLadders,
	parseBadgeCatalogue,
	parseNearbyCase,
	parseNumberList,
} from './check_shared_constants.mjs';

/** @param {Record<string, string>} files */
function migrationsFixture(files) {
	const dir = mkdtempSync(join(tmpdir(), 'shared-constants-'));
	for (const [name, body] of Object.entries(files)) writeFileSync(join(dir, name), body);
	return dir;
}

/**
 * @param {{ label: string, sites: { key: string, where: string, values: string[] }[] }[]} rails
 * @param {'all' | 'key'} match
 * @param {'set' | 'ordered'} compare
 */
function entryOf(rails, match, compare) {
	return {
		name: 'fixture',
		why: 'because.',
		match,
		compare,
		rails: rails.map((r) => ({ label: r.label, sites: () => r.sites })),
	};
}

const NO_CTX = /** @type {any} */ ({});

// ── indexMigrations: the replay, not the snapshot ───────────────────────────

test('the live body of a function is the last one the migrations wrote', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql': "create or replace function f() returns int language sql as $$ select 1; $$;",
		'20260102_001_b.sql': "create or replace function f() returns int language sql as $$ select 2; $$;",
	});
	const { live } = indexMigrations(dir);
	assert.equal(live.get('f')?.file, '20260102_001_b.sql');
	assert.match(live.get('f')?.sql ?? '', /select 2/);
});

test('a dropped function stops being live', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql':
			'create function f() returns int language sql as $$ select 1; $$;\n' +
			'create function g() returns int language sql as $$ select 2; $$;',
		'20260102_001_b.sql': 'drop function if exists f();',
	});
	const { live } = indexMigrations(dir);
	assert.equal(live.has('f'), false);
	assert.equal(live.has('g'), true);
});

// A `$$` body carries semicolons of its own, so a naive split on `;` would
// register the fragments as statements and lose the tail of every function.
test('a semicolon inside a function body does not end the statement', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql':
			'create or replace function f() returns int language sql as $$ select 1; select 2; $$;',
	});
	assert.match(indexMigrations(dir).live.get('f')?.sql ?? '', /select 2/);
});

// A historic definition preserved in a comment is exactly how the GATT guard
// went blind (decisions § 773); the lexer is what stops it here.
test('a commented-out definition does not register as live', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql': 'create or replace function f() returns int language sql as $$ select 1; $$;',
		'20260102_001_b.sql': '-- create or replace function f() returns int language sql as $$ select 99; $$;\nselect 1;',
	});
	assert.equal(indexMigrations(dir).live.get('f')?.file, '20260101_001_a.sql');
});

test('a migration set with no functions throws rather than reporting agreement', () => {
	const dir = migrationsFixture({ '20260101_001_a.sql': 'select 1;' });
	assert.throws(() => indexMigrations(dir), /parsed no function definitions/);
});

// ── The extractors ─────────────────────────────────────────────────────────

test('a number list is read from the named declaration, not the first array', () => {
	const src = "const kOther = [1, 2];\nconst kWanted = [2000, 5000, 10000];\n";
	assert.deepEqual(parseNumberList(src, 'kWanted'), ['2000', '5000', '10000']);
	assert.deepEqual(parseNumberList(src, 'kOther'), ['1', '2']);
});

test('a TypeScript type annotation between the name and the array does not hide it', () => {
	const src = 'export const BOUNDS_M: readonly number[] = [2000, 5000];';
	assert.deepEqual(parseNumberList(src, 'BOUNDS_M'), ['2000', '5000']);
});

test('a declaration that is not there reads as no values, which the caller reports', () => {
	assert.deepEqual(parseNumberList('const kOther = [1];', 'kWanted'), []);
});

test('the nearby CASE yields its bounds in course order', () => {
	const body = `case
      when ST_Distance(a, b) < 2000  then 0
      when ST_Distance(a, b) < 5000  then 1
      when ST_Distance(a, b) < 25000 then 2
      else 3
    end as bucket`;
	assert.deepEqual(parseNearbyCase(body), ['2000', '5000', '25000']);
});

test('a badge catalogue is read the same way in TypeScript and in Dart', () => {
	const ts = `[
	{ id: 'streak', tiers: [
		{ tier: 'bronze', threshold: 7 },
		{ tier: 'silver', threshold: 30 },
	] },
	{ id: 'pr', tiers: [ { tier: 'bronze', threshold: 1 } ] },
]`;
	const dart = `[
  Badge(id: 'streak', tiers: [
    BadgeTier(tier: 'bronze', threshold: 7),
    BadgeTier(tier: 'silver', threshold: 30),
  ]),
  Badge(id: 'pr', tiers: [BadgeTier(tier: 'bronze', threshold: 1)]),
]`;
	const expected = [
		{ key: 'streak', where: 'streak catalogue entry', values: ['7', '30'] },
		{ key: 'pr', where: 'pr catalogue entry', values: ['1'] },
	];
	assert.deepEqual(parseBadgeCatalogue(ts), expected);
	assert.deepEqual(parseBadgeCatalogue(dart), expected);
});

test('the awarder ladder is keyed by the family the branch selects', () => {
	const body = `select 'streak'::text as badge_key, t.tier
    from (values ('bronze',7,1),('silver',30,2)) as t(tier,thr,rank)
    where v >= t.thr
    union all
    select 'pr', t.tier
    from (values ('bronze',1,1)) as t(tier,thr,rank)`;
	assert.deepEqual(parseAwarderLadders(body), [
		{ key: 'streak', where: 'streak branch', values: ['7', '30'] },
		{ key: 'pr', where: 'pr branch', values: ['1'] },
	]);
});

// ── Comparison: match 'all' ────────────────────────────────────────────────

test('sites carrying the same values in a different order agree under set compare', () => {
	const entry = entryOf(
		[
			{ label: 'sql', sites: [{ key: 'k', where: 'the constraint', values: ['a', 'b'] }] },
			{ label: 'web', sites: [{ key: 'k', where: 'the union', values: ['b', 'a'] }] },
		],
		'all',
		'set',
	);
	assert.deepEqual(checkEntry(entry, NO_CTX).errors, []);
});

test('the same reordering is a failure under ordered compare', () => {
	const entry = entryOf(
		[
			{ label: 'sql', sites: [{ key: 'k', where: 'the CASE', values: ['1', '2'] }] },
			{ label: 'web', sites: [{ key: 'k', where: 'the constant', values: ['2', '1'] }] },
		],
		'all',
		'ordered',
	);
	assert.equal(checkEntry(entry, NO_CTX).errors.length, 1);
});

// The message has to name BOTH homes and the difference between them, because
// a reader who has to go and diff the two files themselves is a reader the
// guard has not helped.
test('a disagreement names both rails, both sites and the missing values', () => {
	const entry = entryOf(
		[
			{ label: 'the column vocabulary', sites: [{ key: 'k', where: 'the constraint', values: ['app', 'watch', 'race'] }] },
			{ label: 'live SQL functions', sites: [{ key: 'k', where: 'legacy_fn() in 20260710_001.sql', values: ['app'] }] },
		],
		'all',
		'set',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /the column vocabulary/);
	assert.match(errors[0], /legacy_fn\(\) in 20260710_001\.sql/);
	assert.match(errors[0], /missing there: watch, race/);
});

test('a value present only on the second rail is reported as such', () => {
	const entry = entryOf(
		[
			{ label: 'a', sites: [{ key: 'k', where: 'a', values: ['app'] }] },
			{ label: 'b', sites: [{ key: 'k', where: 'b', values: ['app', 'ghost'] }] },
		],
		'all',
		'set',
	);
	assert.match(checkEntry(entry, NO_CTX).errors[0], /only there: {4}ghost/);
});

test('every site on a multi-site rail is compared, not just the first', () => {
	const entry = entryOf(
		[
			{ label: 'a', sites: [{ key: 'k', where: 'a', values: ['app'] }] },
			{
				label: 'b',
				sites: [
					{ key: 'k', where: 'fn_ok', values: ['app'] },
					{ key: 'k', where: 'fn_drifted', values: ['app', 'extra'] },
				],
			},
		],
		'all',
		'set',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /fn_drifted/);
});

// ── Comparison: match 'key' ────────────────────────────────────────────────

test('ladders are paired by family, not by position', () => {
	const entry = entryOf(
		[
			{
				label: 'web',
				sites: [
					{ key: 'pr', where: 'pr', values: ['1'] },
					{ key: 'streak', where: 'streak', values: ['7'] },
				],
			},
			{
				label: 'sql',
				sites: [
					{ key: 'streak', where: 'streak', values: ['7'] },
					{ key: 'pr', where: 'pr', values: ['1'] },
				],
			},
		],
		'key',
		'ordered',
	);
	assert.deepEqual(checkEntry(entry, NO_CTX).errors, []);
});

// A badge family a client renders but the awarder never inserts is a badge
// nobody can earn; the reverse is one no surface explains. Both are a key
// present on one rail only.
test('a family present on one rail only is reported by name', () => {
	const entry = entryOf(
		[
			{ label: 'web', sites: [{ key: 'vert', where: 'vert', values: ['500'] }] },
			{ label: 'sql', sites: [{ key: 'pr', where: 'pr', values: ['1'] }] },
		],
		'key',
		'ordered',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 2);
	assert.match(errors.join('\n'), /"vert" is written on 1 of 2 rails — missing from sql/);
	assert.match(errors.join('\n'), /"pr" is written on 1 of 2 rails — missing from web/);
});

test('a threshold that differs inside a matched family is reported with both ladders', () => {
	const entry = entryOf(
		[
			{ label: 'web', sites: [{ key: 'streak', where: 'catalogue', values: ['7', '30', '100'] }] },
			{ label: 'sql', sites: [{ key: 'streak', where: 'awarder', values: ['7', '30', '90'] }] },
		],
		'key',
		'ordered',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /7, 30, 100/);
	assert.match(errors[0], /7, 30, 90/);
});

// ── Anti-vacuity ───────────────────────────────────────────────────────────

test('a rail that finds no sites is an error, not an agreement', () => {
	const entry = entryOf(
		[
			{ label: 'web', sites: [{ key: 'k', where: 'w', values: ['a'] }] },
			{ label: 'sql', sites: [] },
		],
		'all',
		'set',
	);
	assert.match(checkEntry(entry, NO_CTX).errors[0], /rail "sql" produced no sites/);
});

test('a site whose extractor read no values is an error, not an agreement', () => {
	const entry = entryOf(
		[
			{ label: 'web', sites: [{ key: 'k', where: 'the constant', values: [] }] },
			{ label: 'sql', sites: [{ key: 'k', where: 'the CASE', values: [] }] },
		],
		'all',
		'ordered',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 2);
	assert.match(errors[0], /read no values at the constant/);
});

test('two rails that both read nothing do not certify each other', () => {
	const entry = entryOf([{ label: 'a', sites: [] }, { label: 'b', sites: [] }], 'all', 'set');
	assert.equal(checkEntry(entry, NO_CTX).errors.length, 2);
});

// ── The real registry against the real tree ────────────────────────────────

test('every registered entry has at least two rails and a stated cost', () => {
	assert.ok(REGISTRY.length > 0);
	for (const entry of REGISTRY) {
		assert.ok(entry.rails.length >= 2, `${entry.name} needs more than one home to be a shared constant`);
		assert.ok(entry.why.length > 40, `${entry.name} must say what a drift costs`);
	}
});

test('the committed tree agrees on every registered shared constant', () => {
	const { errors, ok } = check(REGISTRY, defaultContext());
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= REGISTRY.length);
});

// The regression this guard was built from, replayed: a live function whose
// run-source filter is the pre-#378 list while the constraint carries the full
// vocabulary. It is the fixture and not the tree because the tree is fixed.
test('a run-source filter that missed a widening is caught in the real entry shape', () => {
	const dir = migrationsFixture({
		'20260505_001_check.sql':
			"alter table runs add constraint runs_source_check check (source in ('app','watch','parkrun'));",
		'20260710_001_hardening.sql':
			"create or replace function personal_records() returns int language sql as $$ select 1 from runs where source in ('app'); $$;",
	});
	const entry = /** @type {any} */ (REGISTRY.find((e) => e.name.startsWith('runs.source')));
	const { errors } = checkEntry(entry, { read: () => '', sql: indexMigrations(dir) });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /runs_source_check/);
	assert.match(errors[0], /personal_records\(\) in 20260710_001_hardening\.sql/);
	assert.match(errors[0], /missing there: watch, parkrun/);
});
