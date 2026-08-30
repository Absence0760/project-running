// Unit tests for the CHECK-constraint ↔ client-enumeration guard.
//
// The last four cases read the COMMITTED tree, so a real drift fails them as
// well as the guard itself — which is why CI runs the guard first and this
// suite second (decisions § 774).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

import {
	PAIRS,
	REPO_ROOT,
	UNENUMERATED,
	audit,
	auditCoverage,
	droppedColumnsIn,
	loadAllMigrationChecks,
	parseChecks,
} from './check_constraint_unions.mjs';
import { extractClientEnum } from './client_enum_extract.mjs';

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

// § 791: `runs.kind` was added with a CHECK in 20261204_001 and the COLUMN
// dropped in 20261206_001, and the guard reported it live for eight months.
test('a dropped column takes its CHECK with it, within a file and across them', () => {
	const sql = [
		"alter table public.runs add column kind text check (kind in ('run', 'lift'));",
		'alter table public.runs drop column kind',
	].join(';\n');
	assert.deepEqual(plain(parseChecks(sql)), {});
	assert.deepEqual(droppedColumnsIn(sql), ['runs.kind']);
	assert.equal(loadAllMigrationChecks().has('runs.kind'), false);
});

test('a dropped named constraint takes its values with it', () => {
	const sql = [
		"alter table public.runs add constraint c check (source in ('gps', 'manual'));",
		'alter table public.runs drop constraint c;',
	].join('\n');
	assert.deepEqual(plain(parseChecks(sql)), {});
});

test('the drop-then-widen form every widening is written as still lands widened', () => {
	const sql = [
		"alter table public.runs add constraint c check (source in ('gps'));",
		'alter table public.runs drop constraint c;',
		"alter table public.runs add constraint c check (source in ('gps', 'manual'));",
	].join('\n');
	assert.deepEqual(plain(parseChecks(sql)), { 'runs.source': ['gps', 'manual'] });
});

test('every client-enumeration shape parses', () => {
	const set = (/** @type {Set<string> | null} */ s) => [...(s ?? [])].sort();
	assert.deepEqual(set(extractClientEnum("export type A = 'a' | 'b';", { shape: 'union', name: 'A' })), [
		'a',
		'b',
	]);
	assert.deepEqual(
		set(extractClientEnum("export type B =\n\t| 'x'\n\t| 'y';", { shape: 'union', name: 'B' })),
		['x', 'y'],
	);
	assert.deepEqual(
		set(extractClientEnum("export const L: readonly T[] = ['a', 'b'];", { shape: 'list', name: 'L' })),
		['a', 'b'],
	);
	assert.deepEqual(
		set(
			extractClientEnum("const K: Spec[] = [{ kind: 'a', c: 'x' }, { kind: 'b', c: 'y' }];", {
				shape: 'keyed',
				name: 'K',
				field: 'kind',
			}),
		),
		['a', 'b'],
	);
	assert.deepEqual(
		set(extractClientEnum("const M: Record<string, number> = { 'a': 0, b: 1 };", { shape: 'keys', name: 'M' })),
		['a', 'b'],
	);
	assert.deepEqual(
		set(extractClientEnum('enum E { none, doubleProgression }', { shape: 'enum', name: 'E' })),
		['double_progression', 'none'],
	);
	assert.equal(extractClientEnum("export type A = 'a';", { shape: 'union', name: 'Missing' }), null);
});

// The type-annotation brackets sit before the initialiser's, and reading the
// first pair yielded an empty set for six registered declarations at once.
test('a type annotation carrying brackets does not shadow the initialiser', () => {
	assert.deepEqual(
		[...(extractClientEnum("export const K: Spec[] = [{ kind: 'a' }];", {
			shape: 'keyed',
			name: 'K',
			field: 'kind',
		}) ?? [])],
		['a'],
	);
});

// A field whose TYPE is X is not a declaration OF X — reading it that way made
// four registered Dart enums look like redeclarations of themselves.
test('a field typed by the enum is not mistaken for a second declaration', () => {
	const src = 'enum SessionItemKind { hold, reps }\nclass I { final SessionItemKind kind; }';
	assert.deepEqual([...(extractClientEnum(src, { shape: 'enum', name: 'SessionItemKind' }) ?? [])], [
		'hold',
		'reps',
	]);
});

test('a genuinely ambiguous declaration throws rather than certifying one of them', () => {
	assert.throws(
		() => extractClientEnum("const A = ['a'];\nconst A = ['b'];", { shape: 'list', name: 'A' }),
		/declared 2 times/,
	);
});

