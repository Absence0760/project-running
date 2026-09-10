/**
 * An advance-width estimate for a single-line SVG `<text>`, and the clipper
 * that spends it.
 *
 * The og:image cards paint their title into one `<text>` node, which neither
 * reflows nor clips: anything past the box paints over the artwork and off the
 * card. What bounded it was a GRAPHEME-CLUSTER budget, which is the right unit
 * for a `<meta>` description a reader counts (decisions § 1528) and the wrong
 * one for a box measured in pixels — one cluster is 0.24 em of `'` and 1.0 em
 * of `東`, a factor of four under one number.
 *
 * Measured against the shipped renderer (`@resvg/resvg-js` 2.6.2, the card's
 * own 56 px bold face) by rasterising and reading the ink extent, 30 clusters
 * in the 1120 px box:
 *
 *     lowercase Latin `n`     1142 px      CJK Han                1678 px
 *     a realistic Latin name   952 px      Hangul                 1544 px
 *     uppercase Latin `M`     1645 px      running-figure emoji   1634 px
 *     Cyrillic `ш`            1571 px      flag (RI pair)         2013 px
 *
 * So the overrun was never only CJK: a route named in capitals overran the box
 * by 525 px under a budget written for lowercase.
 *
 * ## Why an estimate and not a measurement
 *
 * The card is built as a string and rasterised elsewhere, so nothing on this
 * side can ask the renderer how wide a glyph is; and `font-family` is a stack
 * ending in `sans-serif`, so the face is the HOST's and differs between the
 * dev server, CI and the Lambda. An exact answer is not available to any
 * caller. What is available is a bound, and a bound is all a clipper needs.
 *
 * `ASCII_ADVANCE_EM` is therefore the widest advance each printable ASCII
 * character takes across six bold sans faces (the shipped stack as resolved on
 * a Fedora host, DejaVu Sans, Liberation Sans, Noto Sans, Arial, Helvetica),
 * rounded UP to 0.01 em. It is a font-metrics approximation, not a derived
 * truth — there is no generator to re-run and no table to keep in lockstep,
 * because the answer depends on a font this repo does not ship. Nothing keys
 * on it: it decides where an ellipsis goes.
 *
 * The claim it has to keep is one-sided — the estimate must never fall BELOW
 * what the renderer paints — and that is checked by behaviour rather than by
 * re-deriving numbers: `svg_text_width.render.test.ts` rasterises each script
 * class and fails if the ink outruns the estimate.
 *
 * ## Why the table alone is not the bound
 *
 * The table was measured on ONE host, and a table of font metrics cannot be
 * more universal than the machine it was read on. Measured against a second
 * host (the CI runner, whose `sans-serif` resolves to a different face) the
 * same strings paint up to **11.2 %** wider than the table says — Cyrillic
 * 1774 px against 1596, ASCII punctuation 1035 against 935, lowercase Latin
 * 1187 against 1142. So a table presented as "the widest advance across six
 * faces" was a bound on the six, and the host is not obliged to use one of
 * them.
 *
 * `HOST_FACE_MARGIN` is the answer, and it is deliberately not a seventh
 * measurement: the Lambda's face is a third unknown and the next host a
 * fourth, so chasing them is a treadmill the estimate would keep losing. The
 * margin covers the measured cross-host spread more than twice over. It costs
 * a slightly earlier clip on a narrow face, which is the safe direction — an
 * over-clipped title is legible, an overrun one paints off the card.
 */

/// Headroom over the measured table for a face this code cannot see.
/// The largest cross-host disagreement measured is 11.2 %; this is 25 %.
///
/// Exported for the render test, which grades the TABLE against the ink and
/// has to divide this back out: the margin is declared headroom, not drift,
/// and folding it into that ceiling made the ceiling a claim about both at
/// once — passing on one host's Latin face and failing on a slightly narrower
/// one, with nothing about the table having changed.
export const HOST_FACE_MARGIN = 1.25;

