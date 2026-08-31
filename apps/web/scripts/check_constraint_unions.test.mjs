// Unit tests for the CHECK-constraint ↔ client-vocabulary guard.
//
// The committed-tree cases at the bottom read the real migrations, the real
// generated row types and the real client sources, so a genuine drift fails
// them as well as the guard itself — which is why CI runs the guard first and
// this suite second (decisions § 774).
//
// The coverage case asserts EQUALITY, both directions. It used to assert
// `checks.size >= PAIRS.length`, which is satisfied by a registry covering
// half the columns — and was, for 26 of them (decisions § 787 found the same
// shape of hole one guard over; § 791 closed this one).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { join } from 'node:path';

import {
	PAIRS,
	REPO_ROOT,
	SHAPES,
	TYPES_FILE,
	audit,
	extractClientValues,
	findInitializers,
	loadAllMigrationChecks,
	loadLiveColumns,
	parseChecks,
	parseLiveColumns,
	parseTsUnion,
	topLevelChunks,
} from './check_constraint_unions.mjs';

/** @param {Map<string, Set<string>>} m */
const plain = (m) => Object.fromEntries([...m].map(([k, v]) => [k, [...v].sort()]));
/** @param {Set<string> | null} s */
const sorted = (s) => (s === null ? null : [...s].sort());

// --- migration reading -----------------------------------------------------

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

// --- live-column reading ---------------------------------------------------

const DB_TYPES_FIXTURE = [
	'export type Database = {',
	'  public: {',
	'    Tables: {',
	'      runs: {',
	'        Row: {',
	'          id: string',
	'          source: string',
	'        }',
	'        Insert: {',
	'          phantom: string',
	'        }',
	'      }',
	'      gear: {',
	'        Row: {',
	'          kind: string',
	'        }',
	'      }',
	'    }',
	'    Views: {',
	'      activities: {',
	'        Row: {',
	'          never_a_table_column: string',
	'        }',
	'      }',
	'    }',
	'  }',
	'}',
].join('\n');

test('live columns come from the Row block only, and Views are not tables', () => {
	const live = parseLiveColumns(DB_TYPES_FIXTURE);
	assert.deepEqual(plain(live), { runs: ['id', 'source'], gear: ['kind'] });
});

test('an unreadable database.types.ts throws rather than reporting no columns', () => {
	assert.throws(() => parseLiveColumns('export type Nothing = 1;'), /no public schema block/);
});

// --- client-source reading -------------------------------------------------

test('top-level chunking is not split by a comma inside a string, comment or nest', () => {
	assert.deepEqual(topLevelChunks("['a, b', 'c']"), ["'a, b'", "'c'"]);
	assert.deepEqual(topLevelChunks("['a', /* x, y */ 'b']"), ["'a'", "/* x, y */ 'b'"]);
	assert.deepEqual(topLevelChunks("[{ k: 'a', j: 1 }, { k: 'b', j: 2 }]"), [
		"{ k: 'a', j: 1 }",
		"{ k: 'b', j: 2 }",
	]);
});

test('a TS union parses single-line and multi-line, and a missing one is null', () => {
	assert.deepEqual(sorted(parseTsUnion("export type A = 'a' | 'b';", 'A')), ['a', 'b']);
	assert.deepEqual(sorted(parseTsUnion("export type B =\n\t| 'x'\n\t| 'y';", 'B')), ['x', 'y']);
	assert.equal(parseTsUnion("export type A = 'a';", 'Missing'), null);
});

test('a union name is matched whole, not as a prefix', () => {
	assert.equal(parseTsUnion("export type RunSourceKind = 'a' | 'b';", 'RunSource'), null);
});

test('a const array of strings reads, including Dart `static const`', () => {
	assert.deepEqual(
		sorted(extractClientValues("export const S = ['a', 'b'];", { decl: 'S', shape: 'strings' })),
		['a', 'b'],
	);
	assert.deepEqual(
		sorted(
			extractClientValues("class X {\n  static const _s = ['a', 'b'];\n}", {
				decl: '_s',
				shape: 'strings',
			}),
		),
		['a', 'b'],
	);
	assert.deepEqual(
		sorted(
			extractClientValues("const List<String> k = <String>[\n  'a',\n  'b',\n];", {
				decl: 'k',
				shape: 'strings',
			}),
		),
		['a', 'b'],
	);
});

