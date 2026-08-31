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
	MOBILE_COLUMN_LIMITS,
	RATE_LIMIT_DOC,
	REGISTRY,
	WEB_COLUMN_LIMITS,
	boundFromCheck,
	bucketMimeSites,
	check,
	checkColumnBounds,
	checkEntry,
	defaultContext,
	indexMigrations,
	numericCeiling,
	parseColumnLimits,
	rateLimitCeilingDocSites,
	rateLimitCeilingSqlSites,
	sqlColumnBound,
	parseAwarderLadders,
	parseBadgeCatalogue,
	parseNamedInt,
	parseNearbyCase,
	parseNumberList,
	parseStringList,
	parseGuidedRunLibrary,
	parseGuidedSeconds,
	parseWhitespaceClass,
	MOBILE_GUIDED_RUNS,
	WEB_GUIDED_RUNS,
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

test('a Dart list written with an explicit type argument is read like the TS one', () => {
	const ts = "export const MIME: readonly string[] = ['image/jpeg', 'image/png'];";
	const dart = "const List<String> kMime = <String>[\n  'image/jpeg',\n  'image/png',\n];";
	assert.deepEqual(parseStringList(ts, 'MIME'), ['image/jpeg', 'image/png']);
	assert.deepEqual(parseStringList(dart, 'kMime'), ['image/jpeg', 'image/png']);
});

// The class has three spellings - a JS regex literal, a Dart RegExp source
// string (backslashes doubled), and a Postgres ARE inside a SQL literal - and
// the registered value is the SET OF CODE POINTS behind them. Reading all
// three with one parser is what makes "the three rails agree" a property of
// the parse rather than of three regexes that could drift the way their
// subjects can.
test('the exercise whitespace class is read the same way from JS, Dart and SQL', () => {
	const ts = 'const EXERCISE_WS =\n\t/[\\u0009-\\u000b\\u00a0]+/g;';
	const dart = "final RegExp kExerciseWhitespace = RegExp(\n  '[\\\\u0009-\\\\u000b\\\\u00a0]+',\n);";
	const sql = "as $$ select btrim(regexp_replace(lower(p_name), '[\\u0009-\\u000b\\u00a0]+', ' ', 'g'), ' '); $$";
	const expected = ['U+0009', 'U+000A', 'U+000B', 'U+00A0'];
	assert.deepEqual(parseWhitespaceClass(ts, 'EXERCISE_WS ='), expected);
	assert.deepEqual(parseWhitespaceClass(dart, 'kExerciseWhitespace ='), expected);
	assert.deepEqual(parseWhitespaceClass(sql, 'regexp_replace'), expected);
});

// A range and the code points it covers are the same set. If the parser
// compared spellings, rewriting one rail's range as separate escapes would
// read as a disagreement and a rail quietly dropping a code point out of a
// range would not.
test('a range expands, so two spellings of one set compare equal', () => {
	const ranged = '/[\\u2000-\\u2003]+/g';
	const spelled = '/[\\u2000\\u2001\\u2002\\u2003]+/g';
	assert.deepEqual(parseWhitespaceClass(ranged, '/['), parseWhitespaceClass(spelled, '/['));
	assert.deepEqual(parseWhitespaceClass(ranged, '/['), ['U+2000', 'U+2001', 'U+2002', 'U+2003']);
});

test('a whitespace class whose anchor moved reads as no values, which the caller reports', () => {
	assert.deepEqual(parseWhitespaceClass('/[\\u0009]+/g', 'RENAMED ='), []);
	assert.deepEqual(parseWhitespaceClass('const RENAMED = 3;', 'RENAMED ='), []);
});

test('a named integer is read from its declaration in Dart and in Kotlin', () => {
	assert.deepEqual(parseNamedInt('  static const kMaxRoutesPerPush = 30;', 'kMaxRoutesPerPush'), ['30']);
	assert.deepEqual(parseNamedInt('        const val MAX_ROUTES = 30', 'MAX_ROUTES'), ['30']);
	assert.deepEqual(parseNamedInt('const val OTHER = 30', 'MAX_ROUTES'), []);
});

