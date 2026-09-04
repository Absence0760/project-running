import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync } from 'node:fs';
import { resolve, relative } from 'node:path';

/**
 * Web-wide RTL readiness guard. audit/i18n-readiness (2026-05-30) Critical
 * W-10: the web app used physical-direction CSS (margin/padding/border-left
 * /right, text-align: left/right, positioned left/right) everywhere, so an
 * RTL locale rendered mirrored content on the wrong side. The fix migrated
 * every directional layout property to inline-logical equivalents
 * (margin-inline-*, padding-inline-*, border-inline-*, text-align: start/end,
 * inset-inline-*), which render identically in LTR and mirror under
 * `dir="rtl"`. This guard keeps the whole `src/` tree free of physical-
 * direction CSS so a new component can't reintroduce the break.
 *
 * Behavioural proof that the shell actually mirrors lives in
 * tests-e2e/cross-cutting/rtl-layout.spec.ts.
 *
 * `cssOf` strips `/* … *\/` and deliberately NOT `//`, which the JS guards in
 * this tree all blank through `core/strip_comments`. `//` is not a comment in
 * CSS: blanking it would delete a protocol-relative `url(//host/x.woff2)` and
 * the tail of any `content: '…//…'`. The register in `source_scanner_guards.test.ts`
 * records the exemption so it reads as chosen rather than overlooked
 * (decisions § 1001).
 */

const srcRoot = resolve(import.meta.dirname, '..');

function cssFiles(): string[] {
	return readdirSync(srcRoot, { recursive: true, withFileTypes: true })
		.filter((e) => e.isFile() && (e.name.endsWith('.svelte') || e.name.endsWith('.css')))
		.map((e) => resolve(e.parentPath ?? (e as unknown as { path: string }).path, e.name));
}

