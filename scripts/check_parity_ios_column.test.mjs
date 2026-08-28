// Unit tests for scripts/check_parity_ios_column.mjs.
//
// Run: `node --test scripts/check_parity_ios_column.test.mjs`
//
// The fixture is a miniature parity.md — a Legend, a rule block with the
// derivation table, and one platform table — so each case can break exactly
// one thing. The last case runs the real document, which is the only way to
// know the parser survives the escaped pipes, the `| Key |` tables and the
// 337 rows it actually has to read.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

import {
	audit,
	checkColumn,
	checkSingleStatement,
	checkVocabularyCoverage,
	MATRIX_PATH,
	markerFor,
	readLegendSymbols,
	readRows,
	readRuleBlock,
} from './check_parity_ios_column.mjs';
import { splitRow } from './markdown_lines.mjs';

const LEGEND = `## Legend

| Symbol | Meaning |
|---|---|
| \`✓\` | Shipped and working end-to-end on that platform. |
| \`Partial\` | Wired but unobserved. |
| \`✗\` | Not started. |
| \`N/A\` | Intentionally not applicable. |
| 🔸 in Notes | A web-canonical gap. |
`;

const RULE = `<!-- parity-ios-rule -->
### What an iOS cell means

Derived from the Android cell.

| Android cell | iOS cell |
|---|---|
| \`✓\` | \`Partial\` |
| \`Partial\` | \`Partial\` |
| \`✗\` | \`✗\` |
| \`N/A\` | \`N/A\` |

A departure states its obstruction.
<!-- /parity-ios-rule -->
`;

const HEADER = `| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |
|---|---|---|---|---|---|---|`;

/**
 * @param {string[]} rows
 * @param {string} [extra]
 */
const doc = (rows, extra = '') =>
	`${LEGEND}\n${RULE}\n${extra}\n${HEADER}\n${rows.join('\n')}\n`;

test('reads the Legend symbols and drops the Notes-convention row', () => {
	assert.deepEqual(readLegendSymbols(LEGEND), ['✓', 'Partial', '✗', 'N/A']);
});

test('reads the derivation out of the rule block rather than restating it', () => {
	const { errors, derivation } = readRuleBlock(RULE);
	assert.deepEqual(errors, []);
	assert.ok(derivation, 'the fixture rule block carries a derivation table');
	assert.equal(derivation.get('✓'), 'Partial');
	assert.equal(derivation.get('✗'), '✗');
	assert.equal(derivation.get('N/A'), 'N/A');
});

test('a second rule block is refused — the rule has one home', () => {
	const { errors } = readRuleBlock(`${RULE}\n${RULE}`);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /exactly one/);
	assert.match(errors[0], /2 opener/);
});

test('a rule block with no derivation table is refused', () => {
	const stripped = RULE.replace(/\| Android cell \| iOS cell \|[\s\S]*?\n\n/, '');
	const { errors, derivation } = readRuleBlock(stripped);
	assert.equal(derivation, null);
	assert.match(errors[0], /no derivation table/);
});

// A markdown row that opens fewer columns than its header used to reach
// `unquote(cells[1])` and die with a TypeError, so a malformed matrix took the
// guard down instead of failing it — a crashed guard reports no verdict at all.
test('a derivation row that opens one column is reported, not thrown on', () => {
	const broken = RULE.replace('| `✗` | `✗` |', '| `✗` |');
	const { errors, derivation } = readRuleBlock(broken);
	assert.ok(errors.some((e) => /fewer than two columns/.test(e)));
	assert.ok(derivation, 'the surviving rows still parse');
	assert.equal(derivation.has('✗'), false);
});

test('a Legend line that opens no columns states no symbol', () => {
	assert.deepEqual(readLegendSymbols(`${LEGEND}|\n`), ['✓', 'Partial', '✗', 'N/A']);
});

