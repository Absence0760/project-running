import test from 'node:test';
import assert from 'node:assert/strict';

import { foldSoftWraps, foldedLines } from './markdown_lines.mjs';

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