/// Advance widths in em for U+0020..U+007E, in code-point order.
const ASCII_ADVANCE_EM = [
	0.31, 0.34, 0.47, 0.74, 0.63, 0.9, 0.74, 0.24, 0.34, 0.34, 0.56, 0.58, 0.27, 0.4, 0.27, 0.47,
	0.58, 0.58, 0.59, 0.61, 0.65, 0.63, 0.59, 0.58, 0.59, 0.59, 0.34, 0.34, 0.58, 0.58, 0.58, 0.61,
	1.09, 0.74, 0.74, 0.77, 0.79, 0.72, 0.63, 0.77, 0.88, 0.34, 0.65, 0.74, 0.65, 0.99, 0.83, 0.9,
	0.67, 0.9, 0.74, 0.68, 0.67, 0.84, 0.74, 0.95, 0.72, 0.67, 0.75, 0.34, 0.47, 0.34, 0.58, 0.58,
	0.34, 0.68, 0.7, 0.61, 0.7, 0.59, 0.38, 0.68, 0.7, 0.29, 0.29, 0.58, 0.31, 0.93, 0.68, 0.68,
	0.7, 0.7, 0.49, 0.58, 0.42, 0.68, 0.58, 0.79, 0.58, 0.58, 0.54, 0.4, 0.56, 0.4, 0.58,
];

/// A cluster carrying any pictographic or regional-indicator code point takes
/// this much, whatever else is in it. One rule rather than a sum, because the
/// parts of an emoji cluster paint as ONE glyph: a woman-woman-girl ZWJ
/// sequence is three pictographs and 1.07 em, and summing its parts would
/// over-count it threefold. The value covers the widest cluster measured — a
/// two-code-point regional-indicator flag at 1.20 em.
const PICTOGRAPHIC_EM = 1.3;

/// East Asian Wide and Fullwidth. Measured at 0.999 em for Han and 0.994 for
/// fullwidth Latin; 1.05 leaves the same one-sided headroom the ASCII table's
/// rounding does.
const EAST_ASIAN_EM = 1.05;

/// Every other script. Above the widest single letter measured in Cyrillic
/// (0.94), Greek (0.92) and Devanagari (0.76), because a name is not obliged
/// to contain an average letter.
const OTHER_EM = 0.95;

/// Combining marks, joiners, variation selectors and tag characters paint no
/// advance of their own — they compose with the base beside them.
const ZERO_EM = 0;

/// Ranges are compared numerically rather than matched, so no pattern is ever
/// assembled from these values.
const EAST_ASIAN_RANGES: ReadonlyArray<readonly [number, number]> = [
	[0x1100, 0x115f],
	[0x2e80, 0x303e],
	[0x3041, 0x33ff],
	[0x3400, 0x4dbf],
	[0x4e00, 0x9fff],
	[0xa000, 0xa4cf],
	[0xa960, 0xa97f],
	[0xac00, 0xd7a3],
	[0xf900, 0xfaff],
	[0xfe10, 0xfe19],
	[0xfe30, 0xfe6f],
	[0xff00, 0xff60],
	[0xffe0, 0xffe6],
	[0x1f200, 0x1f2ff],
	[0x20000, 0x3fffd],
];

const PICTOGRAPHIC_RANGES: ReadonlyArray<readonly [number, number]> = [
	[0x203c, 0x2049],
	[0x2190, 0x21ff],
	[0x2300, 0x23ff],
	[0x25a0, 0x27bf],
	[0x2b00, 0x2bff],
	[0x1f000, 0x1f0ff],
	[0x1f100, 0x1f1ff],
	[0x1f300, 0x1f9ff],
	[0x1fa00, 0x1faff],
];

/// Zero-advance code points that are NOT general combining marks: the joiner,
/// the two tag blocks. Variation selectors and the enclosing keycap are marks
/// and are caught by the property test below.
const ZERO_RANGES: ReadonlyArray<readonly [number, number]> = [
	[0x200b, 0x200f],
	[0x2060, 0x2064],
	[0xfeff, 0xfeff],
	[0xe0000, 0xe007f],
];