test('the derivation must cover every Legend symbol and invent none', () => {
	const legend = ['✓', 'Partial', '✗', 'N/A'];
	assert.deepEqual(checkVocabularyCoverage(legend, new Map([['✓', 'Partial']])).length, 3);
	const invented = checkVocabularyCoverage(legend, new Map([['?', 'Partial']]));
	assert.ok(invented.some((e) => /does not define/.test(e)));
});

test('prose outside the block that pairs iOS with a symbol is a second statement', () => {
	const text = doc([], 'iOS cells stay `✗` until each row is verified on a Mac.');
	const errors = checkSingleStatement(text);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /states a rule about what an iOS cell means/);
});

// Linking to the block was briefly the exemption, and it was a hole: the
// column key that had to be deleted BOTH linked to the block and contradicted
// it, so the guard passed on the exact sentence it exists to catch.
test('linking to the block does not buy the exemption', () => {
	const text = doc(
		[],
		'iOS cells stay `✗` until verified — see [the rule](#what-an-ios-cell-means).',
	);
	assert.equal(checkSingleStatement(text).length, 1);
});

test('naming iOS without a symbol, or a symbol without iOS, is not a statement', () => {
	assert.deepEqual(checkSingleStatement(doc([], 'The iOS build is deferred.')), []);
	assert.deepEqual(checkSingleStatement(doc([], 'A Web cell may be `N/A`.')), []);
});

test('a table row is never read as prose', () => {
	const text = doc(['| Thing | ✓ | ✗ | ✓ | N/A | N/A | **iOS ✗:** no iOS handler. |']);
	assert.deepEqual(checkSingleStatement(text), []);
});

const derivation = new Map([
	['✓', 'Partial'],
	['Partial', 'Partial'],
	['✗', '✗'],
	['N/A', 'N/A'],
]);

test('a derived column passes', () => {
	const { rows } = readRows(
		doc([
			'| Shipped | ✓ | Partial | ✓ | N/A | N/A | Notes. |',
			'| Unbuilt | ✗ | ✗ | ✓ | N/A | N/A | Notes. |',
			'| Hardware | N/A | N/A | ✓ | N/A | N/A | Notes. |',
		]),
	);
	const { errors, marked } = checkColumn(rows, derivation);
	assert.deepEqual(errors, []);
	assert.deepEqual(marked, []);
});

test('the § 707 failure: iOS `✗` under an Android `✓` with nothing obstructing', () => {
	const { rows } = readRows(doc(['| Backup restore | ✓ | ✗ | ✓ | N/A | N/A | Same BackupService. |']));
	const { errors } = checkColumn(rows, derivation);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /iOS is `✗` but Android is `✓`/);
	assert.match(errors[0], /add `\*\*iOS ✗:\*\* <why>`/);
});

test('a bare iOS `✓` is refused — the derivation never produces one', () => {
	const { rows } = readRows(doc(['| Anything | ✓ | ✓ | ✓ | N/A | N/A | Notes. |']));
	const { errors } = checkColumn(rows, derivation);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /asserts someone ran this row/);
});

test('a marker cannot buy the `✓` — only the derivation table can', () => {
	const { rows } = readRows(doc(['| Anything | ✓ | ✓ | ✓ | N/A | N/A | **iOS ✓:** trust me. |']));
	const { errors, marked } = checkColumn(rows, derivation);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /No Notes marker can grant it/);
	assert.deepEqual(marked, []);
});

test('a verified column is expressible — the derivation table is the one edit', () => {
	const verified = new Map(derivation).set('✓', '✓');
	const { rows } = readRows(doc(['| Anything | ✓ | ✓ | ✓ | N/A | N/A | Notes. |']));
	assert.deepEqual(checkColumn(rows, verified).errors, []);
});

