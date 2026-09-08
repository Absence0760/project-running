import { test } from 'node:test';
import { strict as assert } from 'node:assert';

import { clipText, collapseAndClip } from './clip_text';

/// One grapheme cluster each, and every one of them more than one code unit —
/// a ZWJ sequence, a regional-indicator flag pair, a skin-tone modifier, a
/// base letter with its combining mark, and a plain astral emoji.
const FAMILY = '\u{1F469}‍\u{1F469}‍\u{1F467}';
const FLAG_GB = '\u{1F1EC}\u{1F1E7}';
const THUMB = '\u{1F44D}\u{1F3FD}';
const ACCENTED = 'é';
const RUNNER = '\u{1F3C3}';

const CLUSTERS = [
	['family', FAMILY],
	['flag', FLAG_GB],
	['skin tone', THUMB],
	['combining mark', ACCENTED],
	['astral emoji', RUNNER],
] as const;

const segmenter = new Intl.Segmenter('en', { granularity: 'grapheme' });
function graphemeCount(s: string): number {
	let n = 0;
	for (const _ of segmenter.segment(s)) n++;
	return n;
}

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
	assert.equal(clipText('', 0), '');
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

test('clipText — the budget counts what a reader counts, whatever the script', () => {
	// The § 1528 property: 160 of anything fits a budget of 160. Under the
	// code-unit budget this held for ASCII and CJK and for nothing else — 160
	// running emoji came back as 79, and 160 families as 19.
	for (const [name, cluster] of [...CLUSTERS, ['ascii', 'a'] as const, ['cjk', '中'] as const]) {
		const s = cluster.repeat(160);
		assert.equal(clipText(s, 160), s, `${name} was clipped inside its own budget`);
		assert.equal(graphemeCount(s), 160);
	}
});

test('clipText — the cut lands on a cluster boundary, never inside one', () => {
	for (const [name, cluster] of CLUSTERS) {
		const s = cluster.repeat(12);
		for (let max = 1; max <= 20; max++) {
			const out = clipText(s, max);
			const expected = 12 <= max ? s : `${cluster.repeat(max - 1)}…`;
			assert.equal(out, expected, `${name} at budget ${max}`);
			assert.ok(graphemeCount(out) <= Math.max(max, 12), `${name} at budget ${max} overran`);
			assert.ok(survivesUtf8(out), `${name} at budget ${max} left ill-formed text`);
			assert.doesNotMatch(out, LONE_SURROGATE, `${name} at budget ${max}`);
		}
	}
});

test('clipText — a whole cluster is kept where the code-unit budget dropped it', () => {
	// Budget 10, nine clusters kept: eight letters and the runner. The
	// code-unit cut spent two of its ten units on the emoji and had to step
	// back off the pair, so it emitted the letters alone.
	const s = `${'a'.repeat(8)}${RUNNER} and more text past the cut`;
	assert.equal(s.charCodeAt(8), 0xd83c);
	assert.equal(clipText(s, 10), `${'a'.repeat(8)}${RUNNER}…`);
});

test('collapseAndClip — the club-description budget keeps 160 characters of any script', () => {
	const desc = `${'a'.repeat(158)}${FAMILY} more text after the cut point`;
	const out = collapseAndClip(desc, 160);
	assert.equal(out, `${'a'.repeat(158)}${FAMILY}…`);
	assert.equal(graphemeCount(out), 160);
	assert.ok(survivesUtf8(out), 'the og:description carried a lone surrogate');
	assert.doesNotMatch(out, LONE_SURROGATE);
});

test('clipText — trailing whitespace is trimmed off a cluster boundary too', () => {
	assert.equal(clipText(`${FLAG_GB} ${FLAG_GB}${FLAG_GB}`, 3), `${FLAG_GB}…`);
});

test('clipText — without Intl.Segmenter the budget degrades to code units, still well-formed', () => {
	const intl = Intl as { Segmenter?: typeof Intl.Segmenter };
	const ctor = intl.Segmenter;
	const s = `${'a'.repeat(8)}${RUNNER} and more text past the cut`;
	try {
		delete intl.Segmenter;
		const out = clipText(s, 10);
		// The pair straddles the budget's last unit, so the whole character is
		// dropped rather than half-emitted — never a lone surrogate, but a
		// cluster shorter than the grapheme path keeps.
		assert.equal(out, `${'a'.repeat(8)}…`);
		assert.ok(survivesUtf8(out));
		assert.doesNotMatch(out, LONE_SURROGATE);
		// And the cluster the grapheme path protects can be split here: half a
		// flag is a bare regional indicator, which renders as a letter in a box.
		assert.equal(clipText(FLAG_GB.repeat(4), 3), '\u{1F1EC}…');
	} finally {
		intl.Segmenter = ctor;
	}
	assert.equal(clipText(s, 10), `${'a'.repeat(8)}${RUNNER}…`);
});
