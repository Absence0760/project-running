// The one-sided claim `svg_text_width` rests on, measured rather than
// re-derived: the estimate must never fall BELOW what the renderer paints.
//
// Nothing here re-checks the em table's numbers. A table of font metrics has
// no source of truth in this repo — the face is the host's — so the only
// honest check is behavioural: rasterise each script class through the same
// renderer the cards use (`@resvg/resvg-js`, the card's own 56 px bold face)
// and read the ink extent back. `getBBox` reports the INK box, which sits
// inside the advance width by the side bearings, so the comparison is
// conservative in the direction the claim needs.
//
// The estimate is allowed to be generous — that is what an upper bound is —
// so there is no upper assertion on the ratio beyond a sanity ceiling that
// would catch the table drifting into uselessness (a clipper that keeps three
// characters of a title that fits twenty is a bug of its own).

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Resvg } from '@resvg/resvg-js';

import { clipToWidthPx, estimateSvgTextWidthPx } from './svg_text_width';

const SIZE = 56;
const FAMILY = 'system-ui,-apple-system,Segoe UI,Roboto,sans-serif';

/// Ink width in pixels of `text` painted as the cards paint it.
function paintedWidthPx(text: string): number {
	const svg =
		`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 4000 200" width="4000" height="200">` +
		`<text x="0" y="120" font-family="${FAMILY}" font-size="${SIZE}" font-weight="700" ` +
		`fill="#000">${text.replace(/&/g, '&amp;').replace(/</g, '&lt;')}</text></svg>`;
	const box = new Resvg(svg, { font: { loadSystemFonts: true } }).getBBox();
	return box === undefined ? 0 : box.width;
}

// One per class the em table distinguishes, each at the 30 clusters the old
// budget allowed — the length at which the overrun was first measured.
const SUBJECTS: ReadonlyArray<readonly [string, string]> = [
	['lowercase Latin', 'n'.repeat(30)],
	['uppercase Latin', 'M'.repeat(30)],
	['a realistic Latin name', 'Hampstead Heath Parkland Loop'],
	['punctuation and digits', '12:34:56 — (5k) #1 100% @pace!'],
	['Cyrillic', 'ш'.repeat(30)],
	['Greek', 'ω'.repeat(30)],
	['CJK Han', '東'.repeat(30)],
	['Hangul', '한'.repeat(30)],
	['fullwidth Latin', 'Ｍ'.repeat(30)],
	['Devanagari', 'क'.repeat(30)],
	['accented Latin', 'é'.repeat(30)],
	['the ellipsis the clipper spends', '…'],
];

for (const [label, text] of SUBJECTS) {
	test(`the estimate bounds what the renderer paints — ${label}`, () => {
		const painted = paintedWidthPx(text);
		const estimated = estimateSvgTextWidthPx(text, SIZE);
		assert.ok(
			painted > 0,
			`${label} painted nothing — the host resolved no glyph, so this case measures nothing`
		);
		assert.ok(
			estimated >= painted,
			`${label}: estimated ${estimated.toFixed(1)}px < painted ${painted.toFixed(1)}px — ` +
				'the bound is not a bound, and a title clipped to it overruns the card'
		);
		assert.ok(
			estimated <= painted * 2,
			`${label}: estimated ${estimated.toFixed(1)}px against ${painted.toFixed(1)}px painted ` +
				'— the bound has drifted far enough to clip titles that would have fit'
		);
	});
}

test('a clipped title fits the box it was clipped to', () => {
	// The property the clipper exists for, checked against the renderer rather
	// than against the estimator that decided it.
	const box = 1120;
	for (const [label, text] of SUBJECTS) {
		const clipped = clipToWidthPx(text.repeat(4), box, SIZE);
		assert.ok(
			paintedWidthPx(clipped) <= box,
			`${label}: the clipped string still paints past ${box}px`
		);
	}
});
