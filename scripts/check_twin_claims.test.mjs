// Unit tests for scripts/check_twin_claims.mjs.
//
// The guard's own failure mode is the one it exists to catch, one level up: a
// census that quietly stops recognising the header convention reports an empty
// tree as a clean one. Every case below either drives a synthetic tree or reads
// the real one and asserts a property of it.

import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import { SYNCER_DOC } from './check_parity_pair_registry.mjs';
import {
	DECLARATION,
	KNOWN_GAPS,
	MIN_DECLARATIONS,
	NOT_PAIRS,
	RELATIVE_DECLARATION,
	checkDeclarations,
	checkNotPairs,
	collectDeclarations,
	commentBlocks,
	headerComment,
	isRegisteredPair,
	readSources,
	registeredRows,
	resolveRelative,
	topLevelNames,
} from './check_twin_claims.mjs';

/**
 * A source file with `head` as its `///` header and one line of code.
 *
 * @param {string} path
 * @param {string} head
 */
const dartSource = (path, head) => ({
	path,
	text: `${head
		.split('\n')
		.map((l) => `/// ${l}`)
		.join('\n')}\nint answer() => 42;\n`,
});

/**
 * The same for a web module, written as a JSDoc block comment.
 *
 * @param {string} path
 * @param {string} head
 */
const tsSource = (path, head) => ({
	path,
	text: `/**\n${head
		.split('\n')
		.map((l) => ` * ${l}`)
		.join('\n')}\n */\nexport const answer = 42;\n`,
});

const ALL = [
	'apps/web/src/lib/gear/rotation_pick.ts',
	'apps/mobile_android/lib/gear_rotation_pick.dart',
	'apps/web/src/lib/x/y.ts',
	'apps/mobile_android/lib/y.dart',
	'apps/web/src/lib/other/y.ts',
];
const exists = (/** @type {string} */ p) => ALL.includes(p);
/** One row holding both halves of the `x/y` pair. */
const ROW_XY = [new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/x/y.ts'])];

test('headerComment reads to the first line of code and folds a wrapped sentence', () => {
	const text = '/// Dart twin of\n/// `apps/web/src/lib/x/y.ts`.\n\nint answer() => 42;\n/// not a header\n';
	const head = headerComment(text);
	assert.match(head, /Dart twin of `apps\/web\/src\/lib\/x\/y\.ts`/);
	assert.doesNotMatch(head, /not a header/);
});

// The mechanism behind three quarters of the tree being unread (decisions
// § 1243): a module puts its imports above the block that documents it, and a
// scanner that stops at the first non-comment line returns an EMPTY header for
// every such file. `run_stats.ts` and `elevation.dart` are two of the 37.
test('headerComment steps over an import prologue to reach the doc block', () => {
	const dart = "import 'dart:async';\n\nimport 'package:core_models/core_models.dart';\n\n/// Dart port of `apps/web/src/lib/routes/elevation.ts`.\nconst x = 1;\n";
	assert.match(headerComment(dart), /Dart port of `apps\/web\/src\/lib\/routes\/elevation\.ts`/);

	const ts = "import type { TrackPoint } from '../types';\n\n/**\n * Mirrors `apps/mobile_android/lib/run_stats.dart:movingTimeOf`.\n */\nexport const answer = 42;\n";
	assert.match(headerComment(ts), /run_stats\.dart:movingTimeOf/);
});

// The three deploy-gate modules put the env-var key — a documented top-level
// CONSTANT — between the imports and the block that documents the gate, so the
// twin claim sat under a statement and was read as no header at all. A constant
// is data, not the module's behaviour.
test('headerComment steps over a documented top-level constant', () => {
	const dart =
		"import 'package:flutter_dotenv/flutter_dotenv.dart';\n\n" +
		"/// The dotenv key the gate reads.\nconst String kGateEnvKey = 'GATE';\n\n" +
		'/// The gate as the surfaces read it — the mobile twin of web\n' +
		'/// `apps/web/src/lib/safety/off_route_flag.ts`.\nbool get gate => false;\n';
	assert.match(headerComment(dart), /off_route_flag\.ts/);

	const ts = "import { env } from '$env/dynamic/public';\n\nexport const KEY = 'x';\n\n/**\n * Mirrors `apps/mobile_android/lib/y.dart`.\n */\nexport function f() {}\n";
	assert.match(headerComment(ts), /y\.dart/);
});

test('headerComment still stops at the first line that is real code', () => {
	const text = "import 'x.dart';\nint answer() => 42;\n/// Dart twin of `apps/web/src/lib/x/y.ts`.\n";
	assert.doesNotMatch(headerComment(text), /Dart twin of/);
});

// Property 1 is checked wherever a declaration sits, so the whole-file fold has
// to break at each line of code: two unrelated comment blocks merged into one
// sentence would let a verb in the first reach a path in the second.
test('commentBlocks reads past the header but does not fuse two blocks', () => {
	const text = '/// Mirrors nothing.\nint a() => 1;\n\n/// Dart twin of `apps/web/src/lib/x/y.ts`.\nint b() => 2;\n';
	const blocks = commentBlocks(text);
	assert.equal(blocks.length, 2);
	assert.match(blocks[1], /Dart twin of `apps\/web\/src\/lib\/x\/y\.ts`/);
	for (const b of blocks) assert.doesNotMatch(b, /Mirrors nothing\.\s*Dart twin/);
});

// The fusion this prevents is not hypothetical: a verb ending one block and a
// path opening the next would otherwise read as a declaration neither of them
// makes.
test('a verb in one block cannot reach a path in the next', () => {
	const text = '/// Mirrors\nint a() => 1;\n\n/// See `apps/web/src/lib/x/y.ts`.\nint b() => 2;\n';
	const decls = collectDeclarations([{ path: 'apps/mobile_android/lib/y.dart', text }], [], {
		exists,
		paths: ALL,
	});
	assert.deepEqual(decls, []);
});

// Each of these forms was found in the tree and read as no declaration at all.
// Planted one per form, so a narrowing of DECLARATION fails here rather than
// silently shrinking the census again.
for (const [label, head, counterpart] of /** @type {[string, string, string][]} */ ([
	['a twin named without the "of"', 'Kept in lockstep with the Dart twin `apps/web/src/lib/x/y.ts`.', 'apps/web/src/lib/x/y.ts'],
	['a path written with no backticks', 'Mirrors apps/web/src/lib/x/y.ts exactly.', 'apps/web/src/lib/x/y.ts'],
	['a backticked path with a :symbol suffix', 'Mirrors `apps/web/src/lib/x/y.ts:movingTimeOf`.', 'apps/web/src/lib/x/y.ts'],
	['a port declared as "ported from"', 'The pure half, ported from `apps/web/src/lib/x/y.ts`.', 'apps/web/src/lib/x/y.ts'],
	['a port declared as "Dart port of"', 'Dart port of `apps/web/src/lib/x/y.ts`.', 'apps/web/src/lib/x/y.ts'],
])) {
	test(`DECLARATION reads ${label}`, () => {
		const decls = collectDeclarations([dartSource('apps/mobile_android/lib/y.dart', head)], ROW_XY, {
			exists,
			paths: ALL,
		});
		assert.equal(decls.length, 1, `${label}: ${head}`);
		assert.equal(decls[0].counterpart, counterpart);
	});
}

// The fourth form § 1243 filed rather than fixed. Two live § 641-class pairs
// (`off_route_flag`, `weigh_in_flag`) were written this way and sat in neither
// registry with nothing able to see them.
test('RELATIVE_DECLARATION reads a counterpart named without a repo root', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', "The mobile twin of web's `x/y.ts`.")],
		ROW_XY,
		{ exists, paths: ALL },
	);
	assert.equal(decls.length, 1);
	assert.equal(decls[0].counterpart, 'apps/web/src/lib/x/y.ts');
	assert.equal(decls[0].registered, true);
});

// Measured, not stylistic: without the backticks the TAIL of an already-matched
// anchored path matches as a second counterpart (`…/recurrence.dart` yields
// `e.dart`), which produced ten phantom declarations across the tree.
test('a relative path with no backticks is prose, not a declaration', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Mirrors x/y.ts closely enough.')],
		ROW_XY,
		{ exists, paths: ALL },
	);
	assert.deepEqual(decls, []);
});

test('a relative counterpart matching two files is reported, never guessed', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', "The mobile twin of web's `y.ts`.")],
		ROW_XY,
		{ exists, paths: ALL },
	);
	assert.equal(decls.length, 1);
	assert.deepEqual([...decls[0].ambiguous].sort(), [
		'apps/web/src/lib/other/y.ts',
		'apps/web/src/lib/x/y.ts',
	]);
	const { errors } = checkDeclarations(decls, [], []);
	assert.match(errors[0], /matches 2 files/);
});

test('a relative counterpart matching nothing is reported as a dangling path', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', "The mobile twin of web's `x/gone.ts`.")],
		ROW_XY,
		{ exists, paths: ALL },
	);
	assert.equal(decls[0].exists, false);
	const { errors } = checkDeclarations(decls, [], []);
	assert.match(errors[0], /does not exist/);
});

test('resolveRelative matches on a path tail, not on a substring', () => {
	assert.deepEqual(resolveRelative('x/y.ts', ALL), ['apps/web/src/lib/x/y.ts']);
	assert.deepEqual(resolveRelative('y.dart', ALL), ['apps/mobile_android/lib/y.dart']);
	assert.deepEqual(resolveRelative('ick.ts', ALL), []);
});

test('a declaration split over a soft wrap is still one declaration', () => {
	const [d] = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of\n`apps/web/src/lib/x/y.ts` — keep in step.')],
		ROW_XY,
		{ exists, paths: ALL },
	);
	assert.equal(d.counterpart, 'apps/web/src/lib/x/y.ts');
	assert.equal(d.registered, true);
});

test('a counterpart that does not exist is the reported bug', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/y.ts`.')],
		[new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/y.ts'])],
		{ exists, paths: ALL },
	);
	const { errors } = checkDeclarations(decls, [], []);
	assert.equal(errors.length, 2, errors.join('\n'));
	assert.match(errors[0], /does not exist/);
	assert.match(errors[1], /under the floor/);
});

