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
		css = [...raw.matchAll(/<style[^>]*>([\s\S]*?)<\/style>/g)].map((m) => m[1]).join('\n');
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