// The TS inline-record annotation carries `;` field separators, which a walk
// that stops at the first `;` reads as the end of the statement. The
// ReportDialog vocabulary is declared exactly that way and the guard's first
// draft reported it missing.
test('an inline record type annotation does not end the declaration early', () => {
	const src = "\tconst R: { value: X; label: Y }[] = [\n\t\t{ value: 'a' },\n\t\t{ value: 'b' },\n\t];";
	assert.deepEqual(sorted(extractClientValues(src, { decl: 'R', shape: 'records', field: 'value' })), [
		'a',
		'b',
	]);
});

test('object keys read quoted and bare, and only at the top level', () => {
	const src = "const M: Record<string, number> = {\n\t'1_mile': 0,\n\tmarathon: 1,\n\tnested: { inner: 2 },\n};";
	assert.deepEqual(sorted(extractClientValues(src, { decl: 'M', shape: 'keys' })), [
		'1_mile',
		'marathon',
		'nested',
	]);
});

test('a Dart enum reads as snake_case, and the enhanced-enum body is ignored', () => {
	const src = 'enum M {\n  distance,\n  activityCount,\n  streakDays;\n\n  bool get x => true;\n}';
	assert.deepEqual(sorted(extractClientValues(src, { decl: 'M', shape: 'enum' })), [
		'activity_count',
		'distance',
		'streak_days',
	]);
});

test('a value that only appears in a comment is not read as a member', () => {
	const src = "const S = [\n\t'a',\n\t// 'ghost' was removed\n\t'b',\n];";
	assert.deepEqual(sorted(extractClientValues(src, { decl: 'S', shape: 'strings' })), ['a', 'b']);
});

test('a declaration that is not there reads as null, never as an empty set', () => {
	assert.equal(extractClientValues('const other = [1];', { decl: 'S', shape: 'strings' }), null);
	assert.equal(extractClientValues('enum Other { a }', { decl: 'M', shape: 'enum' }), null);
});

test('two declarations of one name throw rather than certifying the first', () => {
	const src = "const order = { nope: 1 };\nfunction f() {\n\tconst order = { '5k': 0 };\n}";
	assert.equal(findInitializers(src, 'order').length, 2);
	assert.throws(
		() => extractClientValues(src, { decl: 'order', shape: 'keys' }),
		/2 declarations named "order"/,
	);
});

// --- audit -----------------------------------------------------------------

/** @param {Record<string, string>} files */
const reader = (files) => (/** @type {string} */ p) => {
	if (!(p in files)) throw new Error(`no such file ${p}`);
	return files[p];
};

test('audit reports drift, a missing declaration, and an absent CHECK', () => {
	const files = { 'a.ts': "export type S = 'a' | 'b';" };
	const checks = new Map([
		['t.ok', new Set(['a', 'b'])],
		['t.drift', new Set(['a', 'b', 'c'])],
	]);
	const pairs = [
		{ tableColumn: 't.ok', clients: [{ file: 'a.ts', decl: 'S', shape: 'union' }] },
		{ tableColumn: 't.drift', clients: [{ file: 'a.ts', decl: 'S', shape: 'union' }] },
		{ tableColumn: 't.absent', clients: [{ file: 'a.ts', decl: 'S', shape: 'union' }] },
		{ tableColumn: 't.ok', clients: [{ file: 'a.ts', decl: 'Nope', shape: 'union' }] },
	];
	const { errors, ok } = audit(checks, reader(files), pairs);
	assert.equal(ok.length, 1);
	assert.equal(errors.length, 4);
	assert.match(errors[0], /registered twice/);
	assert.match(errors[1], /t\.drift drift vs S/);
	assert.match(errors[2], /no set-shaped CHECK constraint found/);
	assert.match(errors[3], /no union declaration named "Nope"/);
});

test('a set-shaped CHECK column with no registry entry fails', () => {
	const checks = new Map([['t.newcol', new Set(['a'])]]);
	const pairs = [{ tableColumn: 't.other', clients: [], note: 'n/a' }];
	const { errors } = audit(checks, reader({}), pairs);
	assert.ok(errors.some((e) => /t\.newcol: a set-shaped CHECK constraint with no entry/.test(e)));
});