test('a declared pair no syncer row carries is the § 641 failure, reported', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/x/y.ts`.')],
		[],
		{ exists, paths: ALL },
	);
	const { errors } = checkDeclarations(decls, [], []);
	assert.match(errors[0], /no row of the shared-library-syncer table carries both files/);
});

// Two files each registered against some THIRD module are two pairs, not one.
// The flattened membership test this replaced read the union of every row and
// could not tell that apart.
test('registration wants both halves in the SAME row', () => {
	const split = [
		new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/other/y.ts']),
		new Set(['apps/web/src/lib/x/y.ts', 'apps/mobile_android/lib/gear_rotation_pick.dart']),
	];
	assert.equal(isRegisteredPair(split, 'apps/mobile_android/lib/y.dart', 'apps/web/src/lib/x/y.ts'), false);
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/x/y.ts`.')],
		split,
		{ exists, paths: ALL },
	);
	assert.equal(decls[0].registered, false);
});

// The registry keys a pair on its WEB basename, so the Dart half's own filename
// need not match. A name-keyed check reports this pair and teaches the reader
// to distrust the guard.
test('registration is by path, so a Dart half named differently still passes', () => {
	const decls = collectDeclarations(
		[
			dartSource(
				'apps/mobile_android/lib/gear_rotation_pick.dart',
				'Twin of `apps/web/src/lib/gear/rotation_pick.ts` — keep in lockstep.',
			),
		],
		[new Set(['apps/mobile_android/lib/gear_rotation_pick.dart', 'apps/web/src/lib/gear/rotation_pick.ts'])],
		{ exists, paths: ALL },
	);
	assert.equal(decls.length, 1);
	assert.equal(decls[0].registered, true);
});

