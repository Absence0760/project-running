import test from 'node:test';
import assert from 'node:assert/strict';

import { foldSoftWraps, foldedLines, markdownTables, splitRow, tableLines } from './markdown_lines.mjs';

test('a wrapped sentence folds back into one line', () => {
	assert.equal(foldSoftWraps('On iOS a cell reading\n`Partial` means\nnobody ran it.'), 'On iOS a cell reading `Partial` means nobody ran it.');
});

test('blank lines keep paragraphs apart', () => {
	assert.equal(foldSoftWraps('one\nwrapped\n\ntwo\n'), 'one wrapped\n\ntwo\n');
});

test('a line that opens a block starts a new one', () => {
	for (const opener of ['- item', '* item', '+ item', '1. item', '## heading', '> quote', '| a | b |', '```js', '~~~', '<!-- marker -->']) {
		assert.equal(foldSoftWraps(`prose\n${opener}`), `prose\n${opener}`, opener);
	}
});

test('an ordered item interrupts a paragraph only at 1, as CommonMark says', () => {
	// A sentence wrapping onto "77. Distinct from ..." is a section reference,
	// not a new list, and every markdown renderer reads it that way. Folding it
	// as a block start truncates the paragraph at that point — on the committed
	// parity bullet that hid 92 of its 109 pairs with no error reported, which is
	// the exact defect the fold exists to prevent.
	assert.equal(foldSoftWraps('see section\n77. Distinct from the other one'), 'see section 77. Distinct from the other one');
	assert.equal(foldSoftWraps('see section\n77) Distinct from the other one'), 'see section 77) Distinct from the other one');
	assert.equal(foldSoftWraps('- pairs are listed\n  604. and the note continues'), '- pairs are listed 604. and the note continues');

	// 1 still interrupts, in both delimiters — a real ordered list written under
	// a paragraph must not be swallowed into it.
	assert.equal(foldSoftWraps('prose\n1. item'), 'prose\n1. item');
	assert.equal(foldSoftWraps('prose\n1) item'), 'prose\n1) item');

	// And a number at the START of a block is a list whatever its value: the
	// rule is about interrupting an OPEN paragraph, not about the digit.
	assert.equal(foldSoftWraps('prose\n\n77. item'), 'prose\n\n77. item');
});

test('a wrapped list item folds, a sibling item does not', () => {
	assert.equal(foldSoftWraps('- first\n  wrapped\n- second'), '- first wrapped\n- second');
});

test('each folded line carries the number of the line it starts on', () => {
	assert.deepEqual(foldedLines('a\nb\n\nc\nd\n').map((l) => l.line), [1, 3, 4, 6]);
});

test('folding is idempotent and preserves a document with no wraps', () => {
	const doc = '# Title\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nprose.\n';
	assert.equal(foldSoftWraps(doc), doc);
	assert.equal(foldSoftWraps(foldSoftWraps(doc)), foldSoftWraps(doc));
});

// --- Tables. decisions § 779.

const TABLE = ['| Feature | Android |', '|---|---|', '| GPX import | ✓ |'];

test('splitRow drops an end cell only where a pipe produced one', () => {
	assert.deepEqual(splitRow('| a | b | c |'), ['a', 'b', 'c']);
	assert.deepEqual(splitRow('a | b | c'), ['a', 'b', 'c']);
	assert.deepEqual(splitRow('| a | b | c'), ['a', 'b', 'c']);
	assert.deepEqual(splitRow('a | b | c |'), ['a', 'b', 'c']);
});

test('an escaped pipe stays inside its cell', () => {
	assert.deepEqual(splitRow('| a | `x \\| y` |'), ['a', '`x \\| y`']);
});

// The § 779 defect, at the layer that caused it. GFM makes the LEADING pipe
// optional and renders the row identically; every reader of parity.md detected
// a row as `line.startsWith('|')`, so the row was invisible to all of them.
test('a row written without its leading pipe is still a row of the table', () => {
	const [table] = markdownTables([...TABLE, 'TCX import | ✓', '| KML import | ✓ |'].join('\n'));
	assert.deepEqual(
		table.rows.map((r) => r.cells[0]),
		['GPX import', 'TCX import', 'KML import'],
	);
	assert.deepEqual(
		table.rows.map((r) => r.line),
		[3, 4, 5],
	);
});

test('a row written with no pipes at all is one cell, not nothing', () => {
	const [table] = markdownTables([...TABLE, 'orphaned prose'].join('\n'));
	assert.deepEqual(table.rows.at(-1)?.cells, ['orphaned prose']);
});

test('the header and the delimiter are not data rows', () => {
	const [table] = markdownTables(TABLE.join('\n'));
	assert.deepEqual(table.header.cells, ['Feature', 'Android']);
	assert.equal(table.delimiter.line, 2);
	assert.equal(table.rows.length, 1);
});

test('a blank line or another block closes the table', () => {
	for (const after of ['', '## Heading', '- list item', '> quote', '<!-- marker -->', '```']) {
		const [table] = markdownTables([...TABLE, after, 'not a row'].join('\n'));
		assert.equal(table.rows.length, 1, after);
	}
});

// GFM's own opening condition. A mismatch renders as a paragraph of raw pipes,
// so the whole table is gone — which is why a caller that cannot afford to lose
// one checks that every pipe-leading line landed in a table.
test('a delimiter of a different width opens no table at all', () => {
	assert.deepEqual(markdownTables(['| a | b |', '|---|---|---|', '| 1 | 2 |'].join('\n')), []);
});

test('a table inside a fence is an illustration, not a table', () => {
	assert.deepEqual(markdownTables(['```md', ...TABLE, '```'].join('\n')), []);
});

test('two tables under one heading are read as two', () => {
	const tables = markdownTables([...TABLE, '', ...TABLE].join('\n'));
	assert.equal(tables.length, 2);
	assert.deepEqual(tables.map((t) => t.header.line), [1, 5]);
});

test('tableLines covers the header, the delimiter and every row', () => {
	assert.deepEqual([...tableLines([...TABLE, 'TCX import | ✓'].join('\n'))], [1, 2, 3, 4]);
});

// The fold has the same blind spot from the other side: a pipeless row is not a
// `BLOCK_START`, so it was glued onto the row above and stopped existing.
test('a pipeless row is not folded into the row above it', () => {
	const doc = [...TABLE, 'TCX import | ✓'].join('\n');
	assert.equal(foldSoftWraps(doc), doc);
	assert.deepEqual(foldedLines(doc).map((l) => l.line), [1, 2, 3, 4]);
});
