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
	bucketMimeSites,
	callArguments,
	check,
	checkEntry,
	columnBoundSites,
	defaultContext,
	indexMigrations,
	limitRegistrySites,
	parseAwarderLadders,
	parseBadgeCatalogue,
	parseCaseFoldMap,
	parseCharClassCodePoints,
	parseColumnBounds,
	parseMinettiCoefficients,
	parseNamedCharClass,
	parseNamedInt,
	parseNearbyCase,
	parseNumberList,
	parseProseThresholds,
	parseStringList,
	parseWearOffRoute,
	resolveNumber,
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

// ── Numeric column bounds ──────────────────────────────────────────────────

// The whole point of resolving an exclusive bound through the column's scale:
// `> 0` on a two-decimal column admits 0.01 and on an int admits 1, and a form
// that offers "0" for either offers the one value the CHECK rejects.
test('an exclusive bound resolves to the neighbouring value the column can hold', () => {
	assert.deepEqual(parseColumnBounds('weight_kg > 0 and weight_kg <= 500', 'weight_kg', 0.01), ['0.01', '500']);
	assert.deepEqual(parseColumnBounds('rest_s >= 0 and rest_s <= 3600', 'rest_s', 1), ['0', '3600']);
	assert.deepEqual(parseColumnBounds('reps > 0 and reps < 100', 'reps', 1), ['1', '99']);
});

test('a between reads as its two inclusive bounds', () => {
	assert.deepEqual(parseColumnBounds('body_weight_kg between 20 and 400', 'body_weight_kg', 0.01), ['20', '400']);
});

test('a bound open at either end is not a bound this guard can state', () => {
	assert.deepEqual(parseColumnBounds('quantity >= 0', 'quantity', 0.01), []);
	assert.deepEqual(parseColumnBounds('servings <= 10', 'servings', 0.1), []);
});

test('the tightest bound in the CHECK wins when it names several', () => {
	assert.deepEqual(parseColumnBounds('x >= 0 and x >= 5 and x <= 90 and x <= 100', 'x', 1), ['5', '90']);
});

// The replay: a bound tightened by a later `alter table` is the one in force,
// and the file that tightens it is routinely named after something else.
test('a column bound is the last statement that set it, not the first', () => {
	const dir = migrationsFixture({
		'20260101_001_create.sql':
			'create table public.body_metrics (\n  weight_kg numeric(5, 2) not null check (weight_kg > 0 and weight_kg <= 500)\n);\n' +
			'create or replace function f() returns int language sql as $$ select 1; $$;',
		'20260102_001_unrelated_hardening.sql':
			'alter table body_metrics add column weight_kg numeric(5, 2) check (weight_kg > 0 and weight_kg <= 400);',
	});
	assert.deepEqual(columnBoundSites(indexMigrations(dir), 'body_metrics.weight_kg'), [
		{
			key: 'body_metrics.weight_kg',
			where: 'body_metrics.weight_kg in 20260102_001_unrelated_hardening.sql',
			values: ['0.01', '400'],
		},
	]);
});

// The parse fell into exactly this hole once: a `\b` after the type alternation
// cannot follow the `)` of `numeric(5, 2)`, so the match backtracked to a bare
// `numeric`, the scale was lost, and `> 0` resolved to 1 rather than 0.01.
test('a parenthesised numeric type keeps its scale', () => {
	const dir = migrationsFixture({
		'20260101_001_create.sql':
			'create table public.t (\n  v numeric(5, 2) not null check (v > 0 and v <= 9)\n);\n' +
			'create or replace function f() returns int language sql as $$ select 1; $$;',
	});
	assert.deepEqual(columnBoundSites(indexMigrations(dir), 't.v')[0].values, ['0.01', '9']);
});

test('a column no migration bounds produces no site, which the caller reports', () => {
	const dir = migrationsFixture({
		'20260101_001_a.sql': 'create or replace function f() returns int language sql as $$ select 1; $$;',
	});
	assert.deepEqual(columnBoundSites(indexMigrations(dir), 'body_metrics.weight_kg'), []);
});