// A sentence beside one function ("Mirrors `core/data.ts:createClub`") is a
// claim about that call, not about the module — 14 of them sit in the tree and
// none is registrable. The path it names still has to exist.
test('a declaration below the header is checked for existence but not registration', () => {
	const text =
		'/// Nothing here.\nint a() => 1;\n\n/// Mirrors `apps/web/src/lib/x/y.ts`.\nint b() => 2;\n';
	const decls = collectDeclarations([{ path: 'apps/mobile_android/lib/y.dart', text }], [], {
		exists,
		paths: ALL,
	});
	assert.equal(decls.length, 1);
	assert.equal(decls[0].scope, 'body');
	assert.deepEqual(checkDeclarations(decls, [], []).errors.filter((e) => !/under the floor/.test(e)), []);

	const dangling = collectDeclarations(
		[{ path: 'apps/mobile_android/lib/y.dart', text: text.replace('x/y.ts', 'x/gone.ts') }],
		[],
		{ exists, paths: ALL },
	);
	assert.match(checkDeclarations(dangling, [], []).errors[0], /does not exist/);
});

test('a same-platform reference is not a twin declaration', () => {
	const decls = collectDeclarations(
		[tsSource('apps/web/src/lib/x/y.ts', 'Mirrors `apps/web/src/lib/x/z.ts` exactly.')],
		[],
		{ exists, paths: ALL },
	);
	assert.deepEqual(decls, []);
});