test('audit reports each failure shape and stays quiet on agreement', () => {
	const files = {
		't.ts': "export type S = 'a' | 'b';\nexport type T = 'a';\n",
	};
	/** @param {string} f */
	const read = (f) => {
		const src = files[/** @type {keyof typeof files} */ (f)];
		if (src === undefined) throw new Error('no such file');
		return src;
	};
	const checks = new Map([
		['t.ok', new Set(['a', 'b'])],
		['t.drift', new Set(['a', 'b', 'c'])],
	]);
	const { errors, ok } = audit(checks, read, [
		{ tableColumn: 't.ok', ts: [{ file: 't.ts', shape: 'union', name: 'S' }], dart: [] },
		{ tableColumn: 't.drift', ts: [{ file: 't.ts', shape: 'union', name: 'S' }], dart: [] },
		{ tableColumn: 't.absent', ts: [{ file: 't.ts', shape: 'union', name: 'S' }], dart: [] },
		{ tableColumn: 't.ok', ts: [{ file: 't.ts', shape: 'union', name: 'NoSuchUnion' }], dart: [] },
		{ tableColumn: 't.ok', ts: [{ file: 'gone.ts', shape: 'union', name: 'S' }], dart: [] },
		{ tableColumn: 't.ok', ts: [], dart: [] },
	]);
	assert.equal(ok.length, 1);
	assert.equal(errors.length, 5);
	assert.match(errors[0], /drift in t\.ts#S/);
	assert.match(errors[1], /no live CHECK constraint on "t\.absent"/);
	assert.match(errors[2], /no union named "NoSuchUnion"/);
	assert.match(errors[3], /cannot read gone\.ts/);
	assert.match(errors[4], /no client enumeration on either rail/);
});

test('a declared superset passes, and a CHECK value it lacks still fails', () => {
	const read = () => "export type S = 'a' | 'b' | 'synthetic';";
	const decl = { file: 't.ts', shape: /** @type {const} */ ('union'), name: 'S', extra: ['synthetic'] };
	assert.deepEqual(
		audit(new Map([['t.c', new Set(['a', 'b'])]]), read, [
			{ tableColumn: 't.c', ts: [decl], dart: [] },
		]).errors,
		[],
	);
	const short = audit(new Map([['t.c', new Set(['a', 'b', 'c'])]]), read, [
		{ tableColumn: 't.c', ts: [decl], dart: [] },
	]).errors;
	assert.equal(short.length, 1);
	assert.match(short[0], /in the CHECK but not the client: c/);
});

test('an empty PAIRS list is a failure, not a clean run', () => {
	const { errors } = audit(new Map(), () => '', []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /compares nothing/);
});

test('coverage names an unaccounted column, a stale excuse and a double filing', () => {
	const checks = new Map([
		['t.paired', new Set(['a'])],
		['t.excused', new Set(['a'])],
		['t.orphan', new Set(['a'])],
		['t.both', new Set(['a'])],
	]);
	const errors = auditCoverage(
		checks,
		[{ tableColumn: 't.paired' }, { tableColumn: 't.both' }],
		{ 't.excused': 'why', 't.both': 'why', 't.gone': 'why' },
	);
	assert.equal(errors.length, 3);
	assert.match(errors[0], /t\.both is filed BOTH/);
	assert.match(errors[1], /t\.orphan has a set-shaped CHECK constraint that nothing accounts for/);
	assert.match(errors[2], /t\.gone is in UNENUMERATED but has no live CHECK/);
});

// The completeness assertion the old suite lacked. It asserted
// `checks.size >= PAIRS.length`, which is true of any registry — 41 pairs
// against 68 parsed columns passed it while 27 columns went unexamined.
test('every live CHECK column is accounted for, and nothing filed is dead', () => {
	assert.deepEqual(auditCoverage(loadAllMigrationChecks()), []);
});

test('the registry is exactly the live constraint set, both directions', () => {
	const live = new Set(loadAllMigrationChecks().keys());
	const filed = new Set([...PAIRS.map((p) => p.tableColumn), ...Object.keys(UNENUMERATED)]);
	assert.deepEqual([...live].sort(), [...filed].sort());
});

test('every migration in the committed tree lexes, and the tree agrees', () => {
	const checks = loadAllMigrationChecks();
	assert.ok(checks.size > 0, 'parsed no CHECK sets at all');
	const { errors, ok } = audit(checks, (rel) => readFileSync(join(REPO_ROOT, rel), 'utf-8'));
	assert.deepEqual(errors, []);
	assert.ok(ok.length >= PAIRS.length, `verified only ${ok.length} client enumerations`);
});
