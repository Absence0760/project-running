// Unit tests for scripts/check_test_inventory_counts.mjs.
//
// The two carve-outs get the most attention here, because they are the ones a
// naive sweep gets wrong in the DANGEROUS direction: a parameterised count is
// correct and would be "corrected" into wrongness, and a `— 1 added` is a
// round delta that would be read as the file's whole count.

import assert from 'node:assert/strict';
import { test } from 'node:test';

import {
	censusHeadings,
	check,
	claimsIn,
	counterFor,
	expander,
	globRe,
	looksLikePath,
	sectionDir,
} from './check_test_inventory_counts.mjs';

test('counterFor uses the recompute command the document prescribes, per kind', () => {
	assert.equal(counterFor('a/b_test.dart')('  test(\'x\', () {});\ntestWidgets(\'y\', (t) {});\n'), 2);
	assert.equal(counterFor('a/b.test.ts')("test('x', () => {});\nit('y', () => {});\n"), 2);
	assert.equal(counterFor('a/b_test.go')('func TestX(t *testing.T) {}\nfunc helper() {}\n'), 1);
	assert.equal(counterFor('a/b.rs')('#[test]\nfn x() {}\n    #[test]\n    fn y() {}\n'), 2);
	assert.equal(counterFor('a/BTest.kt')('    @Test\n    fun x() {}\n'), 1);
	assert.equal(counterFor('a/b_test.sql')('select plan(12);\nselect plan(3);\n'), 15);
});

test('a Deno function test is counted by Deno.test, not by a bare test(', () => {
	const src = "Deno.test('a', () => {});\ntest('not a deno test', () => {});\n";
	assert.equal(counterFor('apps/backend/supabase/functions/x/y.test.ts')(src), 1);
	assert.equal(counterFor('apps/web/src/lib/y.test.ts')(src), 1);
});

test('a commented-out declaration is not counted, because the command is line-anchored', () => {
	assert.equal(counterFor('a/b_test.dart')("// test('disabled', () {});\n  test('live', () {});\n"), 1);
});

test('counterFor refuses a kind it cannot read rather than reporting zero', () => {
	assert.throws(() => counterFor('a/b.py'), /no counter knows how to read/);
});

test('claimsIn attributes the number that follows the path, not one further along', () => {
	assert.deepEqual(claimsIn('`a/b_test.dart` — 7 tests (3 added)'), [
		{ token: 'a/b_test.dart', count: 7, unit: 'tests', across: null },
	]);
	assert.deepEqual(claimsIn('`a/b.test.ts` (16) · `a/c.test.ts` (11 widget)'), [
		{ token: 'a/b.test.ts', count: 16, unit: 'tests', across: null },
		{ token: 'a/c.test.ts', count: 11, unit: 'tests', across: null },
	]);
});

test('claimsIn reads a round delta as NO count, so a delta is never kept current', () => {
	assert.deepEqual(claimsIn('`a/b_test.go` — 1 added'), [
		{ token: 'a/b_test.go', count: null, unit: 'tests', across: null },
	]);
	assert.deepEqual(claimsIn('`a/b_test.go` — 4 replaced'), [
		{ token: 'a/b_test.go', count: null, unit: 'tests', across: null },
	]);
});

test('claimsIn reads an approximate figure as no count', () => {
	assert.deepEqual(claimsIn('`a/b_test.dart` — ~55 tests'), [
		{ token: 'a/b_test.dart', count: null, unit: 'tests', across: null },
	]);
});

test('claimsIn separates a file count from a test count and reads "across N files"', () => {
	assert.deepEqual(claimsIn('`a/test/` — 541 files, byte-for-byte'), [
		{ token: 'a/test/', count: 541, unit: 'files', across: null },
	]);
	assert.deepEqual(claimsIn('`a/*.test.ts` — 145 tests across 13 files'), [
		{ token: 'a/*.test.ts', count: 145, unit: 'tests', across: 13 },
	]);
});

test('looksLikePath ignores a backticked symbol that is not a path', () => {
	assert.equal(looksLikePath('a/b_test.dart'), true);
	assert.equal(looksLikePath('b_test.dart'), true);
	assert.equal(looksLikePath('a/*.test.ts'), true);
	assert.equal(looksLikePath('a/test/'), true);
	assert.equal(looksLikePath('learn.md'), false);
	assert.equal(looksLikePath('movingTimeOf'), false);
});

test('globRe lets a doubled star span zero directories as well as many', () => {
	const re = globRe('a/**/*_test.go');
	assert.equal(re.test('a/x_test.go'), true);
	assert.equal(re.test('a/b/c/x_test.go'), true);
	assert.equal(re.test('b/x_test.go'), false);
	assert.equal(globRe('a/*_test.go').test('a/b/x_test.go'), false);
});

test('expander resolves an exact path, a directory prefix and a glob', () => {
	const e = expander(['a/one_test.go', 'a/b/two_test.go', 'a/notes.md']);
	assert.deepEqual(e('a/one_test.go'), ['a/one_test.go']);
	assert.deepEqual(e('a/b/'), ['a/b/two_test.go']);
	assert.deepEqual(e('a/**/*_test.go'), ['a/one_test.go', 'a/b/two_test.go']);
	assert.deepEqual(e('a/gone_test.go'), []);
});

test('censusHeadings stops at the divider and skips a heading inside a fence', () => {
	const md = [
		'### `a/one_test.go` — 1 tests',
		'```',
		'### not a heading',
		'```',
		'## Suite totals after the round',
		'### `a/two_test.go` — 2 tests',
	].join('\n');
	assert.deepEqual(
		censusHeadings(md).map((h) => h.heading),
		['`a/one_test.go` — 1 tests'],
	);
});