test('a counterpart that is a TEST file is not a module declaration', () => {
	const decls = collectDeclarations(
		[tsSource('apps/web/src/lib/x/y.ts', 'Mirrors `apps/mobile_android/test/y_test.dart`.')],
		[],
		{ exists, paths: ALL },
	);
	assert.deepEqual(decls, []);
});

// `in lockstep with` is this repo's phrase for every kind of coupling — a client
// and an SQL CHECK, a jsonb key registry, a service-worker projection. Reading
// it as a parity claim would report a dozen relationships that are not pairs.
test('a coupling that is not a twin declaration is left alone', () => {
	const decls = collectDeclarations(
		[
			tsSource(
				'apps/web/src/lib/x/y.ts',
				'Keep in lockstep with `apps/mobile_android/lib/y.dart` and the SQL CHECK.',
			),
		],
		[],
		{ exists, paths: ALL },
	);
	assert.deepEqual(decls, []);
});

// The unified rule. A header that DENIES a pair ("Not a twin of web's `x.ts`")
// and one that overstates one (a widget naming the module behind it) both land
// in the same place: the register. Reading the wording instead was tried and
// removed — `gym_session_draft.dart` puts its negation before the path and
// `rate_limit_message.dart` two clauses after, so a one-directional window
// reads one honest header and accuses the other.
test('a NOT_PAIRS entry answers a claim the registries cannot carry', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', "Not a twin of web's `x/y.ts` — only the predicate is shared.")],
		[],
		{ exists, paths: ALL },
	);
	const judged = [
		{
			web: 'apps/web/src/lib/x/y.ts',
			mobile: 'apps/mobile_android/lib/y.dart',
			reason: 'the mobile half keeps only the predicate; the web half is the whole codec',
			shared: [],
		},
	];
	const { errors, ok } = checkDeclarations(decls, [], judged);
	assert.deepEqual(errors.filter((e) => !/under the floor/.test(e)), []);
	assert.ok(ok.some((o) => /judged not a pair/.test(o)), ok.join('\n'));
});

