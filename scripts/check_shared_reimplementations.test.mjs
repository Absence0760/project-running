// Unit tests for scripts/check_shared_reimplementations.mjs.
//
// The fixtures are not invented: the two central cases are the historical
// instances themselves — § 1340's `dm_recipients` fold (a copy missing the
// final-sigma step) and the round-42 exercise-catalogue picker's
// byte-identical `compareFoldedNames`. Each is asserted twice: once as it was
// written, and once with every name in it changed, which is the property the
// guard exists to have.

import test from 'node:test';
import assert from 'node:assert/strict';

import {
	MIN_BODY_TOKENS,
	MIN_SHARED_OPS,
	REGISTERED,
	bodyFingerprint,
	declaredNames,
	distinctiveOperations,
	extractFunctions,
	findReimplementations,
	patternNames,
	reconcile,
	svelteScript,
	tokenize,
} from './check_shared_reimplementations.mjs';

const LIB = 'apps/web/src/lib';

/** The canonical fold, verbatim from `segments/catalogue_browse.ts`. */
const CANONICAL_FOLD = `
export function fold(value: string): string {
	return value
		.normalize('NFD')
		.replace(/\\p{Diacritic}/gu, '')
		.toLowerCase()
		.replace(/\\u03c2/g, '\\u03c3');
}
`;

/** § 1340's copy: the same fold with the final-sigma collapse missing. */
const PRIVATE_FOLD_MISSING_SIGMA = `
function fold(value: string): string {
	return value
		.normalize('NFD')
		.replace(/\\p{Diacritic}/gu, '')
		.toLowerCase();
}
`;

/** The same copy with the function, its parameter and its shape all changed. */
const PRIVATE_FOLD_RENAMED = `
function searchKeyFor(candidate: string): string {
	const stripped = candidate.normalize('NFD').replace(/\\p{Diacritic}/gu, '');
	return stripped.toLowerCase();
}
`;

/** The canonical comparator, verbatim from `segments/catalogue_browse.ts`. */
const CANONICAL_COMPARE = `
export function compareFoldedNames(aName: string, aId: string, bName: string, bId: string): number {
	const fa = fold(aName);
	const fb = fold(bName);
	if (fa !== fb) return fa < fb ? -1 : 1;
	if (aId !== bId) return aId < bId ? -1 : 1;
	return 0;
}
`;

/** The round-42 instance with every identifier in it renamed. */
const PRIVATE_COMPARE_RENAMED = `
function orderEntries(leftName: string, leftKey: string, rightName: string, rightKey: string): number {
	const l = fold(leftName);
	const r = fold(rightName);
	if (l !== r) return l < r ? -1 : 1;
	if (leftKey !== rightKey) return leftKey < rightKey ? -1 : 1;
	return 0;
}
`;

const one = (/** @type {string} */ src) => {
	const fns = extractFunctions(src);
	assert.equal(fns.length, 1, 'fixture should hold exactly one function');
	return fns[0];
};

// ── tokenizer ────────────────────────────────────────────────────────────

test('tokenize: a regex after `.replace(` is one token, not two divisions', () => {
	const toks = tokenize("x.replace(/\\p{Diacritic}/gu, '')");
	const regexes = toks.filter((t) => t.kind === 'regex');
	assert.equal(regexes.length, 1);
	assert.equal(regexes[0].text, '/\\p{Diacritic}/gu');
});

test('tokenize: a `/` after a value divides rather than opening a regex', () => {
	const toks = tokenize('const r = total / count;');
	assert.equal(toks.filter((t) => t.kind === 'regex').length, 0);
	assert.ok(toks.some((t) => t.kind === 'punct' && t.text === '/'));
});

test('tokenize: comments and whitespace are dropped, string contents are not', () => {
	const a = tokenize("// a comment\nconst x = 'NFD'; /* block */");
	const b = tokenize("const x   =\n'NFD';");
	assert.deepEqual(a.map((t) => t.text), b.map((t) => t.text));
	assert.ok(a.some((t) => t.kind === 'string' && t.text === "'NFD'"));
});

test('tokenize: a template literal with an interpolation is one token', () => {
	const toks = tokenize('const s = `a${b + `${c}`}d`;');
	assert.equal(toks.filter((t) => t.kind === 'template').length, 1);
});

test('tokenize: an escaped quote does not end the string', () => {
	const toks = tokenize("const s = 'it\\'s';");
	assert.equal(toks.filter((t) => t.kind === 'string').length, 1);
});

// ── extraction ───────────────────────────────────────────────────────────