test('a registered column whose column was dropped fails, and the phantom needs no entry', () => {
	const checks = new Map([['runs.kind', new Set(['a'])]]);
	const live = new Map([['runs', new Set(['id'])]]);
	assert.deepEqual(audit(checks, reader({}), [], live).errors.length, 1); // empty-registry case
	const withEntry = audit(checks, reader({}), [{ tableColumn: 'runs.kind', clients: [], note: 'x' }], live);
	assert.ok(withEntry.errors.some((e) => /not in database\.types\.ts/.test(e)));
	const without = audit(checks, reader({}), [{ tableColumn: 'other.col', clients: [], note: 'x' }], live);
	assert.ok(!without.errors.some((e) => /runs\.kind/.test(e)));
});

test('an empty clients list needs a note, and an unknown shape fails', () => {
	const checks = new Map([['t.a', new Set(['x'])], ['t.b', new Set(['x'])]]);
	const { errors } = audit(checks, reader({ 'a.ts': "const S = ['x'];" }), [
		{ tableColumn: 't.a', clients: [] },
		{ tableColumn: 't.b', clients: [{ file: 'a.ts', decl: 'S', shape: 'sausages' }] },
	]);
	assert.ok(errors.some((e) => /no client vocabulary and no note/.test(e)));
	assert.ok(errors.some((e) => /unknown shape "sausages"/.test(e)));
});

test('allowExtra tolerates a client-only value and fails once the exemption goes stale', () => {
	const checks = new Map([['t.s', new Set(['a', 'b'])]]);
	const live = { 'a.ts': "export type S = 'none' | 'a' | 'b';" };
	const rail = { file: 'a.ts', decl: 'S', shape: 'union', allowExtra: ['none'] };
	assert.deepEqual(audit(checks, reader(live), [{ tableColumn: 't.s', clients: [rail] }]).errors, []);

	const dropped = { 'a.ts': "export type S = 'a' | 'b';" };
	const stale = audit(checks, reader(dropped), [{ tableColumn: 't.s', clients: [rail] }]);
	assert.ok(stale.errors.some((e) => /allowExtra lists "none" but the declaration no longer carries it/.test(e)));

	const admitted = new Map([['t.s', new Set(['a', 'b', 'none'])]]);
	const absorbed = audit(admitted, reader(live), [{ tableColumn: 't.s', clients: [rail] }]);
	assert.ok(absorbed.errors.some((e) => /the CHECK now admits it/.test(e)));
});

test('allowMissing tolerates a narrower client and fails once the exemption goes stale', () => {
	const checks = new Map([['t.s', new Set(['a', 'b', 'c'])]]);
	const narrow = { 'a.ts': "export type S = 'a' | 'b';" };
	const rail = { file: 'a.ts', decl: 'S', shape: 'union', allowMissing: ['c'] };
	assert.deepEqual(audit(checks, reader(narrow), [{ tableColumn: 't.s', clients: [rail] }]).errors, []);

	const widened = { 'a.ts': "export type S = 'a' | 'b' | 'c';" };
	const stale = audit(checks, reader(widened), [{ tableColumn: 't.s', clients: [rail] }]);
	assert.ok(stale.errors.some((e) => /allowMissing lists "c" but the declaration carries it/.test(e)));
});

test('an unreadable client file is named, not skipped', () => {
	const checks = new Map([['t.s', new Set(['a'])]]);
	const { errors } = audit(checks, reader({}), [
		{ tableColumn: 't.s', clients: [{ file: 'gone.ts', decl: 'S', shape: 'union' }] },
	]);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /cannot read gone\.ts/);
});

test('an empty PAIRS list is a failure, not a clean run', () => {
	const { errors } = audit(new Map(), reader({}), []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /compares nothing/);
});

// --- the committed tree ----------------------------------------------------

/** @param {string} relPath */
const readRepo = (relPath) => readFileSync(join(REPO_ROOT, relPath), 'utf-8');

/** The set-shaped CHECK columns the CURRENT schema still has. */
function liveCheckColumns() {
	const checks = loadAllMigrationChecks();
	const live = loadLiveColumns();
	return [...checks.keys()]
		.filter((k) => {
			const [table, column] = k.split('.');
			return live.get(table)?.has(column) === true;
		})
		.sort();
}