/** CSS text from a file: <style> bodies for .svelte, whole file for .css, comments stripped. */
function cssOf(file: string): string {
	const raw = readFileSync(file, 'utf-8');
	let css: string;
	if (file.endsWith('.css')) {
		css = raw;
	} else {
		css = [...raw.matchAll(/<style(?=[\s/>])[^>]*>([\s\S]*?)<\/style(?=[\s/>])[^>]*>/g)].map((m) => m[1]).join('\n');
	}
	return css.replace(/\/\*[\s\S]*?\*\//g, ''); // strip CSS comments
}

// Box-model / border / text-align must never be physical anywhere.
const BANNED = [
	/\bmargin-left\b/,
	/\bmargin-right\b/,
	/\bpadding-left\b/,
	/\bpadding-right\b/,
	/\bborder-left\b/,
	/\bborder-right\b/,
	/text-align:\s*left\b/,
	/text-align:\s*right\b/,
];

test('no physical-direction box-model / border / text-align in any web CSS', () => {
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const css = cssOf(file);
		for (const re of BANNED) {
			if (re.test(css)) {
				offenders.push(`${relative(srcRoot, file)} — ${re.source}`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`Physical-direction CSS found — use inline-logical equivalents ` +
			`(margin-inline-*, padding-inline-*, border-inline-*, text-align: start/end):\n  ` +
			offenders.join('\n  '),
	);
});

/**
 * Round 16 (issue #666, decisions.md § 543) extends the two guards above with
 * the classes they were blind to. Every predicate below was written from a
 * measured population, and every population is at zero (or an allowlist of
 * one) as of that round — so a failure here is a new site, never a backlog.
 *
 * These are the properties with NO logical form. `transform`,
 * `transform-origin` and `box-shadow`'s x-offset cannot be expressed
 * inline-relative, so the codebase multiplies the offset by `--dir-sign`
 * (app.css, +1 in LTR and -1 under `:root[dir='rtl']`). A `border-radius`
 * shorthand does have logical longhands (border-start-end-radius et al).
 */

/**
 * Every `prop: value` declaration, comments already stripped by cssOf. Split on
 * `;` rather than per line, because two declarations sharing a line otherwise
 * parse as one value with the next property glued onto its tail.
 */
function declarations(css: string): { prop: string; value: string; line: number }[] {
	const out: { prop: string; value: string; line: number }[] = [];
	const re = /([a-z-]+)\s*:\s*([^;{}]+)[;}]/g;
	for (const m of css.matchAll(re)) {
		out.push({
			prop: m[1],
			value: m[2].trim(),
			line: css.slice(0, m.index).split('\n').length,
		});
	}
	return out;
}

/**
 * Top-level space-separated components of a shorthand value. Paren-depth aware:
 * a naive alternation splits `calc(var(--x) - 2px)` at the inner `)` and reports
 * a one-value shorthand as three.
 */
function topLevelParts(value: string): string[] {
	const parts: string[] = [];
	let depth = 0;
	let cur = '';
	for (const ch of value) {
		if (ch === '(') depth++;
		if (ch === ')') depth--;
		if (/\s/.test(ch) && depth === 0) {
			if (cur) parts.push(cur);
			cur = '';
		} else {
			cur += ch;
		}
	}
	if (cur) parts.push(cur);
	return parts;
}

/** The four corners a `border-radius` shorthand expands to: [TL, TR, BR, BL]. */
function radiusCorners(value: string): string[] | null {
	// An elliptical shorthand ("a b / c d") has independent axes; the inline
	// asymmetry question is the same but the parse is not, and none exist.
	if (value.includes('/')) return null;
	const parts = topLevelParts(value);
	if (!parts.length) return null;
	const [a, b, c, d] = parts;
	if (parts.length === 1) return [a, a, a, a];
	if (parts.length === 2) return [a, b, a, b];
	if (parts.length === 3) return [a, b, c, b];
	if (parts.length === 4) return [a, b, c, d];
	return null;
}

// A teardrop map pin on a MapLibre canvas: the point is a real corner of a
// rotated graphic, not a box edge, and the canvas does not mirror.
const RADIUS_ALLOWLIST = new Set(['lib/components/RouteBuilder.svelte']);

test('transform / transform-origin / box-shadow offsets flip with --dir-sign', () => {
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const rel = relative(srcRoot, file);
		for (const { prop, value, line } of declarations(cssOf(file))) {
			// A physical keyword origin drains/scales from the wrong edge once
			// the element itself mirrors.
			if (prop === 'transform-origin' && /\b(left|right)\b/.test(value)) {
				offenders.push(`${rel}:${line} — transform-origin: ${value}`);
			}
			// translateX by a LENGTH is a directional nudge. A percentage is the
			// centering idiom (paired with a %-based physical left) and mirrors
			// with the element, so it needs no sign.
			if (prop === 'transform' || prop === 'transform-origin') {
				const tx = value.match(/translateX\(\s*(-?[\d.]+)(px|rem|em|ch)\s*\)/);
				if (tx) offenders.push(`${rel}:${line} — translateX(${tx[1]}${tx[2]}) without --dir-sign`);
			}
			// An inset box-shadow with a non-zero x-offset draws a leading-edge
			// accent rail, which must follow the inline-start edge.
			if (prop === 'box-shadow' && /\binset\b/.test(value)) {
				const x = value.match(/inset\s+(-?[\d.]+)(px|rem|em)/);
				if (x && parseFloat(x[1]) !== 0) {
					offenders.push(`${rel}:${line} — box-shadow: inset ${x[1]}${x[2]} without --dir-sign`);
				}
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`Direction-sensitive offset without --dir-sign. These properties have no ` +
			`logical form; multiply the offset by var(--dir-sign) (see app.css):\n  ` +
			offenders.join('\n  '),
	);
});

test('border-radius shorthands are inline-symmetric', () => {
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const rel = relative(srcRoot, file);
		if (RADIUS_ALLOWLIST.has(rel)) continue;
		for (const { prop, value, line } of declarations(cssOf(file))) {
			if (prop !== 'border-radius') continue;
			const corners = radiusCorners(value);
			if (!corners) continue;
			const [tl, tr, br, bl] = corners;
			// Mirroring swaps the two corners of each block edge. Differing
			// top-left/top-right (or bottom-left/bottom-right) therefore renders
			// on the wrong side under RTL; a block-axis-only difference
			// (`X X 0 0`) is direction-agnostic and fine.
			if (tl !== tr || bl !== br) {
				offenders.push(`${rel}:${line} — border-radius: ${value}`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`Inline-asymmetric border-radius shorthand — use the logical corner ` +
			`longhands (border-start-start-radius / border-start-end-radius / ` +
			`border-end-start-radius / border-end-end-radius) so the rounded ` +
			`corner follows the inline axis:\n  ` +
			offenders.join('\n  '),
	);
});

test('a percentage inset-inline-* is never paired with a physical translateX', () => {
	// `inset-inline-start: 50%` puts the element's INLINE-start edge at the
	// centre — the right edge under RTL — so a physical `translateX(-50%)`
	// shifts it the same way in both directions and lands it a full width
	// off-centre. The centering idiom has to be physical on both halves.
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const rel = relative(srcRoot, file);
		// Split into rule bodies so the pairing is judged per rule, not per file.
		for (const body of cssOf(file).split('}')) {
			if (!/inset-inline-(start|end):\s*[\d.]+%/.test(body)) continue;
			if (!/transform:[^;]*translateX\(/.test(body)) continue;
			const sel = body.split('{')[0].trim().split('\n').pop()?.trim() ?? '?';
			offenders.push(`${rel} — ${sel}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`A %-based inset-inline-* paired with a physical translateX cannot ` +
			`mirror — use the physical \`left: 50%\` + translateX(-50%) centering ` +
			`pair instead (it is direction-agnostic):\n  ` +
			offenders.join('\n  '),
	);
});

test('auto margins push along the inline axis, not a physical side', () => {
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const rel = relative(srcRoot, file);
		for (const { prop, value, line } of declarations(cssOf(file))) {
			if (prop !== 'margin' && prop !== 'padding') continue;
			const parts = topLevelParts(value);
			// Only the 4-value form names ONE inline side at a time (`T R B L`).
			// In the 1-, 2- and 3-value forms a single slot covers both inline
			// sides, so `margin: 0 auto X` is symmetric centering and mirrors
			// perfectly — flagging it would have condemned 23 correct sites.
			// Two autos in the 4-value form is that same centering, spelled long.
			if (parts.length !== 4) continue;
			const [, right, , left] = parts;
			if ((right === 'auto') !== (left === 'auto')) {
				offenders.push(`${rel}:${line} — ${prop}: ${value}`);
			}
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`An \`auto\` inline margin in a physical shorthand pushes to the wrong ` +
			`end under RTL — use margin-inline-start / margin-inline-end:\n  ` +
			offenders.join('\n  '),
	);
});

test('positioned left:/right: are logical except documented physical cases', () => {
	// `inset-inline-start/end` mirror under RTL. The only physical
	// left:/right: allowed are direction-agnostic idioms: 50% centering
	// (paired with translateX(-50%), which wouldn't flip), the -9999px
	// off-screen a11y hide, and decorative percent-offset blobs.
	const offenders: string[] = [];
	for (const file of cssFiles()) {
		const css = cssOf(file);
		for (const line of css.split('\n')) {
			const m = line.match(/^\s*(left|right):\s*(.+?);?\s*$/);
			if (!m) continue;
			const value = m[2].trim();
			if (value.includes('%') || /-?9999px/.test(value)) continue; // allowed physical
			offenders.push(`${relative(srcRoot, file)} — ${m[1]}: ${value}`);
		}
	}
	assert.deepEqual(
		offenders,
		[],
		`Physical positioned left:/right: found — use inset-inline-start/end ` +
			`so the element mirrors under RTL (only %-based + -9999px may stay physical):\n  ` +
			offenders.join('\n  '),
	);
});