test('a KNOWN_GAPS entry that has been fixed fails rather than sitting as cover', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/x/y.ts`.')],
		ROW_XY,
		{ exists, paths: ALL },
	);
	const { errors } = checkDeclarations(
		decls,
		[{ file: 'apps/mobile_android/lib/y.dart', counterpart: 'apps/web/src/lib/x/y.ts', reason: 'unregistered' }],
		[],
	);
	assert.match(errors[0], /now a well-formed registered pair/);
});

test('a KNOWN_GAPS entry nothing declares fails rather than sitting as cover', () => {
	const { errors } = checkDeclarations(
		[],
		[{ file: 'apps/mobile_android/lib/gone.dart', counterpart: 'apps/web/src/lib/x/gone.ts', reason: 'unregistered' }],
		[],
	);
	assert.ok(errors.some((e) => /no header declares it/.test(e)), errors.join('\n'));
});

test('an empty census fails rather than reading as a clean one', () => {
	const { errors } = checkDeclarations([], [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /reporting an empty census as a clean one/);
});

test('registeredRows reads the two source columns and not the mirror-test one', () => {
	const { rows, errors } = registeredRows(readFileSync(SYNCER_DOC, 'utf-8'));
	assert.deepEqual(errors, []);
	assert.ok(
		isRegisteredPair(
			rows,
			'apps/web/src/lib/gear/rotation_pick.ts',
			'apps/mobile_android/lib/gear_rotation_pick.dart',
		),
	);
	for (const row of rows) for (const p of row) assert.doesNotMatch(p, /\.test\.ts$|_test\.dart$/, p);
});

test('the tree’s twin declarations are all clean, registered, or judged', () => {
	const { rows } = registeredRows(readFileSync(SYNCER_DOC, 'utf-8'));
	const declarations = collectDeclarations(readSources(), rows);
	assert.ok(
		declarations.length >= MIN_DECLARATIONS,
		`expected the declaration population, found ${declarations.length}`,
	);
	assert.deepEqual(checkDeclarations(declarations).errors, []);
});

// A floor is only a floor if it sits near the count it guards. At 60 against a
// census of 106 it carried 46 of slack, and the reader losing a quarter of the
// tree passed it unremarked — the guard's own failure mode, undetected by the
// check written for it (decisions § 1243). This pins the slack itself, so
// widening the reader without raising the floor fails here.
test('MIN_DECLARATIONS sits close under the real census', () => {
	const { rows } = registeredRows(readFileSync(SYNCER_DOC, 'utf-8'));
	const found = collectDeclarations(readSources(), rows).length;
	assert.ok(found - MIN_DECLARATIONS <= 15, `floor ${MIN_DECLARATIONS} has ${found - MIN_DECLARATIONS} of slack under ${found}`);
});

// The register is a list of what is still owed, so it has to be readable as
// one: every entry says which of the two properties it breaks and where the fix
// lives.
//
// An EMPTY register is the goal state, not a broken one -- it means every twin
// declaration in the tree is carried by a syncer row -- so there is no
// non-empty floor here. Emptying it by accident cannot hide anything either:
// `checkDeclarations` fails on a declaration that neither a row nor a gap
// covers, which the test above runs over the whole tree.
test('every KNOWN_GAPS entry carries a reason', () => {
	for (const gap of KNOWN_GAPS) {
		assert.ok(gap.reason.length > 20, `${gap.file}: ${gap.reason}`);
		assert.match(gap.file, /^(?:apps|packages)\//);
		assert.match(gap.counterpart, /^(?:apps|packages)\//);
	}
});

test('DECLARATION is anchored on a verb, not on a bare path', () => {
	DECLARATION.lastIndex = 0;
	assert.equal(DECLARATION.test('see `apps/web/src/lib/x/y.ts` for the shape'), false);
	DECLARATION.lastIndex = 0;
	assert.equal(DECLARATION.test('Dart twin of `apps/web/src/lib/x/y.ts`'), true);
	DECLARATION.lastIndex = 0;
});

// Dropping the backticks widened what can sit between the verb and the path, so
// the verb anchor has to hold without them too.
test('DECLARATION without backticks is still anchored on a verb', () => {
	DECLARATION.lastIndex = 0;
	assert.equal(DECLARATION.test('see apps/web/src/lib/x/y.ts for the shape'), false);
	DECLARATION.lastIndex = 0;
	assert.equal(DECLARATION.test('Mirrors apps/web/src/lib/x/y.ts exactly'), true);
	DECLARATION.lastIndex = 0;
});

test('RELATIVE_DECLARATION is anchored on a verb too', () => {
	RELATIVE_DECLARATION.lastIndex = 0;
	assert.equal(RELATIVE_DECLARATION.test('see `x/y.ts` for the shape'), false);
	RELATIVE_DECLARATION.lastIndex = 0;
	assert.equal(RELATIVE_DECLARATION.test("the mobile twin of web's `x/y.ts`"), true);
	RELATIVE_DECLARATION.lastIndex = 0;
});

// ---------------------------------------------------------------------------
// Property 4: the judgements.

test('topLevelNames reads the public surface of each language', () => {
	const ts = topLevelNames(
		'a.ts',
		'export function f() {}\nexport async function g() {}\nexport const K = 1;\n' +
			'export class C {}\nexport interface I {}\nexport type T = 1;\nexport enum E { a }\n' +
			'function hidden() {}\nconst alsoHidden = 2;\n',
	);
	assert.deepEqual([...ts].sort(), ['C', 'E', 'I', 'K', 'T', 'f', 'g']);

	const dart = topLevelNames(
		'a.dart',
		"class C {}\nenum E { a }\nmixin M {}\ntypedef T = int;\nconst String kKey = 'x';\n" +
			'final answer = 1;\nbool f(String? s) => true;\nFuture<int> g() async => 1;\n' +
			'bool get h => false;\nString _private() => "";\n  if (x) {\n  for (final a in b) {\n',
	);
	assert.deepEqual([...dart].sort(), ['C', 'E', 'M', 'T', 'answer', 'f', 'g', 'h', 'kKey']);
});

test('checkNotPairs passes an entry whose shared surface has not moved', () => {
	const read = (/** @type {string} */ p) =>
		p.endsWith('.ts') ? 'export function shared() {}\nexport const only = 1;\n' : 'bool shared() => true;\n';
	const { errors, ok } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs', shared: ['shared'] }],
		[],
		{ read },
	);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
});

// The judgement the entry records is "these two do not share logic". A name
// appearing on both sides is how that stops being true, and it is the exact
// scenario § 1244 could not re-derive: `strava.dart` growing the native OAuth
// callback its own header anticipates.
test('checkNotPairs fails when the shared surface GROWS', () => {
	const read = (/** @type {string} */ p) =>
		p.endsWith('.ts')
			? 'export function shared() {}\nexport function converged() {}\n'
			: 'bool shared() => true;\nbool converged() => true;\n';
	const { errors } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs entirely', shared: ['shared'] }],
		[],
		{ read },
	);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /now declare \[converged, shared\]/);
});

// The other direction is how a symbol reader that has gone blind presents
// itself: the recorded set stops being found and the entry silently starts
// measuring nothing.
test('checkNotPairs fails when the shared surface SHRINKS', () => {
	const read = (/** @type {string} */ p) =>
		p.endsWith('.ts') ? 'export function shared() {}\n' : 'bool other() => true;\n';
	const { errors } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs entirely', shared: ['shared'] }],
		[],
		{ read },
	);
	assert.match(errors[0], /now declare \[\]/);
});

test('checkNotPairs fails when either file has no public surface at all', () => {
	const read = (/** @type {string} */ p) => (p.endsWith('.ts') ? 'export function f() {}\n' : '// nothing\n');
	const { errors } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs entirely', shared: [] }],
		[],
		{ read },
	);
	assert.match(errors[0], /symbol reader found no top-level names/);
});

test('checkNotPairs fails when a named file is gone', () => {
	const read = (/** @type {string} */ p) => (p.endsWith('.ts') ? 'export function f() {}\n' : null);
	const { errors } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs entirely', shared: [] }],
		[],
		{ read },
	);
	assert.match(errors[0], /names a file that does not exist/);
});

test('checkNotPairs fails when the pair has since been registered', () => {
	const read = (/** @type {string} */ p) => (p.endsWith('.ts') ? 'export function f() {}\n' : 'bool g() => true;\n');
	const { errors } = checkNotPairs(
		[{ web: 'w.ts', mobile: 'm.dart', reason: 'different SDKs entirely', shared: [] }],
		[new Set(['w.ts', 'm.dart'])],
		{ read },
	);
	assert.match(errors[0], /a syncer row now carries both/);
});

test('every NOT_PAIRS entry is well formed and still true of the tree', () => {
	for (const entry of NOT_PAIRS) {
		assert.match(entry.web, /^apps\/web\/src\/lib\//, entry.web);
		assert.match(entry.mobile, /\.dart$/, entry.mobile);
		assert.ok(entry.reason.length > 60, `${entry.web}: reason too thin to re-judge from`);
		assert.deepEqual([...entry.shared], [...entry.shared].sort(), `${entry.web}: shared set must be sorted`);
	}
	const { rows } = registeredRows(readFileSync(SYNCER_DOC, 'utf-8'));
	assert.deepEqual(checkNotPairs(NOT_PAIRS, rows).errors, []);
});

// Anti-vacuity for the measurement itself: a registered pair shares a great
// deal, so a reader that had gone blind would show up here as an empty
// intersection rather than as a passing register.
test('the symbol reader finds a registered pair’s shared surface', () => {
	const web = readFileSync(new URL('../apps/web/src/lib/core/undo_queue.ts', import.meta.url), 'utf-8');
	const mobile = readFileSync(new URL('../apps/mobile_android/lib/undo_queue.dart', import.meta.url), 'utf-8');
	const a = topLevelNames('undo_queue.ts', web);
	const b = topLevelNames('undo_queue.dart', mobile);
	const shared = [...a].filter((n) => b.has(n));
	assert.ok(shared.length >= 4, `expected a registered pair to share names, found [${shared.join(', ')}]`);
});
