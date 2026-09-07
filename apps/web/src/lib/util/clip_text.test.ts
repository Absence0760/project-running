import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { clipText, collapseAndClip } from './clip_text';

test('clipText — a string within budget is returned unchanged', () => {
	assert.equal(clipText('hi', 30), 'hi');
	assert.equal(clipText('exactly ten', 11), 'exactly ten');
});

test('clipText — the ellipsis is inside the budget, not added to it', () => {
	const out = clipText('this string is definitely too long', 10);
	assert.equal(out, 'this stri…');
	assert.equal(out.length, 10);
});

test('clipText — trailing whitespace is trimmed before the ellipsis', () => {
	assert.equal(clipText('one two three', 5), 'one…');
});

test('clipText — a budget of zero or one yields the ellipsis alone', () => {
	assert.equal(clipText('anything', 1), '…');
	assert.equal(clipText('anything', 0), '…');
});

test('collapseAndClip — collapses runs of whitespace and trims', () => {
	assert.equal(collapseAndClip('  8 miles  with   the gang ', 80), '8 miles with the gang');
	assert.equal(collapseAndClip('a\n\tb', 80), 'a b');
});

test('collapseAndClip — nothing to say yields the empty string', () => {
	assert.equal(collapseAndClip('', 80), '');
	assert.equal(collapseAndClip('   ', 80), '');
	assert.equal(collapseAndClip(null, 80), '');
	assert.equal(collapseAndClip(undefined, 80), '');
	assert.equal(collapseAndClip(42, 80), '');
});

test('collapseAndClip — clips the collapsed string, not the raw one', () => {
	assert.equal(collapseAndClip('a     b     c', 5), 'a b c');
});