test('extractFunctions: finds declarations, const arrows and expression bodies', () => {
	const fns = extractFunctions(`
		export function a(x: number): number { return x + 1; }
		const b = (y: string): string => { return y; };
		export const c = (z: number) => z * 2;
	`);
	assert.deepEqual(fns.map((f) => f.name), ['a', 'b', 'c']);
	assert.deepEqual(fns.map((f) => f.exported), [true, false, true]);
});

test('extractFunctions: a generic signature does not hide the function', () => {
	const fns = extractFunctions('function byName<E extends Row>(a: E, b: E): number { return 0; }');
	assert.deepEqual(fns.map((f) => f.name), ['byName']);
});

test('extractFunctions: reads the script of a Svelte component and not its markup', () => {
	const fns = extractFunctions(
		svelteScript('<script lang="ts">\n function f() { return 1; }\n</script>\n<p>function g() {}</p>'),
	);
	assert.deepEqual(fns.map((f) => f.name), ['f']);
});

// ── bound names ──────────────────────────────────────────────────────────

test('declaredNames: parameters, locals, destructuring and catch bindings', () => {
	const fn = one(`
		function f(a: string, { b, c: renamed }: Opts) {
			const d = a;
			let [e, g] = split(d);
			try { work(); } catch (err) { report(err); }
			return b + renamed + e + g;
		}
	`);
	const names = declaredNames(fn);
	for (const n of /** @type {string[]} */ (['a', 'b', 'renamed', 'd', 'e', 'g', 'err'])) {
		assert.ok(names.has(n), `expected ${n} to be bound`);
	}
	assert.ok(!names.has('split'), 'a free name is not bound');
	assert.ok(!names.has('report'), 'a free name is not bound');
});

test('patternNames: a `{ key: binding }` pattern binds the BINDING, not the key', () => {
	assert.deepEqual([...patternNames(tokenize('{ b, c: renamed }'))].sort(), ['b', 'renamed']);
});

test('patternNames: an inline object TYPE is not a destructuring pattern', () => {
	// The defect the register caught: read as a pattern, `{ lng: number; lat: number }`
	// binds `number`, and every `number` in the body is then alpha-renamed — which
	// made two byte-identical haversines disagree.
	assert.deepEqual([...patternNames(tokenize('a: { lng: number; lat: number }, b: TrackPoint'))].sort(), ['a', 'b']);
});

test('patternNames: a default value is a free name, not a binding', () => {
	assert.deepEqual([...patternNames(tokenize('a, b = FALLBACK'))].sort(), ['a', 'b']);
});

test('bodyFingerprint: two identical bodies agree whether the parameter type is named or inline', () => {
	// `[0]` and not `one()`: the inner `const toRad = ...` is itself a named
	// arrow, so each fixture holds two functions.
	const named = extractFunctions('function f(a: Pt, b: Pt): number { const toRad = (d: number) => d; return toRad(a.lat) - toRad(b.lat); }')[0];
	const inline = extractFunctions('function g(p: { lat: number }, q: { lat: number }): number { const toRad = (d: number) => d; return toRad(p.lat) - toRad(q.lat); }')[0];
	assert.equal(bodyFingerprint(named).fingerprint, bodyFingerprint(inline).fingerprint);
});

// ── anchor A: the normalised body ────────────────────────────────────────

test('bodyFingerprint: renaming the function, its parameters and its locals does not change it', () => {
	assert.equal(
		bodyFingerprint(one(CANONICAL_COMPARE)).fingerprint,
		bodyFingerprint(one(PRIVATE_COMPARE_RENAMED)).fingerprint,
	);
});

test('bodyFingerprint: reformatting and re-commenting does not change it', () => {
	const a = one('function f(x: number) { /* why */ return x + 1; }');
	const b = one('function g(y: number) {\n\t// a different comment\n\treturn (y)\n\t\t+ 1;\n}');
	assert.notEqual(
		bodyFingerprint(a).fingerprint,
		bodyFingerprint(b).fingerprint,
		'the parenthesis is a real token and is not normalised away',
	);
	const c = one('function h(y: number) {\n\t// a different comment\n\treturn y\n\t\t+ 1;\n}');
	assert.equal(bodyFingerprint(a).fingerprint, bodyFingerprint(c).fingerprint);
});

test('bodyFingerprint: a property name is behaviour and survives verbatim', () => {
	const a = one('function f(v: string) { return v.toLowerCase(); }');
	const b = one('function f(v: string) { return v.toUpperCase(); }');
	assert.notEqual(bodyFingerprint(a).fingerprint, bodyFingerprint(b).fingerprint);
});