test('a client registry is keyed by the column it names, not by its own key', () => {
	const ts =
		"export const NUMERIC_LIMITS = {\n\tbodyMetricsWeightKg: { min: 0.01, max: 500 }\n} as const;\n" +
		"export const NUMERIC_LIMIT_COLUMNS = {\n\tbodyMetricsWeightKg: 'body_metrics.weight_kg'\n};\n";
	assert.deepEqual(
		limitRegistrySites(ts, /\b([A-Za-z0-9]+):\s*\{\s*min:\s*(-?[\d.]+),\s*max:\s*(-?[\d.]+)\s*\}/g, /\b([A-Za-z0-9]+):\s*'([a-z_]+\.[a-z_]+)'/g),
		[{ key: 'body_metrics.weight_kg', where: 'bodyMetricsWeightKg (body_metrics.weight_kg)', values: ['0.01', '500'] }],
	);
});

// ── Rate-limit thresholds in prose ─────────────────────────────────────────

test('a threshold quoted in prose is read in the order it is written', () => {
	assert.deepEqual(parseProseThresholds('a 30/60 s burst and a 250/3600 s hour cap'), ['30/60', '250/3600']);
	assert.deepEqual(parseProseThresholds('no figures here'), []);
});

// ── Comparison: match 'all' ────────────────────────────────────────────────

test('a character class reads as code points however its language spells them', () => {
	// The same class in the three languages it is written in: a JS regex
	// literal, a Dart string (doubled backslashes), and SQL chr() concatenation.
	const expected = [9, 10, 32, 0x85, 0xa0];
	assert.deepEqual(parseCharClassCodePoints('\\t\\n \\u0085\\u00a0'), expected);
	assert.deepEqual(parseCharClassCodePoints('\\\\t\\\\n \\\\u0085\\\\u00a0'), expected);
	assert.deepEqual(
		parseCharClassCodePoints(
			"chr(9) || chr(10) || chr(32)\n          || chr(133) || chr(160)",
			{ sql: true },
		),
		expected,
	);
});

test('a range expands to every code point it covers, in every spelling', () => {
	assert.deepEqual(parseCharClassCodePoints('\\u2000-\\u2003'), [0x2000, 0x2001, 0x2002, 0x2003]);
	assert.deepEqual(
		parseCharClassCodePoints("chr(8192) || '-' || chr(8195)", { sql: true }),
		[0x2000, 0x2001, 0x2002, 0x2003],
	);
});

test('a SQL class keeps no space of its own, a JS one keeps the space it names', () => {
	// The whitespace between SQL concatenation operands is punctuation; the
	// space inside a JS class is a member. Reading them the same way put 80
	// spurious U+0020s in the SQL rail and made the two disagree.
	assert.deepEqual(parseCharClassCodePoints("chr(9)   ||   chr(10)", { sql: true }), [9, 10]);
	assert.deepEqual(parseCharClassCodePoints('\\t \\n'), [9, 32, 10]);
});

test('a class is read from its declaration, not from a doc comment naming it', () => {
	const src =
		'/// Every step is spelled out; see EXERCISE_WS below.\n' +
		'const EXERCISE_WS = /[\\t\\n \\u00a0]+/g;\n';
	assert.deepEqual(parseNamedCharClass(src, 'EXERCISE_WS'), ['0009', '000a', '0020', '00a0']);
});

test('a case-fold table reads as from>to pairs on both clients', () => {
	const ts =
		"const EXERCISE_CASE_FOLD = /[\\u0130]/g;\n" +
		"const EXERCISE_CASE_MAP: Record<string, string> = {\n\t'\\u0130': 'i',\n\t'\\u01c5': '\\u01c6'\n};\n";
	const dart =
		"const Map<String, String> kExerciseCaseMap = {\n  '\\u0130': 'i',\n  '\\u01c5': '\\u01c6',\n};\n";
	assert.deepEqual(parseCaseFoldMap(ts, 'EXERCISE_CASE_MAP'), ['0130>0069', '01c5>01c6']);
	assert.deepEqual(parseCaseFoldMap(dart, 'kExerciseCaseMap'), ['0130>0069', '01c5>01c6']);
});

test('a call is split on its top-level commas, not on the ones inside its arguments', () => {
	const body = "select translate(collapse(p_name, 'x'), chr(304) || chr(453), chr(105) || chr(454));";
	assert.deepEqual(callArguments(body, 'translate'), [
		"collapse(p_name, 'x')",
		' chr(304) || chr(453)',
		' chr(105) || chr(454)',
	]);
});