test('a departure passes once its Notes name the obstruction', () => {
	const { rows } = readRows(
		doc(['| Lock screen | ✓ | ✗ | N/A | ✓ | ✓ | **iOS ✗:** the channel has an Android handler only. |']),
	);
	const { errors, marked } = checkColumn(rows, derivation);
	assert.deepEqual(errors, []);
	assert.equal(marked.length, 1);
	assert.match(marked[0], /Lock screen/);
});

test('the marker must name the symbol the cell actually carries', () => {
	const { rows } = readRows(doc(['| Lock screen | ✓ | ✗ | N/A | ✓ | ✓ | **iOS N/A:** wrong symbol. |']));
	const { errors } = checkColumn(rows, derivation);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /iOS is `✗`/);
});

test('a marker on a cell that is merely the derivation is the per-row habit, and fails', () => {
	const { rows } = readRows(doc(['| Anything | ✓ | Partial | ✓ | N/A | N/A | **iOS Partial:** pending a Mac. |']));
	const { errors } = checkColumn(rows, derivation);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /restates the rule per row/);
});

test('markerFor spells the marker the failure message tells you to write', () => {
	assert.equal(markerFor('N/A'), '**iOS N/A:**');
});

test('rows survive an escaped pipe in the Notes column', () => {
	const { rows } = readRows(doc(['| Thing | ✓ | Partial | ✓ | N/A | N/A | `all \\| important \\| off`. |']));
	assert.equal(rows.length, 1);
	assert.equal(rows[0].ios, 'Partial');
	assert.match(rows[0].notes, /all \\\| important/);
});

test('the committed docs/product/parity.md passes every rule', () => {
	const { errors, rows } = audit(readFileSync(MATRIX_PATH, 'utf8'));
	assert.deepEqual(errors, []);
	assert.ok(rows > 300, `expected the real matrix, parsed ${rows} rows`);
});

test('the committed matrix carries no iOS `✓`, which is the rule in one assertion', () => {
	const { rows } = readRows(readFileSync(MATRIX_PATH, 'utf8'));
	assert.deepEqual(rows.filter((r) => r.ios === '✓'), []);
});

// --- Soft wraps and optional pipes. decisions § 774.

test('rule 2 catches a second statement that has been soft-wrapped', () => {
	// Markdown wraps a paragraph freely and the wrap changes nothing about what
	// the document says. Requiring `iOS` and the symbol on one PHYSICAL line
	// let the wrapped form of the exact sentence this rule exists to catch
	// walk past it.
	const flat = 'Note that on iOS a `Partial` cell means the Dart shipped but nobody ran it.';
	const wrapped = 'Note that on iOS a cell reading\n`Partial` means the Dart shipped but nobody ran it.';

	assert.equal(checkSingleStatement(doc([], flat)).length, 1);
	const errors = checkSingleStatement(doc([], wrapped));
	assert.equal(errors.length, 1);
	assert.match(errors[0], /Partial/);
});

test('rule 2 does not join two unrelated list items into one statement', () => {
	const list = '- The iOS build is deferred.\n- A Web cell may be `N/A`.';
	assert.deepEqual(checkSingleStatement(doc([], list)), []);
});

test('a row written without its trailing pipe keeps its Notes cell', () => {
	// GFM makes the wrapping pipes optional. `slice(1, -1)` ate the last cell,
	// so rule 4 read the Apple Watch column as the notes and demanded a marker
	// that was already there.
	const notes = `${markerFor('✗')} no iOS handler for the method channel.`;
	const cells = `| Thing | ✓ | ✗ | ✓ | N/A | N/A | ${notes}`;

	assert.equal(splitRow(`${cells} |`).length, 7);
	assert.equal(splitRow(cells).length, 7);

	const { derivation } = readRuleBlock(RULE);
	assert.ok(derivation);
	for (const row of [`${cells} |`, cells]) {
		const { rows: parsed, errors: rowErrors } = readRows(doc([row]));
		assert.deepEqual(rowErrors, []);
		assert.equal(parsed.length, 1);
		assert.equal(parsed[0].notes, notes);
		assert.deepEqual(checkColumn(parsed, derivation).errors, []);
	}
});