// A bucket's allowlist is created by an insert and narrowed by a later update,
// so reading the creating migration alone reports the value the bucket had
// before the narrowing — which is the drift, not the state.
test('a bucket allowlist is the last statement that set it, not the first', () => {
	const dir = migrationsFixture({
		'20260101_001_create.sql':
			"insert into storage.buckets (id, name, allowed_mime_types) values ('run-photos', 'run-photos', array['image/jpeg', 'image/heic']);\n" +
			'create or replace function f() returns int language sql as $$ select 1; $$;',
		'20260102_001_narrow.sql':
			"update storage.buckets set allowed_mime_types = array['image/jpeg'] where id in ('run-photos');",
	});
	assert.deepEqual(bucketMimeSites(indexMigrations(dir), ['run-photos']), [
		{ key: 'run-photos', where: 'run-photos in 20260102_001_narrow.sql', values: ['image/jpeg'] },
	]);
});

test('a bucket nothing ever set produces no site, which the caller reports', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql': 'create or replace function f() returns int language sql as $$ select 1; $$;',
	});
	assert.deepEqual(bucketMimeSites(indexMigrations(dir), ['run-photos']), []);
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

// ── Column bounds: a client input against the column's own CHECK ───────────

test('one extractor reads the bound out of both languages', () => {
	const ts = parseColumnLimits(
		"'body_metrics.weight_kg': { kind: 'value', min: 20, max: 250 },\n" +
			"'club_posts.body': { kind: 'length', max: 1200 },",
	);
	const dart = parseColumnLimits(
		"'body_metrics.weight_kg': ColumnLimit.value(20, 250),\n" +
			"'club_posts.body': ColumnLimit.length(1200),",
	);
	assert.deepEqual([...ts.entries()], [...dart.entries()]);
	assert.deepEqual(ts.get('body_metrics.weight_kg'), { kind: 'value', values: [20, 250] });
	assert.deepEqual(ts.get('club_posts.body'), { kind: 'length', values: [1200] });
});

test('boundFromCheck reads every form the migrations write a bound in', () => {
	assert.deepEqual(boundFromCheck('weight_kg > 0 and weight_kg <= 500', 'weight_kg'), {
		min: 0,
		minExclusive: true,
		max: 500,
		maxExclusive: false,
		lengthMax: null,
	});
	assert.deepEqual(
		boundFromCheck('body_weight_kg is null or body_weight_kg between 20 and 400', 'body_weight_kg'),
		{ min: 20, minExclusive: false, max: 400, maxExclusive: false, lengthMax: null },
	);
	assert.equal(boundFromCheck('description is null or char_length(description) <= 2000', 'description').lengthMax, 2000);
	// A bound on a DIFFERENT column in the same body is not this column's.
	assert.deepEqual(boundFromCheck('reps >= 0 and rpe <= 10', 'reps'), {
		min: 0,
		minExclusive: false,
		max: null,
		maxExclusive: false,
		lengthMax: null,
	});
});

test('numericCeiling is the largest magnitude the declaration can hold', () => {
	assert.equal(numericCeiling(5, 2), 999.99);
	assert.equal(numericCeiling(5, 1), 9999.9);
});

test('a column bound is the intersection of every live CHECK, and a drop removes one', () => {
	const dir = migrationsFixture({
		'0001_create.sql': 'create table body_metrics (weight_kg numeric(5, 2) not null check (weight_kg > 0));',
		'0002_cap.sql': 'alter table body_metrics add constraint bm_cap check (weight_kg <= 500);',
		'0003_tighter.sql': 'alter table body_metrics add constraint bm_tight check (weight_kg <= 300);',
	});
	const sql = indexMigrations2(dir);
	assert.equal(sqlColumnBound(sql, 'body_metrics', 'weight_kg').max, 300);
	const dropped = indexMigrations2(
		migrationsFixture({
			'0001_create.sql': 'create table body_metrics (weight_kg numeric(5, 2) not null check (weight_kg > 0));',
			'0002_cap.sql': 'alter table body_metrics add constraint bm_cap check (weight_kg <= 300);',
			'0003_drop.sql': 'alter table body_metrics drop constraint bm_cap;',
		}),
	);
	// With the cap gone the only ceiling left is what numeric(5, 2) can hold.
	assert.equal(sqlColumnBound(dropped, 'body_metrics', 'weight_kg').max, 999.99);
});

/**
 * indexMigrations needs a function to exist; these fixtures are DDL only.
 * @param {string} dir
 */
function indexMigrations2(dir) {
	writeFileSync(join(dir, '9999_fn.sql'), 'create function noop() returns int language sql as $$ select 1 $$;');
	return indexMigrations(dir);
}

/**
 * The committed clients, with one entry rewritten.
 * @param {(rel: string, src: string) => string} mutate
 * @returns {any}
 */
function boundsCtx(mutate) {
	const real = defaultContext();
	return {
		sql: real.sql,
		read: (/** @type {string} */ rel) => mutate(rel, real.read(rel)),
	};
}

