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
//
// Both assertions rest on the host having a face for the script, and no host
// is obliged to: the CI runner carries none for Han, Hangul, fullwidth Latin
// or Devanagari, and resvg then paints one `.notdef` box per code point. That
// measures the placeholder rather than the text, in a direction that is not
// merely weak — the lower bound passes for free, and the ceiling fires on the
// box's width instead of the script's. It did: all four painted 1002.6 px on
// the runner, three failing the ceiling and Devanagari passing it by 10 px.
// So a subject the host cannot paint is SKIPPED, loudly, instead of being
// measured; `UNIVERSAL` keeps that escape away from the scripts every face
// carries, so a suite where everything skipped cannot read as green.

import { test } from 'node:test';
import assert from 'node:assert/strict';

import { Resvg } from '@resvg/resvg-js';

import { HOST_FACE_MARGIN, clipToWidthPx, estimateSvgTextWidthPx } from './svg_text_width';

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

/// Ink width of `count` code points the host can map NONE of. U+FDD0 is a
/// Unicode noncharacter — permanently unassigned, so no font may carry it —
/// and every unmappable code point falls through to the same `.notdef` glyph
/// of whichever face was resolved. A run of one repeated character therefore
/// paints EXACTLY this wide when the host has no face for it, which is why the
/// comparison below is an equality rather than a threshold: it needs no
/// judgement about how narrow a real glyph may be.
function notdefWidthPx(count: number): number {
	return paintedWidthPx('\uFDD0'.repeat(count));
}

/// Floating-point slack on that equality. Both widths are the same glyph's
/// advance summed the same number of times, so they agree bit for bit; this
/// only guards against a renderer that reorders the sum.
const NOTDEF_EPSILON_PX = 0.01;

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

/// The subjects no host may fail to resolve: a sans face without Latin
/// letters, digits and ASCII punctuation is not a face. A fallback on one of
/// these is a broken host rather than a missing script, so it fails where the
/// rest skip — and it is what stops an all-skipped run from being green.
const UNIVERSAL: ReadonlySet<string> = new Set([
	'lowercase Latin',
	'uppercase Latin',
	'a realistic Latin name',
	'punctuation and digits',
	'accented Latin',
]);

for (const [label, text] of SUBJECTS) {
	test(`the estimate bounds what the renderer paints — ${label}`, (t) => {
		const painted = paintedWidthPx(text);
		const estimated = estimateSvgTextWidthPx(text, SIZE);
		assert.ok(
			painted > 0,
			`${label} painted nothing — the host resolved no glyph, so this case measures nothing`
		);
		const fellBack =
			Math.abs(painted - notdefWidthPx(Array.from(text).length)) < NOTDEF_EPSILON_PX;
		assert.ok(
			!fellBack || !UNIVERSAL.has(label),
			`${label} fell back to .notdef — a face that cannot paint this is not a face the ` +
				'cards can be rendered with, so this is a broken host rather than a missing script'
		);
		if (fellBack) {
			t.skip(
				`${label}: this host has no face covering the script — every glyph painted as ` +
					'.notdef, so the widths below would compare the placeholder box against the em table'
			);
			return;
		}
		assert.ok(
			estimated >= painted,
			`${label}: estimated ${estimated.toFixed(1)}px < painted ${painted.toFixed(1)}px — ` +
				'the bound is not a bound, and a title clipped to it overruns the card'
		);
		// Graded on the em table alone. `HOST_FACE_MARGIN` is deliberate
		// headroom for a face this code cannot see, so charging it to this
		// ceiling makes one assertion about two things: at 25 % the table gets
		// 1.6x of the ink rather than 2x, which `accented Latin` already spends
		// (`OTHER_EM` is sized for the widest Cyrillic letter and 'é' is a
		// narrow one) — 1.99x here, 2.12x against a slightly narrower face,
		// with nothing about the table having changed.
		const table = estimated / HOST_FACE_MARGIN;
		assert.ok(
			table <= painted * 2,
			`${label}: the em table claims ${table.toFixed(1)}px against ${painted.toFixed(1)}px ` +
				'painted — it has drifted far enough to clip titles that would have fit'
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