test('a row written without either wrapping pipe still parses', () => {
	assert.deepEqual(splitRow('a | b | c'), ['a', 'b', 'c']);
	assert.deepEqual(splitRow('| a | b | c |'), ['a', 'b', 'c']);
});

// --- The optional LEADING pipe. decisions § 779.
//
// GFM makes it optional exactly as it makes the trailing one optional, and the
// row renders identically. All three of this script's readers found their rows
// with `line.startsWith('|')`, so such a row was invisible to every one of them
// rather than misgraded by one — and `readRows` reset its header on it, so the
// whole rest of the table went with it.

test('a row written without its leading pipe is graded, not skipped', () => {
	const { rows, errors } = readRows(doc(['Anything | ✓ | ✓ | ✓ | N/A | N/A | Notes. |']));
	assert.deepEqual(errors, []);
	assert.equal(rows.length, 1);
	assert.equal(rows[0].ios, '✓');
	assert.match(checkColumn(rows, derivation).errors[0], /asserts someone ran this row/);
});

test('a row written with no pipe at either end is graded too', () => {
	const { rows } = readRows(doc(['Anything | ✓ | ✓ | ✓ | N/A | N/A | Notes.']));
	assert.equal(rows.length, 1);
	assert.equal(rows[0].notes, 'Notes.');
});

test('one leading-pipe-less row does not take the rest of its table with it', () => {
	const { rows } = readRows(
		doc([
			'| Before | ✓ | Partial | ✓ | N/A | N/A | Notes. |',
			'Middle | ✓ | Partial | ✓ | N/A | N/A | Notes. |',
			'| After | ✓ | Partial | ✓ | N/A | N/A | Notes. |',
		]),
	);
	assert.deepEqual(rows.map((r) => r.feature), ['Before', 'Middle', 'After']);
});

test('the Legend and the derivation survive a row of their own written that way', () => {
	assert.deepEqual(readLegendSymbols(LEGEND.replace('| `✗` |', '`✗` |')), ['✓', 'Partial', '✗', 'N/A']);
	const { errors, derivation: parsed } = readRuleBlock(RULE.replace('| `✗` | `✗` |', '`✗` | `✗` |'));
	assert.deepEqual(errors, []);
	assert.equal(parsed?.get('✗'), '✗');
});

test('such a row is exempt from rule 2, which grades prose', () => {
	const notes = `${markerFor('✗')} no iOS handler for the method channel.`;
	assert.deepEqual(checkSingleStatement(doc([`Lock screen | ✓ | ✗ | N/A | ✓ | ✓ | ${notes} |`])), []);
});

test('a row whose columns do not line up with its header is reported, not skipped', () => {
	const { rows, errors } = readRows(doc(['| Short | ✓ | Partial | ✓ |']));
	assert.deepEqual(rows, []);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /opens 4 column\(s\) where the table's header opens 7/);
});

// A table-aware reader gains a way to lose rows the old walk did not have:
// break the delimiter's width and GFM opens no table at all, so every row under
// it stops existing. Two committed docs are in that state today.
test('a table whose delimiter went wrong is reported rather than silently lost', () => {
	const { rows, errors } = readRows(
		`${LEGEND}\n${RULE}\n${HEADER.replace('|---|---|---|---|---|---|---|', '|---|---|')}\n` +
			'| Thing | ✓ | Partial | ✓ | N/A | N/A | Notes. |\n',
	);
	assert.deepEqual(rows, []);
	assert.equal(errors.length, 3);
	for (const e of errors) assert.match(e, /belongs to no table/);
});

test('the committed matrix leaves no pipe-leading line outside a table', () => {
	assert.deepEqual(readRows(readFileSync(MATRIX_PATH, 'utf8')).errors, []);
});