test('the committed clients bound every registered column inside its own CHECK', () => {
	const { errors, ok } = checkColumnBounds(defaultContext());
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= 8);
});

test('MUTATION: a client cap raised above the column CHECK fails', () => {
	const { errors } = checkColumnBounds(
		boundsCtx((rel, src) =>
			rel === WEB_COLUMN_LIMITS || rel === MOBILE_COLUMN_LIMITS ? src.replace(/\b1200\b/g, '9999') : src,
		),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /club_posts\.body/);
	assert.match(errors[0], /capped ABOVE its own CHECK/);
});

test('MUTATION: a value range that leaves the column CHECK fails at either end', () => {
	const above = checkColumnBounds(
		boundsCtx((rel, src) =>
			rel === WEB_COLUMN_LIMITS || rel === MOBILE_COLUMN_LIMITS
				? src.replace(/(weight_kg'[^\n]*?)\b250\b/g, '$1600')
				: src,
		),
	);
	assert.equal(above.errors.length, 1);
	assert.match(above.errors[0], /body_metrics\.weight_kg/);
	assert.match(above.errors[0], /max 600 is not <= the database's 500/);

	// The exclusive `> 0` half: a client floor of 0 is admitted by the client
	// and rejected by the column, which is what `min="0"` did on the web.
	const below = checkColumnBounds(
		boundsCtx((rel, src) =>
			rel === WEB_COLUMN_LIMITS || rel === MOBILE_COLUMN_LIMITS
				? src.replace(/(height_cm'[^\n]*?)\b50\b/g, '$10')
				: src,
		),
	);
	assert.equal(below.errors.length, 1);
	assert.match(below.errors[0], /user_profiles\.height_cm/);
	assert.match(below.errors[0], /min 0 is not > the database's 0/);
});

test('MUTATION: the two clients disagreeing on one field fails, naming both', () => {
	const { errors } = checkColumnBounds(
		boundsCtx((rel, src) => (rel === MOBILE_COLUMN_LIMITS ? src.replace("ColumnLimit.length(32)", 'ColumnLimit.length(20)') : src)),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /user_profiles\.parkrun_number/);
	assert.match(errors[0], /web:\s+length \[32\]/);
	assert.match(errors[0], /mobile:\s+length \[20\]/);
});

test('MUTATION: a field bounded on one client only fails', () => {
	const { errors } = checkColumnBounds(
		boundsCtx((rel, src) =>
			rel === MOBILE_COLUMN_LIMITS ? src.replace(/'recipes\.servings':[^\n]*\n/, '') : src,
		),
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /recipes\.servings/);
	assert.match(errors[0], /bounded on web only/);
});

test('a client module the extractor can no longer read is reported as blindness', () => {
	const { errors } = checkColumnBounds(boundsCtx((rel, src) => (rel === WEB_COLUMN_LIMITS ? '' : src)));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /guard going blind/);
});

// ── Rate-limit ceilings ────────────────────────────────────────────────────

test('one bucket debited with two different ceilings throws rather than picking one', () => {
	const dir = migrationsFixture({
		'0001_a.sql':
			"create function a() returns void language plpgsql as $$ begin perform enforce_create_rate_limit('create_club', x, 5, 3600); end $$;",
		'0002_b.sql':
			"create function b() returns void language plpgsql as $$ begin perform enforce_create_rate_limit('create_club', x, 50, 3600); end $$;",
	});
	assert.throws(
		() => rateLimitCeilingSqlSites({ read: () => '', sql: indexMigrations(dir) }),
		/two ceilings/,
	);
});

test('a re-issued function replaces its own ceiling rather than conflicting with it', () => {
	const dir = migrationsFixture({
		'0001_a.sql':
			"create function a() returns void language plpgsql as $$ begin perform enforce_create_rate_limit('create_club', x, 5, 3600); end $$;",
		'0002_a.sql':
			"create or replace function a() returns void language plpgsql as $$ begin perform enforce_create_rate_limit('create_club', x, 9, 3600); end $$;",
	});
	const sites = rateLimitCeilingSqlSites({ read: () => '', sql: indexMigrations(dir) });
	assert.deepEqual(sites, [{ key: 'create_club', where: 'a() in 0002_a.sql', values: ['9', '3600'] }]);
});

test('the doc table row is read off the backticked bucket, not the first numbers on the line', () => {
	const sites = rateLimitCeilingDocSites({
		read: () => '| Bucket | Max | Window |\n|---|---|---|\n| `create_club` | 5 | 3600 | see 20260907_001 |\n',
		sql: /** @type {any} */ ({}),
	});
	assert.deepEqual(sites, [
		{ key: 'create_club', where: `${RATE_LIMIT_DOC} bucket table`, values: ['5', '3600'] },
	]);
});

test('MUTATION: the doc table stating a ceiling the SQL does not enforce fails', () => {
	const entry = /** @type {any} */ (REGISTRY.find((e) => e.name === 'create rate-limit ceilings'));
	const real = defaultContext();
	const { errors } = checkEntry(entry, {
		sql: real.sql,
		read: (/** @type {string} */ rel) =>
			rel === RATE_LIMIT_DOC
				? real.read(rel).replace('| `send_direct_message_burst` | 30 | 60 |', '| `send_direct_message_burst` | 60 | 60 |')
				: real.read(rel),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /send_direct_message_burst/);
	assert.match(errors[0], /\[30, 60\]/);
	assert.match(errors[0], /\[60, 60\]/);
});

test('MUTATION: a bucket the SQL raises and the doc table omits fails', () => {
	const entry = /** @type {any} */ (REGISTRY.find((e) => e.name === 'create rate-limit ceilings'));
	const real = defaultContext();
	const { errors } = checkEntry(entry, {
		sql: real.sql,
		read: (/** @type {string} */ rel) =>
			rel === RATE_LIMIT_DOC ? real.read(rel).replace(/^\| `create_club` \|.*$/m, '') : real.read(rel),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"create_club" is written on 1 of 2 rails/);
});

// ── The guided-run cue library ─────────────────────────────────────────────

const GUIDED_ANCHOR_TS = 'guidedRunLibrary(t: GuidedTranslate';
const GUIDED_ANCHOR_DART = 'guidedRunLibrary(AppLocalizations';

const GUIDED_TS = `
export function guidedRunLibrary(t: GuidedTranslate): GuidedRun[] {
	return [
		{
			id: 'easy-30',
			title: t('guidedRuns.easy30.title'),
			duration_sec: 30 * 60,
			cues: [
				{ at_sec: 0, text: t('guidedRuns.easy30.cue0') },
				{ at_sec: 5 * 60, text: t('guidedRuns.easy30.cue1') },
			],
		},
		{
			id: 'brisk-10',
			title: t('guidedRuns.brisk10.title'),
			duration_sec: 600,
			cues: [{ at_sec: 0, text: t('guidedRuns.brisk10.cue0') }],
		},
	];
}
`;

const GUIDED_DART = `
List<GuidedRun> guidedRunLibrary(AppLocalizations l10n) => [
      GuidedRun(
        id: 'easy-30',
        title: l10n.guidedEasy30Title,
        durationSec: 30 * 60,
        cues: [
          GuidedCue(atSec: 0, text: l10n.guidedEasy30Cue0),
          GuidedCue(atSec: 5 * 60, text: l10n.guidedEasy30Cue1),
        ],
      ),
      GuidedRun(
        id: 'brisk-10',
        title: l10n.guidedBrisk10Title,
        durationSec: 600,
        cues: [GuidedCue(atSec: 0, text: l10n.guidedBrisk10Cue0)],
      ),
    ];
`;

// The same two workouts, listed the other way round. Nothing about either run
// changes — which is the point: a set comparison would call this agreement.
const GUIDED_DART_REORDERED = `
List<GuidedRun> guidedRunLibrary(AppLocalizations l10n) => [
      GuidedRun(
        id: 'brisk-10',
        durationSec: 600,
        cues: [GuidedCue(atSec: 0, text: l10n.guidedBrisk10Cue0)],
      ),
      GuidedRun(
        id: 'easy-30',
        durationSec: 30 * 60,
        cues: [
          GuidedCue(atSec: 0, text: l10n.guidedEasy30Cue0),
          GuidedCue(atSec: 5 * 60, text: l10n.guidedEasy30Cue1),
        ],
      ),
    ];
`;

// Two languages, one parse. Comparing the two outputs directly is what makes
// "web and mobile agree" a property of the extractor rather than of two
// regexes that could drift the way their subjects can.
test('one extractor reads the TypeScript and the Dart spelling of the same library', () => {
	const ts = parseGuidedRunLibrary(GUIDED_TS, GUIDED_ANCHOR_TS, 'lib');
	const dart = parseGuidedRunLibrary(GUIDED_DART, GUIDED_ANCHOR_DART, 'lib');
	assert.deepEqual(ts, dart);
	assert.deepEqual(ts, [
		{ key: 'library order', where: 'run ids in lib', values: ['easy-30', 'brisk-10'] },
		{ key: 'easy-30', where: 'easy-30 in lib', values: ['duration=1800', 'cue@0', 'cue@300'] },
		{ key: 'brisk-10', where: 'brisk-10 in lib', values: ['duration=600', 'cue@0'] },
	]);
});

test('a second mark is evaluated from minutes, and a bare integer is taken as seconds', () => {
	assert.equal(parseGuidedSeconds('29 * 60', 'w'), 1740);
	assert.equal(parseGuidedSeconds(' 0 ', 'w'), 0);
	assert.equal(parseGuidedSeconds('600', 'w'), 600);
});

// Skipping an unreadable mark would shorten one rail's cue list, which the
// other rail cannot see and the comparison would read as the run it knows.
test('a second mark in a form the parser does not know throws rather than being skipped', () => {
	assert.throws(() => parseGuidedSeconds('const Duration(minutes: 5).inSeconds', 'easy-30 in lib'), /easy-30 in lib/);
	assert.throws(() => parseGuidedSeconds('5 * 60 + 30', 'w'), /teach it the new form/);
});

test('a library whose anchor is gone throws rather than reading nothing', () => {
	assert.throws(() => parseGuidedRunLibrary(GUIDED_TS, 'buildGuidedRuns(', 'lib'), /agrees with every other one/);
});

test('a run carrying no cue marks throws — a cue-less run matches a cue-less run', () => {
	const cueless = GUIDED_DART.replace(/cues: \[GuidedCue\(atSec: 0, text: l10n\.guidedBrisk10Cue0\)\],/, 'cues: [],');
	assert.throws(() => parseGuidedRunLibrary(cueless, GUIDED_ANCHOR_DART, 'lib'), /"brisk-10".*no cue marks/s);
});

test('a run carrying no duration throws', () => {
	const undated = GUIDED_TS.replace('duration_sec: 600,', '');
	assert.throws(() => parseGuidedRunLibrary(undated, GUIDED_ANCHOR_TS, 'lib'), /"brisk-10".*no duration/s);
});

test('a parse that yields fewer runs than a library holds throws', () => {
	const oneRun = GUIDED_TS.slice(0, GUIDED_TS.indexOf("id: 'brisk-10'")) + '];\n}\n';
	assert.throws(() => parseGuidedRunLibrary(oneRun, GUIDED_ANCHOR_TS, 'lib'), /read 1 guided run\(s\)/);
});

test('MUTATION: two rails holding the same runs in a different order fail on the order', () => {
	const entry = entryOf(
		[
			{ label: 'web', sites: parseGuidedRunLibrary(GUIDED_TS, GUIDED_ANCHOR_TS, 'web') },
			{ label: 'mobile', sites: parseGuidedRunLibrary(GUIDED_DART_REORDERED, GUIDED_ANCHOR_DART, 'mobile') },
		],
		'key',
		'ordered',
	);
	const { errors } = checkEntry(entry, NO_CTX);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"library order" disagrees/);
});

test('MUTATION: a cue mark moved on the phone alone fails, naming the run', () => {
	const entry = /** @type {any} */ (REGISTRY.find((e) => e.name === 'guided-run cue library'));
	const real = defaultContext();
	const { errors } = checkEntry(entry, {
		sql: real.sql,
		read: (/** @type {string} */ rel) =>
			rel === MOBILE_GUIDED_RUNS
				? real.read(rel).replace('GuidedCue(atSec: 25 * 60,', 'GuidedCue(atSec: 26 * 60,')
				: real.read(rel),
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /"easy-30" disagrees/);
	assert.match(errors[0], /cue@1500/);
	assert.match(errors[0], /cue@1560/);
});

test('MUTATION: a workout renamed on the web alone fails as a key missing from each rail in turn', () => {
	const entry = /** @type {any} */ (REGISTRY.find((e) => e.name === 'guided-run cue library'));
	const real = defaultContext();
	const { errors } = checkEntry(entry, {
		sql: real.sql,
		read: (/** @type {string} */ rel) =>
			rel === WEB_GUIDED_RUNS ? real.read(rel).replace("id: 'first-timer-15',", "id: 'first-timer-15-v2',") : real.read(rel),
	});
	assert.match(errors.join('\n'), /"first-timer-15" is written on 1 of 2 rails/);
	assert.match(errors.join('\n'), /"first-timer-15-v2" is written on 1 of 2 rails/);
	assert.match(errors.join('\n'), /"library order" disagrees/);
});
