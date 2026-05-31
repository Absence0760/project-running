// Source-level guard that pins WCAG 2.2 AA (>=4.5:1 for normal text)
// for the text colour tokens in app.css, against every background-surface
// token in the same theme. The tertiary token shipped at 2.6-3.3:1 and
// failed AA on ~40 surfaces (older-runner persona finding #7); this guard
// stops any text token from regressing below AA on any surface, in either
// theme, without a future editor reading why.
//
// Web-only: app.css has no mobile/Dart twin (Flutter themes its own
// colours), so there is no parity counterpart to keep in lockstep.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const css = readFileSync(resolve(__dirname, '../app.css'), 'utf-8');

function relativeLuminance(hex: string): number {
	const n = parseInt(hex.slice(1), 16);
	const channels = [(n >> 16) & 0xff, (n >> 8) & 0xff, n & 0xff].map((c) => {
		const s = c / 255;
		return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4;
	});
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrastRatio(a: string, b: string): number {
	const la = relativeLuminance(a);
	const lb = relativeLuminance(b);
	const [hi, lo] = la > lb ? [la, lb] : [lb, la];
	return (hi + 0.05) / (lo + 0.05);
}

// Pull the value of a CSS custom property out of a single theme block.
function tokenIn(block: string, name: string): string {
	const m = block.match(new RegExp(`--${name}:\\s*(#[0-9A-Fa-f]{6})`));
	assert.ok(m, `app.css theme block is missing --${name}`);
	return m![1];
}

// The three theme declaration blocks in app.css. The light defaults live in
// the first `:root {`; dark lives in both the prefers-color-scheme media
// query and the explicit [data-theme="dark"] block. We test all three so a
// fix to one but not the others (the exact bug this guard caught) fails.
function block(startMarker: string): string {
	const start = css.indexOf(startMarker);
	assert.ok(start >= 0, `app.css is missing the "${startMarker}" block`);
	// Grab a generous window; the token regex only matches the first hit,
	// and every block declares the tokens once near its top.
	return css.slice(start, start + 2000);
}

const TEXT_TOKENS = ['color-text', 'color-text-secondary', 'color-text-tertiary'];
const SURFACE_TOKENS = [
	'color-bg',
	'color-bg-secondary',
	'color-bg-tertiary',
	'color-surface',
];
const AA_NORMAL = 4.5;

const THEMES: Array<{ label: string; marker: string }> = [
	{ label: 'light (:root)', marker: ':root {' },
	{ label: 'dark (prefers-color-scheme)', marker: '@media (prefers-color-scheme: dark)' },
	{ label: 'dark ([data-theme="dark"])', marker: ':root[data-theme="dark"]' },
];

// Solid status surfaces (toasts, the offline banner) render WHITE text on
// the "-strong" status tokens. The base --color-success / --color-danger /
// --color-warning shipped at 2.05-3.28:1 with white (accessibility audit
// 2026-05-30 High); the "-strong" variants must clear AA. They live once
// in :root and are theme-independent (already dark in both themes).
test('solid status "-strong" tokens meet WCAG AA with white text', () => {
	const root = block(':root {');
	const WHITE = '#FFFFFF';
	const STRONG = ['color-success-strong', 'color-danger-strong', 'color-warning-strong'];
	for (const name of STRONG) {
		const hex = tokenIn(root, name);
		const ratio = contrastRatio(WHITE, hex);
		assert.ok(
			ratio >= AA_NORMAL,
			`white on --${name} (${hex}) is ${ratio.toFixed(2)}:1; WCAG AA requires >=${AA_NORMAL}:1 for the solid status surfaces that use it.`,
		);
	}
	// Pin theme-independence: a dark-mode override would shadow the
	// AA-checked :root value with an unchecked one, so the dark blocks
	// must NOT redefine these tokens.
	for (const marker of ['@media (prefers-color-scheme: dark)', ':root[data-theme="dark"]']) {
		const b = block(marker);
		for (const name of STRONG) {
			assert.ok(
				!b.includes(`--${name}:`),
				`--${name} must not be redefined in the ${marker} block — it is AA-checked only in :root and must stay theme-independent.`,
			);
		}
	}
});

for (const { label, marker } of THEMES) {
	test(`text tokens meet WCAG AA on every surface — ${label}`, () => {
		const b = block(marker);
		const surfaces = SURFACE_TOKENS.map((s) => ({ name: s, hex: tokenIn(b, s) }));
		for (const tName of TEXT_TOKENS) {
			const text = tokenIn(b, tName);
			for (const surface of surfaces) {
				const ratio = contrastRatio(text, surface.hex);
				assert.ok(
					ratio >= AA_NORMAL,
					`--${tName} (${text}) on --${surface.name} (${surface.hex}) is ${ratio.toFixed(2)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
				);
			}
		}
	});
}
