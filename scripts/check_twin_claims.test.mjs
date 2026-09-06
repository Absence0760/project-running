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
	checkDeclarations,
	collectDeclarations,
	headerComment,
	readSources,
	registeredPaths,
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

const ALL = new Set([
	'apps/web/src/lib/gear/rotation_pick.ts',
	'apps/mobile_android/lib/gear_rotation_pick.dart',
	'apps/web/src/lib/x/y.ts',
	'apps/mobile_android/lib/y.dart',
]);
const exists = (/** @type {string} */ p) => ALL.has(p);

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

test('headerComment still stops at the first line that is real code', () => {
	const text = "import 'x.dart';\nint answer() => 42;\n/// Dart twin of `apps/web/src/lib/x/y.ts`.\n";
	assert.doesNotMatch(headerComment(text), /Dart twin of/);
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
		const decls = collectDeclarations(
			[dartSource('apps/mobile_android/lib/y.dart', head)],
			new Set(['apps/mobile_android/lib/y.dart', counterpart]),
			exists,
		);
		assert.equal(decls.length, 1, `${label}: ${head}`);
		assert.equal(decls[0].counterpart, counterpart);
	});
}

test('a declaration split over a soft wrap is still one declaration', () => {
	const [d] = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of\n`apps/web/src/lib/x/y.ts` — keep in step.')],
		new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/x/y.ts']),
		exists,
	);
	assert.equal(d.counterpart, 'apps/web/src/lib/x/y.ts');
	assert.equal(d.registered, true);
});

test('a counterpart that does not exist is the reported bug', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/y.ts`.')],
		new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/y.ts']),
		exists,
	);
	const { errors } = checkDeclarations(decls, []);
	assert.equal(errors.length, 2, errors.join('\n'));
	assert.match(errors[0], /does not exist/);
	assert.match(errors[1], /under the floor/);
});

test('a declared pair no syncer row carries is the § 641 failure, reported', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/x/y.ts`.')],
		new Set(),
		exists,
	);
	const { errors } = checkDeclarations(decls, []);
	assert.match(errors[0], /no row of the shared-library-syncer table carries both files/);
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
		new Set(['apps/mobile_android/lib/gear_rotation_pick.dart', 'apps/web/src/lib/gear/rotation_pick.ts']),
		exists,
	);
	assert.equal(decls.length, 1);
	assert.equal(decls[0].registered, true);
});

test('a same-platform reference is not a twin declaration', () => {
	const decls = collectDeclarations(
		[tsSource('apps/web/src/lib/x/y.ts', 'Mirrors `apps/web/src/lib/x/z.ts` exactly.')],
		new Set(),
		exists,
	);
	assert.deepEqual(decls, []);
});

test('a counterpart that is a TEST file is not a module declaration', () => {
	const decls = collectDeclarations(
		[tsSource('apps/web/src/lib/x/y.ts', 'Mirrors `apps/mobile_android/test/y_test.dart`.')],
		new Set(),
		exists,
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
		new Set(),
		exists,
	);
	assert.deepEqual(decls, []);
});

test('a KNOWN_GAPS entry that has been fixed fails rather than sitting as cover', () => {
	const decls = collectDeclarations(
		[dartSource('apps/mobile_android/lib/y.dart', 'Dart twin of `apps/web/src/lib/x/y.ts`.')],
		new Set(['apps/mobile_android/lib/y.dart', 'apps/web/src/lib/x/y.ts']),
		exists,
	);
	const { errors } = checkDeclarations(decls, [
		{ file: 'apps/mobile_android/lib/y.dart', counterpart: 'apps/web/src/lib/x/y.ts', reason: 'unregistered' },
	]);
	assert.match(errors[0], /now a well-formed registered pair/);
});

test('a KNOWN_GAPS entry nothing declares fails rather than sitting as cover', () => {
	const { errors } = checkDeclarations([], [
		{ file: 'apps/mobile_android/lib/gone.dart', counterpart: 'apps/web/src/lib/x/gone.ts', reason: 'unregistered' },
	]);
	assert.ok(errors.some((e) => /no header declares it/.test(e)), errors.join('\n'));
});

test('an empty census fails rather than reading as a clean one', () => {
	const { errors } = checkDeclarations([], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /reporting an empty census as a clean one/);
});

test('registeredPaths reads the two source columns and not the mirror-test one', () => {
	const { paths, errors } = registeredPaths(readFileSync(SYNCER_DOC, 'utf-8'));
	assert.deepEqual(errors, []);
	assert.ok(paths.has('apps/web/src/lib/gear/rotation_pick.ts'));
	assert.ok(paths.has('apps/mobile_android/lib/gear_rotation_pick.dart'));
	for (const p of paths) assert.doesNotMatch(p, /\.test\.ts$|_test\.dart$/, p);
});

test('the tree’s twin declarations are all clean or registered as a known gap', () => {
	const { paths } = registeredPaths(readFileSync(SYNCER_DOC, 'utf-8'));
	const declarations = collectDeclarations(readSources(), paths);
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
	const { paths } = registeredPaths(readFileSync(SYNCER_DOC, 'utf-8'));
	const found = collectDeclarations(readSources(), paths).length;
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