test('the registry covers exactly the live set-shaped CHECK columns', () => {
	const registered = PAIRS.map((p) => p.tableColumn).sort();
	assert.deepEqual(registered, liveCheckColumns());
});

test('every migration in the committed tree lexes', () => {
	assert.ok(loadAllMigrationChecks().size > 0);
});

test('both clients are represented, and every registered rail declares a known shape', () => {
	const files = PAIRS.flatMap((p) => p.clients.map((c) => c.file));
	assert.ok(
		files.some((f) => f.startsWith('apps/web/src/')),
		'no web rail registered',
	);
	assert.ok(
		files.some((f) => f.startsWith('apps/mobile_android/lib/')),
		'no Dart rail registered — the half § 791 added would be gone with nothing failing',
	);
	for (const p of PAIRS) {
		for (const c of p.clients) {
			assert.ok(SHAPES.includes(c.shape), `${p.tableColumn} → ${c.decl}: bad shape ${c.shape}`);
			assert.ok(existsSync(join(REPO_ROOT, c.file)), `${c.file} does not exist`);
		}
	}
});

// Dart rails name mobile_android only. That is sound BECAUSE the twin is
// byte-identical (decisions § 39) — pin the premise here rather than trusting
// a comment.
test('every registered Dart rail has a byte-identical mobile_ios twin', () => {
	const dartFiles = [
		...new Set(
			PAIRS.flatMap((p) => p.clients.map((c) => c.file)).filter((f) =>
				f.startsWith('apps/mobile_android/lib/'),
			),
		),
	];
	assert.ok(dartFiles.length > 0);
	for (const f of dartFiles) {
		const twin = f.replace('apps/mobile_android/', 'apps/mobile_ios/');
		assert.ok(existsSync(join(REPO_ROOT, twin)), `${twin} is missing`);
		assert.equal(readRepo(twin), readRepo(f), `${twin} has drifted from ${f}`);
	}
});

test('the committed tree agrees', () => {
	const { errors } = audit(loadAllMigrationChecks(), readRepo, PAIRS, loadLiveColumns());
	assert.deepEqual(errors, []);
});

// § 817: four columns whose vocabulary was spelled anonymously inline —
// `'finished' | 'dnf' | 'dns'` five times, `'user' | 'assistant'` six — until
// each was named once. A rail that merely EXISTS proves nothing about what it
// catches, so widen each column's real CHECK by a value no client carries and
// pin that the rail is what fails.
test('the newly-named inline vocabularies catch a widened CHECK', () => {
	const live = loadLiveColumns();
	for (const column of [
		'event_results.finisher_status',
		'race_sessions.status',
		'reports.status',
		'coach_messages.role',
	]) {
		const checks = loadAllMigrationChecks();
		const current = checks.get(column);
		assert.ok(current, `${column}: no set-shaped CHECK in the committed tree`);
		checks.set(column, new Set([...current, 'a_value_no_client_carries']));
		const { errors } = audit(checks, readRepo, PAIRS, live);
		assert.ok(
			errors.some((e) => e.startsWith(`${column} drift`)),
			`${column}: widening the CHECK failed no rail`,
		);
	}
});

test('the exported TYPES_FILE still points at the web overlay unions', () => {
	assert.ok(parseTsUnion(readFileSync(TYPES_FILE, 'utf-8'), 'RunSource'));
});

test('a declaration name that is not an identifier is refused, not interpolated', () => {
	// `decl` was escaped for `$` alone, so any other metacharacter reaching the
	// pattern changed what the guard matched rather than failing: a `.` matches
	// any character and would certify the wrong list, an unbalanced `(` throws
	// from inside the scan loop, and a `\` escapes whatever follows it. The
	// registry only ever holds identifiers, so the honest answer is to say so.
	for (const bad of ['A.B', 'A(B', 'A\\w', 'A|B', '', 'A B']) {
		assert.throws(
			() => findInitializers('const AB = [1];', bad),
			/is not an identifier/,
			`${JSON.stringify(bad)} should be refused`,
		);
	}
	assert.doesNotThrow(() => findInitializers('const $A_1 = [1];', '$A_1'));
});
