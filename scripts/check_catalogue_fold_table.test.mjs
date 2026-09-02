import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import {
	describeDrift,
	describeFirstDifference,
	stampedUnicodeVersion,
} from './check_catalogue_fold_table.mjs';
import {
	OUTPUT_PATH,
	buildFoldTable,
	dartLiteral,
	decomposeHangul,
	render,
	webFold,
} from './gen_catalogue_fold_table.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const committed = readFileSync(join(REPO_ROOT, OUTPUT_PATH), 'utf8');

const STAMP = "const String kCatalogueFoldUnicodeVersion = '17.0';";

test('no drift when the committed render is the fresh one', () => {
	assert.deepEqual(
		describeDrift({ committed: STAMP, fresh: STAMP, runtimeUnicode: '17.0' }),
		[],
	);
});

test('a missing file is reported as generated-not-written', () => {
	const errors = describeDrift({ committed: null, fresh: STAMP, runtimeUnicode: '17.0' });
	assert.equal(errors.length, 1);
	assert.match(errors[0], /is missing/);
	assert.match(errors[0], /gen_catalogue_fold_table\.mjs/);
});

test('a Unicode-version gap is named as an ICU bump, not a hand-edit', () => {
	// The whole point of stamping the version into the file: this failure is
	// reached by a Node upgrade on a PR that touched none of it, and sending
	// the reader hunting for an edit they did not make wastes the CI run.
	const errors = describeDrift({
		committed: "const String kCatalogueFoldUnicodeVersion = '16.0';\nold",
		fresh: "const String kCatalogueFoldUnicodeVersion = '17.0';\nnew",
		runtimeUnicode: '17.0',
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Unicode 16\.0 and this Node carries Unicode 17\.0/);
	assert.doesNotMatch(errors[0], /hand-edit/);
});

test('a same-version difference is named as a hand-edit or a stale commit', () => {
	const errors = describeDrift({
		committed: "const String kCatalogueFoldUnicodeVersion = '17.0';\n0x0041,",
		fresh: "const String kCatalogueFoldUnicodeVersion = '17.0';\n0x0042,",
		runtimeUnicode: '17.0',
	});
	assert.equal(errors.length, 1);
	assert.match(errors[0], /hand-edit or a commit that skipped the generator/);
	assert.match(errors[0], /first difference at line 2/);
});

test('a render that lost its version stamp is itself reported', () => {
	// Without the stamp the guard cannot tell the two causes apart, so it says
	// so rather than silently collapsing them into one message.
	const errors = describeDrift({ committed: 'a', fresh: 'b', runtimeUnicode: '17.0' });
	assert.ok(errors.some((e) => /carries no `kCatalogueFoldUnicodeVersion` line/.test(e)));
});

test('describeFirstDifference names the line, including a truncation', () => {
	assert.match(describeFirstDifference('a\nb\nc', 'a\nb\nd'), /line 3/);
	assert.match(describeFirstDifference('a\nb', 'a'), /<end of file>/);
});

test('the committed table carries a Unicode version stamp', () => {
	// Anti-vacuity: every message above leans on this line existing.
	assert.match(stampedUnicodeVersion(committed) ?? '', /^\d+\.\d+$/);
});

test('the committed table is what the generator renders', () => {
	assert.deepEqual(
		describeDrift({
			committed,
			fresh: render(),
			runtimeUnicode: process.versions.unicode ?? 'unknown',
		}),
		[],
	);
});

test('the committed keys are strictly ascending and parallel to the values', () => {
	// The Dart side binary-searches the keys, so an unsorted table would not
	// fail loudly — it would silently stop folding some of the letters.
	const keys = listBody(committed, 'kCatalogueFoldKeys')
		.split(',')
		.map((s) => s.trim())
		.filter(Boolean)
		.map((s) => Number.parseInt(s, 16));
	const values = listBody(committed, 'kCatalogueFoldValues').match(/'(?:[^'\\]|\\.)*'/g) ?? [];
	assert.ok(keys.length > 4000, `expected a table of thousands, got ${keys.length}`);
	assert.equal(keys.length, values.length);
	for (let i = 1; i < keys.length; i++) {
		assert.ok(keys[i] > keys[i - 1], `key ${i} (0x${keys[i].toString(16)}) is out of order`);
	}
});

test('the Hangul arithmetic reproduces NFD across the whole syllable block', () => {
	// The 11,172 rows the table does not carry. buildFoldTable throws if this
	// ever stops holding; this asserts it independently rather than trusting
	// that the throw is reachable.
	for (let cp = 0xac00; cp <= 0xd7a3; cp++) {
		const jamo = decomposeHangul(cp);
		assert.ok(jamo !== null);
		assert.equal(String.fromCodePoint(...jamo), webFold(String.fromCodePoint(cp)));
	}
	assert.equal(decomposeHangul(0xabff), null);
	assert.equal(decomposeHangul(0xd7a4), null);
});

test('the generator folds the classes the hand table missed', () => {
	// The generator's own copy of the fold is what the table is derived from, so
	// it gets the same vectors both client suites carry.
	assert.equal(webFold('Đèo Hải Vân'), 'đeo hai van');
	assert.equal(webFold('Ἀθήνα'), 'αθηνα');
	assert.equal(webFold('ΟΔΟΣ'), webFold('οδος'));
	assert.equal(webFold('Huángshān'), 'huangshan');
	assert.equal(webFold('a´b'), 'ab');
	// And leaves the letters with no canonical decomposition alone.
	assert.equal(webFold('Øst Đông Straße'), 'øst đong straße');
});

test('the table holds every code point the fold rewrites, Hangul aside', () => {
	const { entries, hangul } = buildFoldTable();
	assert.equal(hangul, 11172);
	const covered = new Set(entries.map((e) => e.cp));
	for (const cp of [0x1ea2, 0x01ce, 0x0401, 0x00b4, 0x10c7, 0xf900, 0x03c2, 0x0041]) {
		assert.ok(covered.has(cp), `U+${cp.toString(16).toUpperCase()} should be in the table`);
	}
	// A letter with no canonical decomposition must NOT be.
	for (const cp of [0x00f8, 0x0111, 0x00df, 0x0142]) {
		assert.ok(!covered.has(cp), `U+${cp.toString(16).toUpperCase()} must stay unfolded`);
	}
});

test('dartLiteral emits ASCII-only, escaping what Dart would read', () => {
	assert.equal(dartLiteral('a'), "'a'");
	assert.equal(dartLiteral("'"), "'\\''");
	assert.equal(dartLiteral('\\'), "'\\\\'");
	assert.equal(dartLiteral('$'), "'\\$'");
	assert.equal(dartLiteral('́'), "'\\u{301}'");
	assert.equal(dartLiteral(''), "''");
});

/**
 * The body of one of the generated file's two top-level lists.
 *
 * @param {string} text
 * @param {string} name
 * @returns {string}
 */
function listBody(text, name) {
	const open = text.indexOf(`${name} = <`);
	assert.notEqual(open, -1, `could not find the ${name} list in the committed table`);
	const start = text.indexOf('[', open);
	const end = text.indexOf('\n];', start);
	assert.ok(start !== -1 && end > start, `the ${name} list is not bracketed as expected`);
	return text.slice(start + 1, end);
}
