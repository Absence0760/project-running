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

/// The output re-encoded as UTF-8 and read back — exactly what the HTTP
/// response does to a `<head>` meta tag or an SVG text node. A lone surrogate
/// does not survive it, so this equality IS the property.
function survivesUtf8(s: string): boolean {
	return Buffer.from(s, 'utf8').toString('utf8') === s;
}

const LONE_SURROGATE = /[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]/;

test('clipText — a cut that lands inside a surrogate pair drops the character whole', () => {
	// The budget's last kept unit (index 8) is the high half of the emoji.
	const s = `${'a'.repeat(8)}\u{1F3C3} and more text past the cut`;
	assert.equal(s.charCodeAt(8), 0xd83c);
	const out = clipText(s, 10);
	assert.equal(out, `${'a'.repeat(8)}…`);
	assert.ok(survivesUtf8(out), 'a lone surrogate reached the output');
	assert.doesNotMatch(out, LONE_SURROGATE);
});

test('clipText — a cut that lands after a whole pair keeps it', () => {
	const s = `${'a'.repeat(7)}\u{1F3C3} and more text past the cut`;
	const out = clipText(s, 10);
	assert.equal(out, `${'a'.repeat(7)}\u{1F3C3}…`);
	assert.ok(survivesUtf8(out));
});

test('clipText — no budget over any all-emoji string can split a pair', () => {
	const s = '\u{1F3C3}'.repeat(40);
	for (let max = 1; max <= 60; max++) {
		const out = clipText(s, max);
		assert.ok(out.length <= Math.max(max, s.length === out.length ? out.length : max));
		assert.ok(survivesUtf8(out), `budget ${max} split a pair`);
		assert.doesNotMatch(out, LONE_SURROGATE, `budget ${max} left a lone surrogate`);
	}
});

test('collapseAndClip — the club-description budget cannot cut an emoji in half', () => {
	const desc = `${'a'.repeat(158)}\u{1F3C3} more text after the cut point`;
	const out = collapseAndClip(desc, 160);
	assert.ok(survivesUtf8(out), 'the og:description carried a lone surrogate');
	assert.doesNotMatch(out, LONE_SURROGATE);
	assert.equal(out, `${'a'.repeat(158)}…`);
});