test('censusHeadings collects the per-file bullets under a heading', () => {
	const md = ['### `a/*_test.go` — 3 tests across 2 files', '', '- **`one_test.go`** — 1 tests', '- **`two_test.go`** — no count here'].join('\n');
	const [section] = censusHeadings(md);
	assert.deepEqual(
		section.bullets.map((b) => b.claim.token),
		['one_test.go'],
	);
});

test('sectionDir takes the fixed prefix of a glob heading', () => {
	assert.equal(sectionDir(claimsIn('`a/b/**/*.test.ts` — 1 tests')), 'a/b');
	assert.equal(sectionDir(claimsIn('`a/b/c_test.go` — 1 tests')), 'a/b');
	assert.equal(sectionDir(claimsIn('`a/b/` — 1 files')), 'a/b');
});

// ---------------------------------------------------------------------------
// check()
// ---------------------------------------------------------------------------

/** @param {Record<string, string>} files @returns {{ expand: (t: string) => string[], read: (p: string) => string }} */
function tree(files) {
	const e = expander(Object.keys(files));
	return {
		expand: e,
		read: (p) => {
			const hit = files[p];
			if (hit === undefined) throw new Error(`no such fixture file: ${p}`);
			return hit;
		},
	};
}

const ONE = 'func TestOne(t *testing.T) {}\n';
const TWO = `${ONE}func TestTwo(t *testing.T) {}\n`;

test('a heading whose count matches the file passes', () => {
	const t = tree({ 'a/one_test.go': TWO });
	const { errors, ok } = check('### `a/one_test.go` — 2 tests', t.expand, t.read, [], []);
	assert.deepEqual(errors, []);
	assert.match(ok[0], /^1 count\(s\) across 1 census heading\(s\) agree/);
});

test('a stale count fails, naming both figures', () => {
	const t = tree({ 'a/one_test.go': TWO });
	const { errors } = check('### `a/one_test.go` — 7 tests', t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states 7 tests where the recompute command counts 2/);
});

test('a heading naming a file that has moved fails', () => {
	const t = tree({ 'a/one_test.go': ONE });
	const { errors } = check('### `a/gone_test.go` — 1 tests', t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /names no file in the repository/);
});

test('a heading that names no file fails, so deleting the path is not an escape', () => {
	const t = tree({ 'a/one_test.go': ONE });
	const { errors } = check('### Some suites — 12 tests', t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /names no test file, so nothing can re-derive what it says/);
});

test('a heading that names a file and no count fails, so deleting the number is not an escape', () => {
	const t = tree({ 'a/one_test.go': ONE });
	const { errors } = check('### `a/one_test.go` — the loop guards', t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /carries no count/);
});

test('NOT_A_FILE_SECTION excuses a heading that names no file, and must match', () => {
	const t = tree({ 'a/one_test.go': ONE });
	const excuse = [{ heading: 'Some suites', reason: 'a shape, not a file set' }];
	assert.deepEqual(check('### Some suites — 12 tests', t.expand, t.read, excuse, []).errors, []);
	const stale = check('### `a/one_test.go` — 1 tests', t.expand, t.read, excuse, []);
	assert.equal(stale.errors.length, 1);
	assert.match(stale.errors[0], /matches no census heading. Delete it/);
});

test('PARAMETERISED leaves a runtime count alone, and must match', () => {
	const t = tree({ 'a/one_test.go': ONE });
	const param = [{ path: 'a/one_test.go', reason: 'one case per locale at run time' }];
	assert.deepEqual(check('### `a/one_test.go` — 99 tests', t.expand, t.read, [], param).errors, []);
	const other = tree({ 'a/two_test.go': ONE });
	const stale = check('### `a/two_test.go` — 1 tests', other.expand, other.read, [], param);
	assert.equal(stale.errors.length, 1);
	assert.match(stale.errors[0], /matches no census claim. Delete it/);
});

test('a glob heading checks the sum and the file count', () => {
	const t = tree({ 'a/one_test.go': ONE, 'a/b/two_test.go': TWO });
	assert.deepEqual(
		check('### `a/**/*_test.go` — 3 tests across 2 files', t.expand, t.read, [], []).errors,
		[],
	);
	const { errors } = check('### `a/**/*_test.go` — 3 tests across 5 files', t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states "across 5 files" where 2 match/);
});

test('a directory heading checks the file count', () => {
	const t = tree({ 'a/one_test.go': ONE, 'a/two_test.go': TWO });
	assert.deepEqual(check('### `a/` — 2 files, byte-for-byte', t.expand, t.read, [], []).errors, []);
	const { errors } = check('### `a/` — 9 files, byte-for-byte', t.expand, t.read, [], []);
	assert.match(errors[0], /states 9 files where 2 match/);
});

test('a bullet count is checked, and its bare path resolves against the section', () => {
	const md = [
		'### `a/**/*_test.go` — 3 tests across 2 files',
		'',
		'- **`one_test.go`** — 1 tests, the claim loop',
		'- **`b/two_test.go`** — 5 tests, the other one',
	].join('\n');
	const t = tree({ 'a/one_test.go': ONE, 'a/b/two_test.go': TWO });
	const { errors } = check(md, t.expand, t.read, [], []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /`b\/two_test\.go` states 5 tests where the recompute command counts 2/);
});

test('a bullet with no count is prose, not a failure — the heading above it carries the aggregate', () => {
	const md = ['### `a/**/*_test.go` — 1 tests across 1 files', '', '- **`one_test.go`** — the claim loop'].join('\n');
	const t = tree({ 'a/one_test.go': ONE });
	assert.deepEqual(check(md, t.expand, t.read, [], []).errors, []);
});
