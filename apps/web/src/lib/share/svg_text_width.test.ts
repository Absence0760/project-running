// The clipper's contract, checked without a renderer. The one-sided width
// claim the estimate rests on is measured in `svg_text_width.render.test.ts`;
// this file holds the behaviour a caller depends on.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { clipToWidthPx, estimateSvgTextWidthPx } from './svg_text_width';

const SIZE = 56;
const BOX = 1120; // the route card's title box: W 1200 less two 40 px pads

const RUNNER = '\u{1F3C3}';
const FLAG_GB = '\u{1F1EC}\u{1F1E7}';

test('a string that fits is returned unchanged', () => {
	assert.equal(clipToWidthPx('Heath Loop', BOX, SIZE), 'Heath Loop');
});

test('the ellipsis is inside the budget, not added to it', () => {
	const out = clipToWidthPx('n'.repeat(200), BOX, SIZE);
	assert.ok(out.endsWith('…'));
	assert.ok(
		estimateSvgTextWidthPx(out, SIZE) <= BOX,
		'the clipped string, ellipsis included, must fit the box it was clipped to'
	);
});

test('the budget is pixels, so a wide script is cut sooner than a narrow one', () => {
	// The whole point of the module: under the cluster budget these two were
	// the same length, and one of them painted 500 px past the card.
	const narrow = clipToWidthPx('n'.repeat(200), BOX, SIZE);
	const wide = clipToWidthPx('東'.repeat(200), BOX, SIZE);
	assert.ok(
		Array.from(wide).length < Array.from(narrow).length,
		`Han kept ${Array.from(wide).length} against Latin's ${Array.from(narrow).length}`
	);
	for (const out of [narrow, wide]) {
		assert.ok(estimateSvgTextWidthPx(out, SIZE) <= BOX);
	}
});

test('the cut lands on a cluster boundary, never inside one', () => {
	// A flag is two regional indicators and a runner is one code point wide;
	// half of either is a different glyph, or a replacement box.
	for (const s of [`${'a'.repeat(60)}${FLAG_GB}`, `${'a'.repeat(60)}${RUNNER}`]) {
		for (let box = 40; box < 1200; box += 37) {
			const out = clipToWidthPx(s, box, SIZE);
			assert.ok(
				s.startsWith(out.replace(/…$/, '')),
				`clipping to ${box}px produced ${JSON.stringify(out)}, not a prefix`
			);
			assert.ok(!out.includes('�'), 'a cluster was split');
		}
	}
});

test('trailing whitespace is trimmed before the ellipsis', () => {
	const out = clipToWidthPx('one two three four five six seven eight nine ten', 300, SIZE);
	assert.ok(!/\s…$/.test(out), `got ${JSON.stringify(out)}`);
});

test('a box too narrow for the ellipsis alone yields nothing', () => {
	// Not a lone `…`, which would itself paint past the box.
	assert.equal(clipToWidthPx('anything', 1, SIZE), '');
	assert.equal(clipToWidthPx('anything', 0, SIZE), '');
	assert.equal(clipToWidthPx('anything', -5, SIZE), '');
	assert.equal(clipToWidthPx('anything', Number.NaN, SIZE), '');
});

test('an unusable font size estimates nothing rather than a negative width', () => {
	for (const size of [0, -10, Number.NaN, Number.POSITIVE_INFINITY]) {
		assert.equal(estimateSvgTextWidthPx('anything', size), 0);
	}
});

test('a combining mark adds no width of its own', () => {
	// `é` composed is one cluster of one letter; decomposed it is a letter and
	// a mark that paints on top of it. The card must measure them the same.
	assert.equal(
		estimateSvgTextWidthPx('é', SIZE),
		estimateSvgTextWidthPx('e', SIZE)
	);
});

test('an emoji cluster is one glyph, not the sum of its parts', () => {
	// A ZWJ family is three pictographs and one painted glyph; summing the
	// parts would over-count it threefold and clip a title that would fit.
	const family = '\u{1F469}‍\u{1F469}‍\u{1F467}';
	assert.ok(
		estimateSvgTextWidthPx(family, SIZE) < estimateSvgTextWidthPx(RUNNER, SIZE) * 2,
		'a ZWJ sequence must not be measured as its component pictographs'
	);
});