function inRanges(cp: number, ranges: ReadonlyArray<readonly [number, number]>): boolean {
	for (const [lo, hi] of ranges) if (cp >= lo && cp <= hi) return true;
	return false;
}

/// `\p{M}` is a literal pattern over the RUNTIME's own Unicode data, the same
/// choice § 1529 made for the segmenter: a frozen mark table would be a table
/// and a rule engine to remove a disagreement no consumer can observe. It is
/// also older everywhere than `Intl.Segmenter` — Unicode property escapes
/// landed in Firefox 78 against the segmenter's 125 — so a runtime that has
/// one has this.
const COMBINING_MARK = /\p{M}/u;

function advanceEm(cp: number): number {
	if (cp >= 0x20 && cp <= 0x7e) return ASCII_ADVANCE_EM[cp - 0x20];
	if (cp < 0x20 || (cp >= 0x7f && cp <= 0x9f)) return ZERO_EM;
	if (inRanges(cp, ZERO_RANGES)) return ZERO_EM;
	if (COMBINING_MARK.test(String.fromCodePoint(cp))) return ZERO_EM;
	if (inRanges(cp, PICTOGRAPHIC_RANGES)) return PICTOGRAPHIC_EM;
	if (inRanges(cp, EAST_ASIAN_RANGES)) return EAST_ASIAN_EM;
	return OTHER_EM;
}

/// The grapheme clusters of `s`, or its code points where the runtime has no
/// segmenter. A code-point split can put two halves of one emoji cluster in
/// different buckets, which costs at most the difference between one
/// pictographic width and two — an over-estimate, so the one-sided claim above
/// survives the fallback.
function clusters(s: string): string[] {
	const ctor = (Intl as { Segmenter?: typeof Intl.Segmenter }).Segmenter;
	if (typeof ctor !== 'function') return Array.from(s);
	const out: string[] = [];
	for (const { segment } of new ctor('en', { granularity: 'grapheme' }).segment(s)) {
		out.push(segment);
	}
	return out;
}

function clusterEm(cluster: string): number {
	let sum = 0;
	for (const ch of cluster) {
		const cp = ch.codePointAt(0) ?? 0;
		if (inRanges(cp, PICTOGRAPHIC_RANGES)) return PICTOGRAPHIC_EM;
		sum += advanceEm(cp);
	}
	return sum;
}

/// An upper bound, in pixels, on the advance width `text` takes at
/// `fontSizePx`. Never below what the renderer paints; see the module header
/// for what that claim rests on.
export function estimateSvgTextWidthPx(text: string, fontSizePx: number): number {
	if (!Number.isFinite(fontSizePx) || fontSizePx <= 0) return 0;
	let em = 0;
	for (const c of clusters(text)) em += clusterEm(c);
	return em * fontSizePx * HOST_FACE_MARGIN;
}

/// `text` cut to fit `maxWidthPx` at `fontSizePx`, with an ellipsis in the
/// budget when anything was dropped.
///
/// The cut lands on a grapheme-cluster boundary wherever the runtime can name
/// one, so § 1528's guarantee is unchanged — only the budget's UNIT moved. A
/// box too narrow for the ellipsis alone yields `''` rather than a lone `…`
/// that would itself overrun.
export function clipToWidthPx(text: string, maxWidthPx: number, fontSizePx: number): string {
	if (!Number.isFinite(maxWidthPx) || maxWidthPx <= 0) return '';
	if (estimateSvgTextWidthPx(text, fontSizePx) <= maxWidthPx) return text;

	const ellipsisPx = estimateSvgTextWidthPx('…', fontSizePx);
	if (ellipsisPx > maxWidthPx) return '';

	const budget = maxWidthPx - ellipsisPx;
	let used = 0;
	let kept = '';
	for (const c of clusters(text)) {
		// Through the same margin the estimate carries, or the running total
		// and the fits-check above would be measuring in different units.
		const w = clusterEm(c) * fontSizePx * HOST_FACE_MARGIN;
		if (used + w > budget) break;
		used += w;
		kept += c;
	}
	const trimmed = kept.trimEnd();
	return trimmed ? `${trimmed}…` : '';
}