test('bodyFingerprint: a local colliding with a property name does not erase the property', () => {
	const withLocal = bodyFingerprint(one('function f(name: string) { const length = name.length; return length; }'));
	const renamed = bodyFingerprint(one('function f(v: string) { const n = v.length; return n; }'));
	assert.equal(withLocal.fingerprint, renamed.fingerprint, 'the local is a spelling and is erased');
	assert.ok(
		withLocal.fingerprint.split('\u0000').includes('length'),
		'the property read survives as a token even though a local shares its name',
	);
});

test('bodyFingerprint: a free name is behaviour and is not renamed', () => {
	const a = one('function f(x: number) { return Math.round(x); }');
	const b = one('function f(x: number) { return Math.floor(x); }');
	assert.notEqual(bodyFingerprint(a).fingerprint, bodyFingerprint(b).fingerprint);
});

test('bodyFingerprint: a literal is behaviour and is not renamed', () => {
	const a = one("function f(v: string) { return v.normalize('NFD'); }");
	const b = one("function f(v: string) { return v.normalize('NFC'); }");
	assert.notEqual(bodyFingerprint(a).fingerprint, bodyFingerprint(b).fingerprint);
});

// ── anchor B: distinctive operations ─────────────────────────────────────

test('distinctiveOperations: only calls carrying a literal argument count', () => {
	const ops = distinctiveOperations(one(CANONICAL_FOLD));
	assert.deepEqual(ops, ["normalize('NFD')", "replace(/\\p{Diacritic}/gu,'')", "replace(/\\u03c2/g,'\\u03c3')"]);
	assert.ok(!ops.some((o) => o.startsWith('toLowerCase')), 'a bare call names no helper');
});

test('distinctiveOperations: survives renaming everything around the call', () => {
	assert.deepEqual(
		distinctiveOperations(one(PRIVATE_FOLD_MISSING_SIGMA)),
		distinctiveOperations(one(PRIVATE_FOLD_RENAMED)),
	);
});

test('distinctiveOperations: a literal in a nested call belongs to that call', () => {
	const ops = distinctiveOperations(one("function f(v: string) { return v.map((x) => x.trim('a')); }"));
	assert.deepEqual(ops, ["trim('a')"]);
});

// ── the two anchors over a synthetic tree ────────────────────────────────

const shared = { file: `${LIB}/segments/catalogue_browse.ts`, source: CANONICAL_FOLD + CANONICAL_COMPARE };

test('findReimplementations: names the § 1340 copy, which anchor A cannot see', () => {
	const findings = findReimplementations([
		shared,
		{ file: `${LIB}/social/dm_recipients.ts`, source: PRIVATE_FOLD_MISSING_SIGMA },
	]);
	assert.equal(findings.length, 1);
	assert.equal(findings[0].kind, 'ops', 'a copy that omits a step has a different body');
	assert.deepEqual(
		findings[0].members.map((m) => m.name).sort(),
		['fold', 'fold'],
	);
	assert.ok(findings[0].detail.includes("normalize('NFD')"));
});

test('findReimplementations: names the § 1340 copy after every name in it changes', () => {
	const findings = findReimplementations([
		shared,
		{ file: `${LIB}/social/dm_recipients.ts`, source: PRIVATE_FOLD_RENAMED },
	]);
	assert.equal(findings.length, 1);
	assert.ok(findings[0].members.some((m) => m.name === 'searchKeyFor'));
});

test('findReimplementations: names a byte-identical copy through anchor A', () => {
	const findings = findReimplementations([
		shared,
		{ file: `${LIB}/components/exercise_catalogue_picker.ts`, source: CANONICAL_COMPARE.replace('export ', '') },
	]);
	const clone = findings.find((f) => f.kind === 'clone');
	assert.ok(clone, 'anchor A should name the identical body');
	assert.equal(new Set(clone.members.map((m) => m.file)).size, 2);
});

test('findReimplementations: anchor A survives renaming the copy end to end', () => {
	const findings = findReimplementations([
		shared,
		{ file: `${LIB}/components/exercise_catalogue_picker.ts`, source: PRIVATE_COMPARE_RENAMED },
	]);
	const clone = findings.find((f) => f.kind === 'clone');
	assert.ok(clone);
	assert.ok(clone.members.some((m) => m.name === 'orderEntries'));
});

test('findReimplementations: importing the shared export instead of copying it says nothing', () => {
	const findings = findReimplementations([
		shared,
		{
			file: `${LIB}/social/dm_recipients.ts`,
			source: `import { fold } from '../segments/catalogue_browse';
				export function filterDmRecipients(rows: Row[], query: string): Row[] {
					const q = fold(query.trim());
					return rows.filter((r) => fold(r.displayName).includes(q));
				}`,
		},
	]);
	assert.deepEqual(findings, []);
});

