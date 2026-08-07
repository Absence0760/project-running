import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';

// A `var(--foo)` whose custom property is defined nowhere is not an error in
// CSS — the declaration silently resolves to the property's initial/inherited
// value at computed-value time (`background` -> transparent, `border` -> none,
// `color` -> inherited). Three surfaces (roadbook, RouteMarkerEditor, the
// event board) shipped with a whole undefined token vocabulary
// (--surface/--text-primary/--border/--accent) and therefore never tracked
// the light/dark theme (accessibility audit 2026-07-02 High). This guard
// fails the build on any var() reference to a token that is neither in
// app.css nor defined/assigned in the same file.
//
// It originally matched only the FALLBACK-LESS form, and that gap hid the same
// bug class wearing a fallback: 130 references across 39 files were written
// `var(--missing-token, #hex)`, which is worse than the bare form rather than
// better. The bare form at least collapses to something inherited and
// theme-adjacent; the fallback form pins a literal, so the declaration is
// permanently that hex in BOTH themes and *looks* deliberate at the call site.
// Measured: `#666` muted text read 2.815:1 on the dark card, and white on a
// primary fill read 2.081:1 in dark because primary flips to a light coral.
//
// A fallback on a token that IS declared stays legal, and deliberately so: it
// is the documented default for a component custom property a parent sets per
// instance (`style:--x={...}`), which is a real pattern here. The line the
// guard draws is existence, not syntax — a fallback on a declared token is a
// default, a fallback on an undeclared token is a hardcoded value in a var()
// costume. The whole distinction rests on the single `[,)]` character class in
// VAR_REFERENCE, so MATCHER_FIXTURES pins it in both directions.

const __dirname = resolve(new URL('.', import.meta.url).pathname);
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

// `var(` + optional space + `--name`, terminated by `)` (no fallback) or `,`
// (a fallback follows). Both forms are references and both are checked.
const VAR_REFERENCE = /var\(\s*--([a-zA-Z0-9-]+)\s*[,)]/g;

function varReferences(line: string): string[] {
	return [...line.matchAll(VAR_REFERENCE)].map((m) => m[1]);
}

// Both directions. `flags` is what the matcher must extract from `source`;
// an empty array means the line must be left alone entirely.
const MATCHER_FIXTURES: Array<{ source: string; flags: string[]; why: string }> = [
	// --- must flag ---
	{ source: 'color: var(--x);', flags: ['x'], why: 'bare reference, the original case' },
	{ source: 'color: var(--x, #fff);', flags: ['x'], why: 'fallback-bearing, the case this guard gained' },
	{ source: 'color: var(--x,#fff);', flags: ['x'], why: 'no space after the comma' },
	{ source: 'color: var( --x , #fff );', flags: ['x'], why: 'padded inside the parens' },
	{ source: 'border-radius: var(--radius-pill, 999px);', flags: ['radius-pill'], why: 'hyphenated name' },
	{
		source: 'background: color-mix(in srgb, var(--a, #fff) 16%, transparent);',
		flags: ['a'],
		why: 'nested inside another CSS function',
	},
	{ source: 'color: var(--a, var(--b, red));', flags: ['a', 'b'], why: 'a nested fallback checks BOTH names' },
	{ source: 'width: calc(100% - var(--a, 4rem) - var(--b));', flags: ['a', 'b'], why: 'two references, mixed forms' },
	{ source: 'font-family: var(--font-mono, monospace);', flags: ['font-mono'], why: 'bare-keyword fallback' },
	{ source: 'background: var(--a, rgba(0, 0, 0, 0.06));', flags: ['a'], why: 'fallback carrying commas and parens' },
	// --- must spare ---
	{ source: '--x: #fff;', flags: [], why: 'a declaration is not a reference' },
	{ source: '--x: var(--y);', flags: ['y'], why: 'a declaration whose VALUE references another token' },
	{ source: '<div style:--x={v}>', flags: [], why: 'Svelte component custom-property directive' },
	{ source: '<Chart --series-a={c} />', flags: [], why: 'component custom-property prop' },
	{ source: 'color: variable(--x);', flags: [], why: 'not the var() function' },
	{ source: 'color: var(x);', flags: [], why: 'no custom-property prefix' },
	{ source: 'color: var(--x', flags: [], why: 'unterminated — neither comma nor close paren' },
	{ source: '--foo-var: 1px;', flags: [], why: 'a declaration whose own name ends in "var"' },
];