test('the exercise normalisation entries agree across SQL, web and mobile', () => {
	// Reads the real rails, so a class or a fold that drifts on one platform
	// fails here rather than silently re-keying a lifter's stored history.
	const ctx = defaultContext();
	for (const name of ['exercise-name whitespace class', 'exercise-name case folds']) {
		const entry = /** @type {import('./check_shared_constants.mjs').Entry} */ (
			REGISTRY.find((e) => e.name === name)
		);
		assert.ok(entry, `${name} is registered`);
		const { errors } = checkEntry(entry, ctx);
		assert.deepEqual(errors, []);
	}
});

test('a SQL function that rolls its own exercise-name class is reported, not ignored', () => {
	// The failure this entry exists to catch a SECOND time: a new RPC that
	// inlines `regexp_replace(lower(btrim(exercise_name)), '\s+', ' ', 'g')`
	// instead of calling normalise_exercise_name(). `\s` names no code point,
	// so the rail reads no values and the guard says it has gone blind there.
	const entry = /** @type {import('./check_shared_constants.mjs').Entry} */ (
		REGISTRY.find((e) => e.name === 'exercise-name whitespace class')
	);
	const real = defaultContext();
	const live = new Map(real.sql.live);
	live.set('gym_rogue_rpc', {
		file: '20990101_001_rogue.sql',
		sql: "create function gym_rogue_rpc() returns text language sql as $$ select regexp_replace(lower(btrim(s.exercise_name)), '\\s+', ' ', 'g') from gym_sets s $$;",
	});
	const { errors } = checkEntry(entry, { read: real.read, sql: { live, statements: real.sql.statements } });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /gym_rogue_rpc\(\)/);
	assert.match(errors[0], /read no values/);
});

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

test('resolveNumber reads a literal and resolves a derived one', () => {
	const src = [
		'pub const OFF_COURSE_THRESHOLD_M: f64 = 40.0;',
		'pub const OFF_COURSE_REARM_M: f64 = OFF_COURSE_THRESHOLD_M / 2.0;',
	].join('\n');
	assert.equal(resolveNumber(src, 'OFF_COURSE_THRESHOLD_M'), 40);
	assert.equal(resolveNumber(src, 'OFF_COURSE_REARM_M'), 20);
	// A threshold change carries the derived half with it, which is precisely
	// what the hand-written rail cannot do.
	const moved = src.replace('= 40.0', '= 50.0');
	assert.equal(resolveNumber(moved, 'OFF_COURSE_REARM_M'), 25);
	assert.equal(resolveNumber(src, 'NOT_DECLARED'), null);
});

test('parseWearOffRoute reads the comparisons, not the comment above them', () => {
	const src = [
		'    // Off-route hysteresis: alert above 40 m, clear below 20 m.',
		'    val currentlyOffRoute = offRouteDistanceM != null && offRouteDistanceM > 55',
		'    val backOnRoute = offRouteDistanceM != null && offRouteDistanceM < 25',
	].join('\n');
	assert.deepEqual(parseWearOffRoute(src), ['55', '25']);
	assert.deepEqual(parseWearOffRoute('nothing here'), []);
});

test('parseMinettiCoefficients keeps signs and ignores the i5..i2 identifiers', () => {
	const dart = [
		'  final i2 = i * i;',
		'  final i5 = i4 * i;',
		'  return 155.4 * i5 - 30.4 * i4 - 43.3 * i3 + 46.3 * i2 + 19.5 * i + 3.6;',
	].join('\n');
	assert.deepEqual(parseMinettiCoefficients(dart), [
		'155.4',
		'-30.4',
		'-43.3',
		'46.3',
		'19.5',
		'3.6',
	]);
	// Rust writes the same expression as a trailing value, no `return`, no `;`.
	const rust = dart
		.replace('  return ', '    ')
		.replace('+ 3.6;', '+ 3.6');
	assert.deepEqual(parseMinettiCoefficients(rust), parseMinettiCoefficients(dart));
	assert.deepEqual(parseMinettiCoefficients('nothing here'), []);
});