test('findReimplementations: a copy of something the shared tree does not EXPORT is not this class', () => {
	const findings = findReimplementations([
		{ file: `${LIB}/segments/catalogue_browse.ts`, source: CANONICAL_COMPARE.replace('export ', '') },
		{ file: `${LIB}/components/exercise_catalogue_picker.ts`, source: PRIVATE_COMPARE_RENAMED },
	]);
	assert.deepEqual(findings, [], 'nothing was importable, so nothing was ignored');
});

test('findReimplementations: two copies of a body under the size floor say nothing', () => {
	const tiny = 'export function idOf(row: Row): string { return row.id; }';
	const { size } = bodyFingerprint(one(tiny));
	assert.ok(size < MIN_BODY_TOKENS, 'fixture must be under the floor');
	assert.deepEqual(
		findReimplementations([
			{ file: `${LIB}/a.ts`, source: tiny },
			{ file: `${LIB}/b.ts`, source: tiny.replace('export ', '') },
		]),
		[],
	);
});

test('findReimplementations: one shared operation is a coincidence, not a copy', () => {
	const findings = findReimplementations([
		{ file: `${LIB}/a.ts`, source: "export function load(db: Db) { return db.from('runs').select('x'); }" },
		{ file: `${LIB}/b.ts`, source: "function reload(db: Db) { return db.from('runs').eq('id', 1); }" },
	]);
	assert.deepEqual(findings, []);
	assert.equal(MIN_SHARED_OPS, 2);
});

test('findReimplementations: an operation held widely is not distinctive', () => {
	const holder = (/** @type {number} */ n) => ({
		file: `${LIB}/w${n}.ts`,
		source: `function w${n}(el: El) { el.setAttribute('role', 'x'); el.setAttribute('aria-label', 'y'); }`,
	});
	const files = [
		{
			file: `${LIB}/shared.ts`,
			source: "export function tag(el: El) { el.setAttribute('role', 'x'); el.setAttribute('aria-label', 'y'); }",
		},
		holder(1), holder(2), holder(3), holder(4),
	];
	assert.ok(
		!findReimplementations(files).some((f) => f.kind === 'ops'),
		'five holders of each operation makes neither distinctive',
	);
});

test('findReimplementations: two functions in the SAME file are not a cross-module copy', () => {
	assert.deepEqual(
		findReimplementations([
			{ file: `${LIB}/one.ts`, source: CANONICAL_FOLD + PRIVATE_FOLD_MISSING_SIGMA.replace('fold', 'fold2') },
		]),
		[],
	);
});

// ── the register ─────────────────────────────────────────────────────────

test('reconcile: a finding nobody registered is reported', () => {
	const findings = /** @type {import('./check_shared_reimplementations.mjs').Finding[]} */ ([
		{ kind: 'clone', key: 'a.ts:f|b.ts:g', members: [], detail: '' },
	]);
	const { unregistered, stale } = reconcile(findings, []);
	assert.equal(unregistered.length, 1);
	assert.equal(stale.length, 0);
});

test('reconcile: a registration matching no finding is STALE and reported', () => {
	const { unregistered, stale } = reconcile([], [{ kind: 'clone', key: 'a.ts:f|b.ts:g', reason: 'gone' }]);
	assert.equal(unregistered.length, 0);
	assert.equal(stale.length, 1);
	assert.equal(stale[0].reason, 'gone');
});

test('reconcile: a registration for the other ANCHOR does not excuse a finding', () => {
	const findings = /** @type {import('./check_shared_reimplementations.mjs').Finding[]} */ ([
		{ kind: 'clone', key: 'a.ts:f|b.ts:g', members: [], detail: '' },
	]);
	const { unregistered, stale } = reconcile(findings, [{ kind: 'ops', key: 'a.ts:f|b.ts:g', reason: 'wrong kind' }]);
	assert.equal(unregistered.length, 1, 'the kind is part of the identity');
	assert.equal(stale.length, 1);
});

test('REGISTERED: every entry names its members and says what the thing IS', () => {
	assert.ok(REGISTERED.length > 0);
	for (const r of REGISTERED) {
		assert.ok(r.kind === 'clone' || r.kind === 'ops', `bad kind on ${r.key}`);
		assert.ok(r.key.includes('|'), `a registration names at least two members: ${r.key}`);
		for (const member of r.key.split('|')) {
			assert.match(member, /^apps\/web\/src\/.+:[^:]+$/, `malformed member ${member}`);
		}
		assert.ok(r.reason.length >= 80, `reason too thin to be a verdict: ${r.key}`);
	}
});

test('REGISTERED: no key is registered twice', () => {
	const keys = REGISTERED.map((r) => r.kind + ' ' + r.key);
	assert.equal(new Set(keys).size, keys.length);
});