test('the var() reference matcher flags fallback-bearing refs and spares declarations', () => {
	for (const { source, flags, why } of MATCHER_FIXTURES) {
		assert.deepEqual(varReferences(source), flags, `${why}: ${JSON.stringify(source)}`);
	}
});

test('an undeclared token is reported whether or not it carries a fallback', () => {
	const declared = new Set(['color-text']);
	const offenders = ['color: var(--color-text, #000);', 'color: var(--nope, #000);', 'color: var(--nope);']
		.flatMap(varReferences)
		.filter((n) => !declared.has(n));
	assert.deepEqual(offenders, ['nope', 'nope']);
});

function walkFiles(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir, { withFileTypes: true })) {
		const path = join(dir, entry.name);
		if (entry.isDirectory()) {
			if (!SKIP_DIRS.has(entry.name)) walkFiles(path, out);
			continue;
		}
		if (/\.(svelte|css)$/.test(entry.name)) out.push(path);
	}
	return out;
}

test('every var(--token) reference resolves to a defined custom property', () => {
	const srcRoot = resolve(__dirname, '..');
	const globalCss = readFileSync(join(srcRoot, 'app.css'), 'utf-8');
	const globalTokens = new Set(
		[...globalCss.matchAll(/--([a-zA-Z0-9-]+)\s*:/g)].map((m) => m[1]),
	);

	const offenders: string[] = [];
	for (const path of walkFiles(srcRoot)) {
		const source = readFileSync(path, 'utf-8');
		// Local definitions: `--x: ...` in a style block or inline style, and
		// Svelte's `style:--x={...}` / `--x={...}` component custom-property
		// directives all end up defining the property for this subtree.
		const localTokens = new Set([
			...[...source.matchAll(/--([a-zA-Z0-9-]+)\s*[:=]/g)].map((m) => m[1]),
			...[...source.matchAll(/style:--([a-zA-Z0-9-]+)/g)].map((m) => m[1]),
		]);
		source.split('\n').forEach((line, i) => {
			for (const name of varReferences(line)) {
				if (!globalTokens.has(name) && !localTokens.has(name)) {
					offenders.push(`${path}:${i + 1}  var(--${name})`);
				}
			}
		});
	}
	assert.equal(
		offenders.length,
		0,
		`var() references an undefined custom property. Without a fallback the ` +
			`declaration silently collapses to its initial value; WITH one it is ` +
			`pinned to that literal in both themes and never tracks the theme at ` +
			`all. Use the matching --color-*/--space-*/--radius-* token from ` +
			`app.css, or declare the property:\n` +
			offenders.join('\n'),
	);
});

/**
 * `--transition-fast` (150ms ease) and `--transition-base` (200ms ease) are the
 * two motion rungs `app.css` declares. Sixteen declarations spelled a rung's
 * value out by hand instead — an identical value, so routing them onto the
 * token changed nothing visually and made the rung movable.
 *
 * The ban is narrow on purpose: only the exact `<rung duration> ease` form,
 * because the token carries its easing. `transition: width 150ms linear` shares
 * the duration and is NOT the same rung — swapping it would change the curve —
 * and it is left alone. Off-rung durations (80, 100, 120, 180, 250, 400 ms) are
 * a design call about how many rungs there should be, not drift, and this does
 * not touch them.
 */
test('no transition spells out a rung the tokens already carry', () => {
	const offenders: string[] = [];
	let scanned = 0;

	for (const path of walkFiles(resolve(__dirname, '..'))) {
		if (path.endsWith('app.css')) continue; // declares the rungs
		const source = readFileSync(path, 'utf-8');
		scanned++;
		for (const m of source.matchAll(/transition:\s*([^;]+);/g)) {
			const body = m[1];
			if (!/\b(0\.15s|150ms|0\.2s|200ms)\s+ease\b/.test(body)) continue;
			const line = source.slice(0, m.index ?? 0).split('\n').length;
			offenders.push(`${path.split('/').slice(-2).join('/')}:${line}  ${body.trim().slice(0, 60)}`);
		}
	}

	// Population: §534 — a walker that found nothing must not pass for that.
	assert.ok(scanned > 100, `scanned only ${scanned} style files — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'these spell a motion rung by hand. Use var(--transition-fast) or ' +
			'var(--transition-base) — the value is identical, and the token is ' +
			'what makes the rung movable. A different easing at the same duration ' +
			'is a different rung and is not flagged.',
	);
});
