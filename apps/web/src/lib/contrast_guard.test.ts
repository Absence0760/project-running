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
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { resolve, dirname, join } from 'node:path';
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
	// Return the WHOLE rule by walking from its first `{` to the matching
	// `}` (brace-balanced — handles the nested `:root` inside the dark
	// `@media`). A fixed-size window used to truncate the block, so a large
	// declaration near the top of `:root` (e.g. the non-Latin font-family
	// fallback list) could push the colour tokens out of view and the
	// guard would mis-report them as "missing".
	const open = css.indexOf('{', start);
	assert.ok(open >= 0, `app.css "${startMarker}" block has no opening brace`);
	let depth = 0;
	for (let i = open; i < css.length; i++) {
		if (css[i] === '{') depth++;
		else if (css[i] === '}' && --depth === 0) return css.slice(start, i + 1);
	}
	throw new assert.AssertionError({ message: `app.css "${startMarker}" block is unterminated` });
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

// Resolve a token to a #hex within a theme, following `var(--x)` references
// (the -text tokens are defined as `var(--color-warning-strong)` in light and
// `var(--color-warning)` in dark). A token missing from a dark block falls back
// to its :root value, exactly as the cascade resolves it.
function resolveToken(marker: string, name: string): string {
	const rootBlock = block(':root {');
	const themeBlock = marker === ':root {' ? rootBlock : block(marker);
	for (let hop = 0, cur = name; hop < 6; hop++) {
		const src = themeBlock.match(new RegExp(`--${cur}:\\s*([^;]+);`))?.[1]?.trim()
			?? rootBlock.match(new RegExp(`--${cur}:\\s*([^;]+);`))?.[1]?.trim();
		assert.ok(src, `app.css is missing --${cur} (resolving --${name} in ${marker})`);
		const hex = src!.match(/^#[0-9A-Fa-f]{6}$/)?.[0];
		if (hex) return hex;
		const ref = src!.match(/var\(\s*--([\w-]+)\s*\)/)?.[1];
		assert.ok(ref, `--${cur} is neither a #hex nor a var() reference: ${src}`);
		cur = ref!;
	}
	throw new assert.AssertionError({ message: `--${name} var() chain too deep in ${marker}` });
}

function mixOverHex(fg: string, pct: number, bg: string): string {
	const f = parseInt(fg.slice(1), 16), b = parseInt(bg.slice(1), 16);
	const a = pct / 100;
	const ch = (sh: number) =>
		Math.round((((f >> sh) & 0xff) * a + ((b >> sh) & 0xff) * (1 - a)));
	return '#' + [16, 8, 0].map((sh) => ch(sh).toString(16).padStart(2, '0')).join('');
}

// Theme-aware FOREGROUND tokens for status / accent TEXT + ICONS. Unlike the
// -strong tokens (theme-independent white-on-fill backgrounds), these MUST flip
// per theme: dark on a light surface, light on a dark surface. The base
// --color-warning / -secondary / -accent-cyan they replace failed WCAG 1.4.3 as
// text (2.05 / 3.06 / 2.30:1 on white; issue #368). Each -text token is checked
// as text both on the plain surface AND on its own same-hue chip tint (the
// tightest case — a raw base token at the tint % used on the chip), in EVERY
// theme, so a fix to one theme but not the others fails here.
const ACCENT_TEXT: Array<{ text: string; base: string; chipPct: number }> = [
	{ text: 'color-warning-text', base: 'color-warning', chipPct: 22 },
	{ text: 'color-secondary-text', base: 'color-secondary', chipPct: 16 },
	{ text: 'color-accent-cyan-text', base: 'color-accent-cyan', chipPct: 16 },
	{ text: 'color-accent-orange-text', base: 'color-accent-orange', chipPct: 14 },
];
for (const { label, marker } of THEMES) {
	test(`accent/status -text tokens meet WCAG AA as text — ${label}`, () => {
		const surface = resolveToken(marker, 'color-surface');
		const bg = resolveToken(marker, 'color-bg');
		for (const { text, base, chipPct } of ACCENT_TEXT) {
			const fg = resolveToken(marker, text);
			for (const [ctxName, ctx] of [
				['color-surface', surface],
				['color-bg', bg],
				[`${base}@${chipPct}% chip on surface`, mixOverHex(resolveToken(marker, base), chipPct, surface)],
			] as const) {
				const ratio = contrastRatio(fg, ctx);
				assert.ok(
					ratio >= AA_NORMAL,
					`--${text} (${fg}) on ${ctxName} (${ctx}) is ${ratio.toFixed(2)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
				);
			}
		}
	});
}

// Every base accent / status token is tuned for tints, borders and dark-mode
// use; as a bare `color:` (text/icon) on a LIGHT surface each fails WCAG 1.4.3.
// Computed against the real tokens, worst light surface first:
//   accent-pink   1.42-1.79:1    accent-orange 1.66-2.08:1
//   warning       1.63-2.05:1    secondary     3.06:1
//   accent-cyan   2.30:1         success       2.62-3.28:1
//   danger        3.65-4.58:1
// success and danger were the last two still spread across the tree (96 sites
// on 46 files) — success sat below even the 3:1 non-text floor on the page
// background. The theme-aware -text variants exist for foreground use; this
// scan stops any base token creeping back as one.
//
// The list is every base accent/status token EXCEPT --color-primary, which
// computes to 6.40-7.07:1 in light and 7.77:1 in dark and is a legitimate
// foreground at its 236 sites. There is no --color-info token to check.
//
// A token is banned as a FOREGROUND, not banned outright: `background:`,
// `background-color:`, `border-color:` and the -light tints are exactly what
// these tokens are tuned for, and a solid `-strong` fill under white text is
// the documented pairing. The leading `(?<![a-z-])` boundary is what draws
// that line — it rejects every `*-color:` longhand — and MATCHER_FIXTURES
// below pins both directions so a future tightening cannot over-reach.
// Quoted JS props (`color: 'var(--color-accent-cyan)'`, the macro-ring stroke
// colours) are data, not text, and don't match (the `'` breaks `:\s*var`).
// The trailing `[,)]` matters as much as the leading boundary: a fallback does
// not make the reference safe, it only hid it here. `color: var(--color-warning,
// #b45309)` resolves to the token (the fallback is dead — the token exists), so
// it painted 2.048:1 warning text on white while reading as guarded. Eight such
// sites survived §503 for exactly this reason; css_token_guard.test.ts had the
// same one-character gap. A fallback on the -text pair stays legal.
const FOREGROUND_TOKEN_OFFENDER =
	/(?<![a-z-])(?:color|fill|stroke|-webkit-text-fill-color)\s*:\s*var\(\s*--color-(?:warning|secondary|accent-cyan|accent-orange|accent-pink|success|danger)\s*[,)](?!-)/;

test('no source file uses a bare accent/status token as a foreground colour', () => {
	const hits = scanSource((line) => FOREGROUND_TOKEN_OFFENDER.test(line));
	assert.equal(
		hits.length,
		0,
		`A base accent/status token is used as a foreground (text, icon glyph or SVG fill); ` +
			`every one of them fails WCAG AA on light surfaces (1.42-4.58:1) and the palest ` +
			`fail even the 3:1 non-text floor. Use the theme-aware --color-<token>-text ` +
			`variant instead:\n${hits.join('\n')}`,
	);
});

// The scan's own precision, pinned in both directions. Without this the guard
// could be "fixed" into banning the tokens outright — which would flag the
// fills and tints they exist for, and the white-on--strong pairing the toasts
// and the offline banner are built on.
const MATCHER_FIXTURES: Array<[flagged: boolean, line: string]> = [
	[true, '\tcolor: var(--color-success);'],
	[true, '\t.x:hover { color: var(--color-danger); }'],
	[true, '\tcolor: var( --color-warning );'],
	[true, '\tfill: var(--color-danger);'],
	[true, '\tstroke: var(--color-success);'],
	[true, '\t-webkit-text-fill-color: var(--color-accent-orange);'],
	[true, '\tcolor: var(--color-warning, #b45309);'],
	[true, '\tcolor: var(--color-success, #16a34a);'],
	[true, '\tfill: var(--color-danger, #dc2626);'],
	[true, '\tcolor: var(--color-danger, var(--color-primary));'],
	[false, '\tbackground: var(--color-success);'],
	[false, '\tbackground: var(--color-success, #16a34a);'],
	[false, '\tborder-color: var(--color-danger, #dc2626);'],
	[false, '\tcolor: var(--color-success-text, #2E6B3C);'],
	[false, '\tcolor: var(--color-danger-light, #fff);'],
	[false, '\tbackground-color: var(--color-danger);'],
	[false, '\tborder-color: var(--color-danger);'],
	[false, '\toutline-color: var(--color-warning);'],
	[false, '\tbackground: var(--color-success-strong); color: #fff;'],
	[false, '\tbackground: var(--color-danger-light);'],
	[false, '\tbackground: color-mix(in srgb, var(--color-success) 16%, transparent);'],
	[false, '\tcolor: var(--color-success-text);'],
	[false, '\tcolor: var(--color-danger-strong);'],
	[false, '\tcolor: var(--color-primary);'],
	[false, '\tfill-opacity: var(--color-danger);'],
	[false, '\t--color-success: #4A9F5A;'],
];
test('the foreground scan flags foregrounds and spares fills', () => {
	for (const [flagged, line] of MATCHER_FIXTURES) {
		assert.equal(
			FOREGROUND_TOKEN_OFFENDER.test(line),
			flagged,
			flagged
				? `the foreground scan misses \`${line.trim()}\``
				: `the foreground scan wrongly flags \`${line.trim()}\` — these tokens are fills and tints, and only their FOREGROUND use is banned.`,
		);
	}
});

// Walk src/ and return `path:line  text` for every line the predicate flags.
function scanSource(flag: (line: string) => boolean): string[] {
	const srcRoot = resolve(__dirname, '..');
	const selfPath = resolve(__dirname, 'contrast_guard.test.ts');
	const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);
	const hits: string[] = [];
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				if (!SKIP_DIRS.has(entry.name)) walk(path);
				continue;
			}
			if (!/\.(svelte|css|ts)$/.test(entry.name)) continue;
			if (path === selfPath) continue; // this guard's own doc/string mentions
			readFileSync(path, 'utf-8')
				.split('\n')
				.forEach((line, i) => {
					if (flag(line)) hits.push(`${path}:${i + 1}  ${line.trim()}`);
				});
		}
	})(srcRoot);
	return hits;
}

// The "-strong" status tokens are theme-INDEPENDENT dark fills, AA-checked
// only with WHITE text (the test above pins white-on-strong + forbids a
// dark-mode override). Using one as a `color:` (text) is therefore a bug:
// it renders dark text that goes near-invisible on a dark surface in dark
// mode. Both the gym/gear wear badge and the nutrition macro-F chip hit this
// (audit 2026-06-08). For warning/danger text on a tint, the codebase
// pattern is `color-mix(<status> N%, var(--color-text))` (theme-aware via
// --color-text) or a solid -strong fill with `color: #fff`. This guard scans
// the source tree so the antipattern can't come back unnoticed.
test('no source file uses a "-strong" status token as a text colour', () => {
	// `color:` (the text property — the leading boundary rejects
	// `background-color:`) set to a `-strong` status token.
	const offender = /(?<![a-z-])color:\s*var\(\s*--color-(?:success|danger|warning)-strong/;
	const hits = scanSource((line) => offender.test(line));
	assert.equal(
		hits.length,
		0,
		`A "-strong" status token is used as text (it is a white-on-fill background colour, ` +
			`invisible in dark mode as text). Use color-mix(<status> N%, var(--color-text)) ` +
			`or a solid -strong fill with white text instead:\n${hits.join('\n')}`,
	);
});

// Status text on a same-status tint uses `color: color-mix(<status> N%,
// var(--color-text))` (theme-aware via --color-text, which flips per theme).
// AA holds only while the status stays a minority-enough share of the mix; past
// that the text washes out on the chip tint in light mode (a warning at 80% is
// #be8e5e on the tint = 2.59:1; a solid status as text — 0% text — fails the
// same way: success 2.78:1, danger 3.79:1, audit 2026-06-08). The caps below
// are the AA-verified ceilings (computed with contrastRatio above against the
// 14-22% tints in use; both themes >=4.5:1, contrast falls as the share rises):
//   warning 45% -> 5.25 light / 7.82 dark   (55% was 4.23:1, the regression this caught)
//   success 50% -> 6.06 light / 7.80 dark
//   danger  65% -> 6.05 light / 6.27 dark
const STATUS_TEXT_MIX_MAX: Record<string, number> = { warning: 45, success: 50, danger: 65 };
test('status text-on-tint keeps each --color-<status> mix share AA-safe in both themes', () => {
	const offenders: string[] = [];
	for (const [status, max] of Object.entries(STATUS_TEXT_MIX_MAX)) {
		const re = new RegExp(
			`(?<![a-z-])color:\\s*color-mix\\([^;]*var\\(--color-${status}\\)\\s*(\\d+)%[^;]*var\\(--color-text\\)`,
		);
		offenders.push(
			...scanSource((line) => {
				const m = line.match(re);
				return m != null && Number(m[1]) > max;
			}).map((h) => `[${status} cap ${max}%] ${h}`),
		);
	}
	assert.equal(
		offenders.length,
		0,
		`A status text colour mixes more of its --color-<status> than the AA-safe cap with ` +
			`--color-text, failing WCAG AA on the chip tint in light mode. Lower the share to the cap:\n` +
			offenders.join('\n'),
	);
});

// The leaderboard medal pills (RunSegmentEfforts) and the segment-crown icon.
// Gold rides the theme-aware --color-crown / --color-on-crown pair (mobile's
// AppSemanticColors.crown/onCrown, mirrored); silver and bronze are fixed
// metal fills whose foregrounds are therefore fixed too. Every pair is text on
// an opaque fill, so the 4.5:1 normal-text floor applies; --color-crown is
// additionally used as a bare icon colour, which is WCAG 1.4.11 non-text at
// 3:1. The pre-fix values: gold #f59e0b + white 2.15:1, silver #94a3b8 + white
// 2.56:1, crown icon #f5b30a on the light surface 1.85:1.
const AA_NON_TEXT = 3;
for (const { label, marker } of THEMES) {
	test(`crown token pairs AA as pill text and 3:1 as an icon — ${label}`, () => {
		const crown = resolveToken(marker, 'color-crown');
		const onCrown = resolveToken(marker, 'color-on-crown');
		const pill = contrastRatio(onCrown, crown);
		assert.ok(
			pill >= AA_NORMAL,
			`--color-on-crown (${onCrown}) on --color-crown (${crown}) is ${pill.toFixed(2)}:1 in ${label}; the rank-1 pill needs >=${AA_NORMAL}:1.`,
		);
		for (const surfaceName of ['color-surface', 'color-bg']) {
			const surface = resolveToken(marker, surfaceName);
			const icon = contrastRatio(crown, surface);
			assert.ok(
				icon >= AA_NON_TEXT,
				`--color-crown (${crown}) on --${surfaceName} (${surface}) is ${icon.toFixed(2)}:1 in ${label}; the crown icon carries meaning alone and needs >=${AA_NON_TEXT}:1 (WCAG 1.4.11).`,
			);
		}
	});
}

test('fixed medal rank pills meet WCAG AA', () => {
	const source = readFileSync(
		resolve(__dirname, 'components/RunSegmentEfforts.svelte'),
		'utf-8',
	);
	for (const medal of ['silver', 'bronze']) {
		const rule = source.match(
			new RegExp(`\\.rank-pill\\.${medal}\\s*\\{([^}]*)\\}`),
		);
		assert.ok(rule, `RunSegmentEfforts.svelte has no .rank-pill.${medal} rule`);
		const body = rule![1];
		const bg = body.match(/background:\s*(#[0-9A-Fa-f]{6})/)?.[1];
		const fgRaw = body.match(/(?<![a-z-])color:\s*(#[0-9A-Fa-f]{6}|white)/)?.[1];
		assert.ok(bg, `.rank-pill.${medal} has no literal background`);
		assert.ok(fgRaw, `.rank-pill.${medal} has no literal colour`);
		const fg = fgRaw === 'white' ? '#FFFFFF' : fgRaw!;
		const ratio = contrastRatio(fg, bg!);
		assert.ok(
			ratio >= AA_NORMAL,
			`.rank-pill.${medal} renders ${fg} on ${bg} = ${ratio.toFixed(2)}:1; WCAG AA requires >=${AA_NORMAL}:1.`,
		);
	}
});

// Fitness / Fatigue / Form chart series. Each stroke is a graphical object
// carrying meaning alone, so each owes WCAG 1.4.11's 3:1 to the surface it is
// drawn on, in every theme. The single fixed trio this replaced was 2.57:1
// (indigo on the dark surface) and 2.15:1 (amber on white). Pairwise 3:1 across
// three series is unreachable once each also owes 3:1 to its surface, so what
// is pinned between them is a strictly monotone LUMINANCE ladder — that, not
// hue, is what survives greyscale and red-green colour-vision deficiency.
const CHART_SERIES = ['chart-fitness', 'chart-fatigue', 'chart-form'];
for (const { label, marker } of THEMES) {
	test(`training-load series clear 3:1 and separate by luminance — ${label}`, () => {
		const hexes = CHART_SERIES.map((n) => ({ name: n, hex: resolveToken(marker, n) }));
		for (const surfaceName of ['color-surface', 'color-bg']) {
			const surface = resolveToken(marker, surfaceName);
			for (const { name, hex } of hexes) {
				const ratio = contrastRatio(hex, surface);
				assert.ok(
					ratio >= AA_NON_TEXT,
					`--${name} (${hex}) on --${surfaceName} (${surface}) is ${ratio.toFixed(2)}:1 in ${label}; a plotted series needs >=${AA_NON_TEXT}:1 (WCAG 1.4.11).`,
				);
			}
		}
		assert.equal(new Set(hexes.map((h) => h.hex)).size, 3, `series hues collide in ${label}`);
		const ladder = hexes.map((h) => relativeLuminance(h.hex)).sort((a, b) => a - b);
		for (let i = 0; i + 1 < ladder.length; i++) {
			const ratio = (ladder[i + 1] + 0.05) / (ladder[i] + 0.05);
			assert.ok(
				ratio >= 1.7,
				`adjacent series separate by only ${ratio.toFixed(2)}:1 in ${label}; the luminance ladder is what carries the plot in greyscale.`,
			);
		}
	});
}

// Both mobile chart scales are the same palettes by value — a Dart file cannot
// import a CSS custom property, so the lockstep is checked here. Reading the
// scale by NAME rather than by ordinal position is what makes this survive a
// relocation: the two scales lived in a screen and a top-level palette file
// until they moved into ui_kit's ChartPalette, and a positional match would
// have gone on passing against whatever list happened to come first.
function dartChartScale(
	brightness: 'light' | 'dark',
	scale: 'series' | 'zones' | 'kinds',
): string[] {
	const dart = readFileSync(
		resolve(__dirname, '../../../../packages/ui_kit/lib/src/theme/chart_palette.dart'),
		'utf-8',
	);
	const palette = dart.match(
		new RegExp(`static const ${brightness} = ChartPalette\\(([\\s\\S]*?)\\n  \\);`),
	);
	assert.ok(palette, `chart_palette.dart has no ${brightness} palette`);
	const body = palette![1].match(new RegExp(`${scale}: \\[([\\s\\S]*?)\\]`));
	assert.ok(body, `ChartPalette.${brightness} has no ${scale} scale`);
	return [...body![1].matchAll(/Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map(
		(m) => `#${m[1].toUpperCase()}`,
	);
}

test('training-load series match mobile ChartPalette.series', () => {
	const expected: Array<[string, 'light' | 'dark']> = [
		[':root {', 'light'],
		[':root[data-theme="dark"]', 'dark'],
	];
	for (const [marker, brightness] of expected) {
		const hexes = dartChartScale(brightness, 'series');
		assert.equal(
			hexes.length,
			3,
			`ChartPalette.${brightness}.series does not carry three curves`,
		);
		['chart-fitness', 'chart-fatigue', 'chart-form'].forEach((token, i) => {
			assert.equal(
				resolveToken(marker, token).toUpperCase(),
				hexes[i],
				`--${token} in ${marker} has drifted from ChartPalette.${brightness}.series[${i}].`,
			);
		});
	}
});

// The five heart-rate zone bands. Each band owes WCAG 1.4.11's 3:1 to the
// surface behind the bar — that is exactly what makes the surface-coloured gap
// between segments visible against every band, which is how the boundaries are
// delineated at all: four steps of 3:1 need 81:1 and sRGB offers 21:1, so five
// pairwise-3:1 bands do not exist. What is pinned between the bands instead is
// a strictly monotone LUMINANCE ladder, because a green-to-red ramp collapses
// under red-green colour-vision deficiency. The two palettes this replaced had
// z1 and z5 at 1.03:1 (identical in greyscale) and 2.11:1 respectively.
const ZONE_TOKENS = ['zone-1', 'zone-2', 'zone-3', 'zone-4', 'zone-5'];
for (const { label, marker } of THEMES) {
	test(`HR zone bands clear 3:1 and step monotonically — ${label}`, () => {
		const hexes = ZONE_TOKENS.map((n) => resolveToken(marker, n));
		for (const surfaceName of ['color-surface', 'color-bg']) {
			const surface = resolveToken(marker, surfaceName);
			hexes.forEach((hex, i) => {
				const ratio = contrastRatio(hex, surface);
				assert.ok(
					ratio >= AA_NON_TEXT,
					`--${ZONE_TOKENS[i]} (${hex}) on --${surfaceName} (${surface}) is ${ratio.toFixed(2)}:1 in ${label}; a band the separator has to show through needs >=${AA_NON_TEXT}:1.`,
				);
			});
		}
		const ls = hexes.map(relativeLuminance);
		const rising = ls[1] > ls[0];
		for (let i = 0; i + 1 < ls.length; i++) {
			assert.ok(
				rising ? ls[i + 1] > ls[i] : ls[i + 1] < ls[i],
				`the zone ramp is not monotone in ${label} at z${i + 1}->z${i + 2}; the ordering is what survives greyscale.`,
			);
			const step = rising
				? (ls[i + 1] + 0.05) / (ls[i] + 0.05)
				: (ls[i] + 0.05) / (ls[i + 1] + 0.05);
			assert.ok(
				step >= 1.35,
				`z${i + 1}->z${i + 2} steps only ${step.toFixed(2)}:1 in ${label}.`,
			);
		}
	});
}

// The run-detail band must read the tokens, not a literal — the two mobile
// surfaces and this one carried three different lists before.
test('run-detail HR zone defs read the shared zone tokens', () => {
	const page = readFileSync(
		resolve(__dirname, '../routes/runs/[id]/+page.svelte'),
		'utf-8',
	);
	for (let i = 1; i <= 5; i++) {
		assert.ok(
			page.includes(`color: 'var(--zone-${i})'`),
			`runs/[id] zoneDefs entry ${i} does not read --zone-${i}.`,
		);
	}
});

// The dashboard's per-zone time bars were a FIFTH list nobody had measured:
// z3 and z4 were 1.016:1 apart in light, and in dark z1..z4 all sat inside
// 1.08:1, so four of the five rows drew the same bar. They read the shared
// ladder now, and each rung owes WCAG 1.4.11's 3:1 to the track it is measured
// against — the bar's extent is the datum, so that boundary is the graphical
// information.
test('dashboard HR zone bars read the shared zone tokens', () => {
	const page = readFileSync(resolve(__dirname, '../routes/dashboard/+page.svelte'), 'utf-8');
	for (let i = 1; i <= 5; i++) {
		assert.ok(
			page.includes(`.zone-row-${i} .zone-bar { background: var(--zone-${i}); }`),
			`dashboard .zone-row-${i} .zone-bar does not read --zone-${i}.`,
		);
	}
	const track = page.match(/\.zone-bar-wrap \{[^}]*background:\s*var\(\s*--([\w-]+)\s*\)/)?.[1];
	assert.ok(track, 'dashboard .zone-bar-wrap declares no track background token');
	for (const { label, marker } of THEMES) {
		const trackHex = resolveToken(marker, track!);
		for (const name of ZONE_TOKENS) {
			const ratio = contrastRatio(resolveToken(marker, name), trackHex);
			assert.ok(
				ratio >= AA_NON_TEXT,
				`--${name} on the zone-bar track --${track} (${trackHex}) is ${ratio.toFixed(3)}:1 in ${label}; the bar/track boundary carries the value and needs >=${AA_NON_TEXT}:1.`,
			);
		}
	}
});

// The intensity split bar. Two bands, so unlike the five-band ramp they CAN be
// pairwise 3:1 as well as 3:1 against the card — and they take the two ends of
// the same shared ladder rather than a third bespoke pair. The amber this
// replaces was 2.148:1 against the light card, and in DARK it was 1.032:1
// against its own partner (--color-primary flips to coral, which is the same
// hue) — the split bar showed no split at all.
test('the intensity split bar reads the ends of the shared zone ladder', () => {
	const card = readFileSync(
		resolve(__dirname, 'components/IntensityBalanceCard.svelte'),
		'utf-8',
	);
	for (const [cls, token] of [
		['seg-easy', 'zone-1'],
		['seg-hard', 'zone-5'],
		['dot-easy', 'zone-1'],
		['dot-hard', 'zone-5'],
	] as const) {
		assert.ok(
			new RegExp(`\\.${cls}\\s*\\{\\s*background:\\s*var\\(--${token}\\);`).test(card),
			`IntensityBalanceCard .${cls} does not read --${token}.`,
		);
	}
	assert.ok(
		!/#[0-9a-fA-F]{3,8}\b/.test(card),
		'IntensityBalanceCard carries a raw colour literal; every colour in it is a token.',
	);
	const track = card.match(/\.split-bar \{[^}]*background:\s*var\(\s*--([\w-]+)\s*\)/)?.[1];
	assert.ok(track, 'IntensityBalanceCard .split-bar declares no track background token');
	for (const { label, marker } of THEMES) {
		const easy = resolveToken(marker, 'zone-1');
		const hard = resolveToken(marker, 'zone-5');
		const pair = contrastRatio(easy, hard);
		assert.ok(
			pair >= AA_NON_TEXT,
			`the easy/hard split bands are ${pair.toFixed(3)}:1 apart in ${label}; two adjacent bands carrying the split need >=${AA_NON_TEXT}:1.`,
		);
		for (const surfaceName of ['color-surface', track!]) {
			const surface = resolveToken(marker, surfaceName);
			for (const [name, hex] of [['zone-1', easy], ['zone-5', hard]] as const) {
				const ratio = contrastRatio(hex, surface);
				assert.ok(
					ratio >= AA_NON_TEXT,
					`--${name} (${hex}) on --${surfaceName} (${surface}) is ${ratio.toFixed(3)}:1 in ${label}; the band needs >=${AA_NON_TEXT}:1.`,
				);
			}
		}
	}
});

// Mobile cannot import a CSS custom property, so the lockstep is checked here.
test('HR zone tokens match mobile ChartPalette.zones', () => {
	for (const [marker, brightness] of [
		[':root {', 'light'],
		[':root[data-theme="dark"]', 'dark'],
	] as const) {
		const hexes = dartChartScale(brightness, 'zones');
		assert.equal(
			hexes.length,
			5,
			`ChartPalette.${brightness}.zones does not carry five bands`,
		);
		hexes.forEach((hex, i) => {
			assert.equal(
				resolveToken(marker, `zone-${i + 1}`).toUpperCase(),
				hex,
				`--zone-${i + 1} in ${marker} has drifted from ChartPalette.${brightness}.zones[${i}].`,
			);
		});
	}
});

// The six planned-workout kind marks. These were three raw hexes inlined in
// PlanCalendar.svelte and CurrentWeekStrip.svelte, painting the kind LABEL as
// well as the 3 px cell edge: as text they owed AA and delivered 2.30 (tempo),
// 2.77 (interval) and 1.85 (marathon pace) on the page. Nothing in this file
// caught it because none of those hues is a status token and none of them was in
// app.css at all. The label reads --color-text now, so what the marks owe is
// 1.4.11's 3:1 — on the page, on the plain surface, AND on the completed-day
// fill, which is the deepest thing a cell edge is drawn against.
const KIND_MARKS = ['kind-1', 'kind-2', 'kind-3', 'kind-4', 'kind-5', 'kind-6'];
for (const { label, marker } of THEMES) {
	test(`workout-kind marks clear 3:1 and separate by luminance — ${label}`, () => {
		const hexes = KIND_MARKS.map((n) => ({ name: n, hex: resolveToken(marker, n) }));
		const doneFill = mixOverHex(
			resolveToken(marker, 'color-success'),
			10,
			resolveToken(marker, 'color-bg'),
		);
		for (const [surfaceName, surface] of [
			['color-bg', resolveToken(marker, 'color-bg')],
			['color-surface', resolveToken(marker, 'color-surface')],
			['the completed-day fill', doneFill],
		] as const) {
			for (const { name, hex } of hexes) {
				const ratio = contrastRatio(hex, surface);
				assert.ok(
					ratio >= AA_NON_TEXT,
					`--${name} (${hex}) on ${surfaceName} (${surface}) is ${ratio.toFixed(3)}:1 in ${label}; a kind mark needs >=${AA_NON_TEXT}:1 (WCAG 1.4.11).`,
				);
			}
		}
		assert.equal(new Set(hexes.map((h) => h.hex)).size, 6, `kind marks collide in ${label}`);
		// Six categorical marks cannot be pairwise 3:1 — five such steps need
		// 243:1 and sRGB offers 21:1 — so the ordering is what is pinned, and
		// the list order IS that ordering.
		const ls = hexes.map((h) => relativeLuminance(h.hex));
		const rising = ls[1] > ls[0];
		for (let i = 0; i + 1 < ls.length; i++) {
			assert.ok(
				rising ? ls[i + 1] > ls[i] : ls[i + 1] < ls[i],
				`the kind ladder folds at --kind-${i + 1} -> --kind-${i + 2} in ${label}.`,
			);
			const step = (Math.max(ls[i], ls[i + 1]) + 0.05) / (Math.min(ls[i], ls[i + 1]) + 0.05);
			assert.ok(
				step >= 1.18,
				`--kind-${i + 1} -> --kind-${i + 2} steps only ${step.toFixed(3)} in ${label}; the ladder is what carries the marks in greyscale.`,
			);
		}
	});
}

// --color-border is the one LINE token, and its entire guarantee is WCAG
// 1.4.11's 3:1 floor against every surface a boundary is drawn on. It shipped
// at 1.458:1 on the light card and 1.328:1 on the dark one, so web had no token
// that guaranteed a visible boundary at all while mobile's whole card/divider
// grammar rests on one (§ 487). In light the card fill is #FFFFFF on a #F7F3EC
// page — 1.116:1 apart — so the hairline is the only separation there is, which
// is exactly the "visual information required to identify a UI component"
// 1.4.11 sets at 3:1.
for (const { label, marker } of THEMES) {
	test(`the line token clears the 3:1 boundary floor on every surface — ${label}`, () => {
		const line = resolveToken(marker, 'color-border');
		for (const surfaceName of SURFACE_TOKENS) {
			const surface = resolveToken(marker, surfaceName);
			const ratio = contrastRatio(line, surface);
			assert.ok(
				ratio >= AA_NON_TEXT,
				`--color-border (${line}) on --${surfaceName} (${surface}) is ${ratio.toFixed(3)}:1 in ${label}; a boundary needs >=${AA_NON_TEXT}:1 (WCAG 1.4.11).`,
			);
		}
	});
}

// The mark scale must not go back to painting type. Every surface that carries a
// per-kind custom property is listed, and a `color:` reading any of them fails —
// the marks are built to 1.4.11's 3:1, so as type they are exactly the 1.973 /
// 2.373 / 1.589 regression this round closed. The scale reached FOUR web surfaces
// (two components and two plan routes), each with its own copy of the three
// hexes, which is why one measured fix had to close all four at once.
const KIND_MARK_SURFACES = [
	['lib/components/PlanCalendar.svelte', '--kind'],
	['lib/components/CurrentWeekStrip.svelte', '--kind'],
	['routes/plans/[id]/+page.svelte', '--kind-color'],
	['routes/plans/[id]/workouts/[wid]/+page.svelte', '--kind-tint'],
	['routes/plans/[id]/workouts/[wid]/+page.svelte', '--seg-color'],
] as const;

test('no plan surface paints type in the workout-kind mark scale', () => {
	const root = resolve(__dirname, '..');
	for (const [file, prop] of KIND_MARK_SURFACES) {
		const src = readFileSync(join(root, file), 'utf-8');
		const styles = src.slice(src.indexOf('<style>'));
		assert.ok(styles.length > 0, `${file} has no style block`);
		const asText = new RegExp(`(?<![a-z-])color:\\s*var\\(${prop}[,)]`);
		assert.ok(
			!asText.test(styles),
			`${file} paints type in var(${prop}); the mark scale is a 3:1 fill, so the label owes AA in a text token.`,
		);
		assert.ok(
			styles.includes(`var(${prop}`),
			`${file} no longer reads var(${prop}) at all — if the mark moved, move this guard with it.`,
		);
	}
});

// Mobile cannot import a CSS custom property, so the lockstep is checked here.
test('workout-kind tokens match mobile ChartPalette.kinds', () => {
	for (const [marker, brightness] of [
		[':root {', 'light'],
		[':root[data-theme="dark"]', 'dark'],
	] as const) {
		const hexes = dartChartScale(brightness, 'kinds');
		assert.equal(
			hexes.length,
			6,
			`ChartPalette.${brightness}.kinds does not carry six marks`,
		);
		hexes.forEach((hex, i) => {
			assert.equal(
				resolveToken(marker, `kind-${i + 1}`).toUpperCase(),
				hex,
				`--kind-${i + 1} in ${marker} has drifted from ChartPalette.${brightness}.kinds[${i}].`,
			);
		});
	}
});

// Mobile pinned the same token per brightness in § 487 and web's surfaces ARE
// mobile's (parchment / parchmentDim / duskDeep / midnight are --color-bg /
// --color-bg-tertiary / --color-surface / --color-bg), so the two hairlines
// must be the same colour or a card reads apart on one platform and not the
// other. A Dart file cannot import a CSS custom property, so the lockstep is
// checked here, the same way the chart, zone and semantic palettes already are.
test('the line token matches mobile AppTheme.parchmentLine / duskLine', () => {
	const dart = readFileSync(
		resolve(__dirname, '../../../../packages/ui_kit/lib/src/theme/app_theme.dart'),
		'utf-8',
	);
	for (const [marker, symbol] of [
		[':root {', 'parchmentLine'],
		[':root[data-theme="dark"]', 'duskLine'],
	] as const) {
		const hex = dart.match(
			new RegExp(`static const Color ${symbol} = Color\\(0xFF([0-9A-Fa-f]{6})\\)`),
		)?.[1];
		assert.ok(hex, `app_theme.dart has no ${symbol}`);
		assert.equal(
			resolveToken(marker, 'color-border').toUpperCase(),
			`#${hex!.toUpperCase()}`,
			`--color-border in ${marker} has drifted from AppTheme.${symbol}.`,
		);
	}
});

// The other half of the split: --color-fill-subtle holds the value the border
// token shipped with, and its contract is the opposite one — text ON it must
// clear AA. It is what the neutral metadata chip, the progress-bar tracks and
// the button hover took when --color-border became a 3:1 line. Its own
// separation from the surface is deliberately NOT pinned: a track is identified
// by the fill inside it, not by its own edge (measured 1.162-1.622:1, recorded
// in decisions rather than raised, because deepening a progress track is a
// visual-design decision on five surfaces and not a boundary defect).
for (const { label, marker } of THEMES) {
	test(`the neutral chip's label clears AA on the subtle fill — ${label}`, () => {
		const fg = resolveToken(marker, 'chip-fg');
		const bg = resolveToken(marker, 'chip-bg');
		const ratio = contrastRatio(fg, bg);
		assert.ok(
			ratio >= AA_NORMAL,
			`--chip-fg (${fg}) on --chip-bg (${bg}) is ${ratio.toFixed(3)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
		);
	});
}

// The rule the split creates, and the only direction it can regress in: a FILL
// token drawn as a border re-creates the sub-3:1 hairline the line token exists
// to remove, silently, at a call site that reads as deliberate. Scoped to the
// CSS border/outline longhands and shorthands, which are unambiguously a
// component boundary. `background` is NOT in scope in either direction — eight
// dividers here are drawn as a 1px background or a grid `gap` show-through and
// legitimately take --color-border — and `stroke` is not either, because a
// chart gridline is reference ornament inside a graphic rather than a component
// edge and is the one class deliberately left below the floor.
const BOUNDARY_PROPERTY =
	'(?:border|border-(?:top|bottom|left|right|inline|block)(?:-(?:start|end))?|border-(?:top|bottom|left|right|inline-start|inline-end|block-start|block-end)?-?color|outline|outline-color)';
const FILL_AS_BOUNDARY = new RegExp(
	`(?<![a-z-])${BOUNDARY_PROPERTY}\\s*:[^;]*var\\(\\s*--color-fill-subtle\\s*[,)]`,
);

test('no source file draws a border or outline in the subtle FILL token', () => {
	const hits = scanSource((line) => FILL_AS_BOUNDARY.test(line));
	assert.equal(
		hits.length,
		0,
		`A boundary is drawn in --color-fill-subtle, which sits at 1.162-1.622:1 against ` +
			`the surfaces it lands on — the invisible hairline --color-border was raised to ` +
			`3:1 to remove. Use --color-border:\n${hits.join('\n')}`,
	);
});

// And the mirror: a boundary token is not text. It guarantees 3:1, not 4.5:1,
// so painting type in it is a WCAG 1.4.3 failure that the boundary floor above
// cannot catch — the plan surfaces' "rest" workout label did exactly this,
// reading 1.458:1 light / 1.328:1 dark before the token moved and still only
// 3.906 / 3.330 after. Muted type is --color-text-tertiary (5.782 / 5.510).
//
// A QUOTED reference is banned outright rather than classified, because syntax
// cannot decide it: `rest: 'var(--color-border)'` was handed to a `--kind`
// component custom property that the consumer applied to a 3px stripe AND to
// the label's `color:`, so one entry was a boundary and text at once. That is
// § 510's "derived" verdict — and unlike mobile's it needs no count-pinned
// allowlist, because after the routing none is left and an entry matching
// nothing would fail the "can only shrink" rule anyway.
const BOUNDARY_TOKEN_AS_TEXT = new RegExp(
	`(?<![a-z-])(?:color|-webkit-text-fill-color)\\s*:\\s*var\\(\\s*--color-border\\s*[,)]` +
		`|['"]\\s*var\\(\\s*--color-border\\s*\\)\\s*['"]`,
);

test('no source file uses the line token as a text colour', () => {
	const hits = scanSource((line) => BOUNDARY_TOKEN_AS_TEXT.test(line));
	assert.equal(
		hits.length,
		0,
		`--color-border is a 3:1 boundary token used as text, which cannot reach WCAG AA's ` +
			`4.5:1 (3.906:1 light / 3.330:1 dark on the card). Use --color-text-tertiary:\n${hits.join('\n')}`,
	);
});

// A boundary token has no headroom at all — its whole guarantee is the floor,
// so any thinning spends it (§ 510, arrived at on mobile). Mixing it with an
// ACCENT is not a thinning and must be spared: the 19 `color-mix(<accent> N%,
// var(--color-border))` borders here all move contrast UP, because the accent
// is darker than the line in light and lighter than it in dark. Mixing toward
// `transparent` or toward a surface token is the thinning, and it is banned.
const LINE_TOKEN_THINNED = new RegExp(
	`color-mix\\([^;]*var\\(\\s*--color-border\\s*\\)[^;]*?,\\s*(?:transparent|var\\(\\s*--color-(?:bg|bg-secondary|bg-tertiary|surface)\\s*\\))|` +
		`color-mix\\([^;]*(?:transparent|var\\(\\s*--color-(?:bg|bg-secondary|bg-tertiary|surface)\\s*\\))[^;]*var\\(\\s*--color-border\\s*\\)\\s*\\d`,
);

test('the line token is never thinned toward a surface or transparent', () => {
	const hits = scanSource((line) => LINE_TOKEN_THINNED.test(line));
	assert.equal(
		hits.length,
		0,
		`--color-border is mixed toward a surface or transparent. Its entire guarantee is ` +
			`the 3:1 floor, so a thinning spends it — 0.18 of it computed to 1.229:1 on the ` +
			`mobile side of the same finding. Draw the softer line in --color-fill-subtle if ` +
			`it is genuinely decorative:\n${hits.join('\n')}`,
	);
});

// All three scans, both directions. The line-vs-fill split is exactly what the
// property boundary decides, so a future tightening that reached `background`
// would flag the eight legitimate divider-as-a-fill sites, and one that dropped
// the `(?<![a-z-])` lookbehind would read `background-color` as a boundary.
const LINE_TOKEN_FIXTURES: Array<[re: RegExp, flagged: boolean, line: string]> = [
	// --- fill drawn as a boundary ---
	[FILL_AS_BOUNDARY, true, '\tborder: 1px solid var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\tborder-top: 1px solid var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\tborder-inline-start: 3px solid var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\tborder-color: var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\tborder-bottom-color: var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\toutline: 2px solid var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, true, '\tborder: 1px solid var(--color-fill-subtle, #DDD5C5);'],
	[FILL_AS_BOUNDARY, false, '\tbackground: var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, false, '\tbackground-color: var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, false, '\tstroke: var(--color-fill-subtle);'],
	[FILL_AS_BOUNDARY, false, '\tborder: 1px solid var(--color-border);'],
	[FILL_AS_BOUNDARY, false, '\t--color-fill-subtle: #DDD5C5;'],
	// --- boundary token as text ---
	[BOUNDARY_TOKEN_AS_TEXT, true, '\tcolor: var(--color-border);'],
	[BOUNDARY_TOKEN_AS_TEXT, true, "\t\trest: 'var(--color-border)'"],
	[BOUNDARY_TOKEN_AS_TEXT, true, '\t-webkit-text-fill-color: var(--color-border);'],
	[BOUNDARY_TOKEN_AS_TEXT, false, '\tborder-color: var(--color-border);'],
	[BOUNDARY_TOKEN_AS_TEXT, false, '\tbackground-color: var(--color-border);'],
	[BOUNDARY_TOKEN_AS_TEXT, false, '\tcolor: var(--color-text-tertiary);'],
	[BOUNDARY_TOKEN_AS_TEXT, false, "\t\trest: 'var(--color-text-tertiary)'"],
	[BOUNDARY_TOKEN_AS_TEXT, false, '\tstyle="--kind: {KIND_COLOR[wo.kind]}"'],
	// --- thinning ---
	[LINE_TOKEN_THINNED, true, '\tborder-color: color-mix(in srgb, var(--color-border) 40%, transparent);'],
	[LINE_TOKEN_THINNED, true, '\tborder-color: color-mix(in srgb, var(--color-border) 60%, var(--color-surface));'],
	[LINE_TOKEN_THINNED, true, '\tborder-color: color-mix(in srgb, var(--color-bg) 70%, var(--color-border) 30%);'],
	[LINE_TOKEN_THINNED, false, '\tborder-color: color-mix(in srgb, var(--color-primary) 35%, var(--color-border));'],
	[LINE_TOKEN_THINNED, false, '\tborder: 1px dashed color-mix(in srgb, var(--color-secondary) 35%, var(--color-border));'],
	[LINE_TOKEN_THINNED, false, '\tbackground: color-mix(in srgb, var(--color-primary) 14%, var(--color-fill-subtle));'],
];
test('the line/fill scans split on the CSS property, not on the token alone', () => {
	for (const [re, flagged, line] of LINE_TOKEN_FIXTURES) {
		assert.equal(
			re.test(line),
			flagged,
			flagged ? `the scan misses \`${line.trim()}\`` : `the scan wrongly flags \`${line.trim()}\``,
		);
	}
});

// § 518 recorded the line token as failing 3:1 "on eight dark tinted-gradient
// cards, 2.551-2.998:1" and could not close it. Re-derived here, that figure
// turns out to be the TOKEN measured against the tint (2.539-2.776 in 8-bit) —
// but seven of those eight cards do not paint the token: they paint
// `color-mix(<their own accent> 28-35%, var(--color-border))`, which lands
// 3.152-3.744 dark and 3.388-4.579 light. § 503's "measure where it lands"
// trap, one round further on. The residue was five sites the token-level look
// could not see and one it hid, so the check that closes it has to be composited
// per call site, which is what this is.
//
// It resolves, per theme: the tint stops a rule paints as
// `color-mix(in srgb, var(--A) N%, var(--SURFACE))`, the border colour that
// actually applies to that rule's subject (the last declaration per edge among
// the rules whose subject's class AND pseudo-class sets are subsets of this
// one's — which is why `.relink-run:hover`, whose own hover rule moves the edge
// to primary, is not a finding and `.btn-secondary:hover`, whose does not, is),
// and then the ratio between them. A tint over `transparent` is deliberately out
// of scope: the source does not name what is behind it, so nothing here can
// resolve it, and asserting on a guess is how § 503 got its name.
const TINT_OVER_SURFACE =
	/color-mix\(\s*in srgb\s*,\s*var\(\s*--([\w-]+)\s*\)\s*([\d.]+)%\s*,\s*var\(\s*--([\w-]+)\s*\)\s*\)/g;
const LINE_MIXED_WITH_ACCENT =
	/color-mix\(\s*in srgb\s*,\s*var\(\s*--([\w-]+)\s*\)\s*([\d.]+)%\s*,\s*var\(\s*--color-border\s*\)\s*\)/;
// Every edge a border longhand or shorthand can set. The shorthands widen to the
// edges they cover so a later `border-top` override is not read as replacing the
// whole box — the plan grid's kind stripe is exactly that shape.
const BORDER_EDGES: Record<string, readonly string[]> = {
	border: ['top', 'right', 'bottom', 'left'],
	'border-color': ['top', 'right', 'bottom', 'left'],
	'border-block': ['top', 'bottom'],
	'border-block-color': ['top', 'bottom'],
	'border-block-start': ['top'],
	'border-block-end': ['bottom'],
	'border-inline': ['inline-start', 'inline-end'],
	'border-inline-color': ['inline-start', 'inline-end'],
	'border-inline-start': ['inline-start'],
	'border-inline-start-color': ['inline-start'],
	'border-inline-end': ['inline-end'],
	'border-inline-end-color': ['inline-end'],
	'border-top': ['top'],
	'border-top-color': ['top'],
	'border-bottom': ['bottom'],
	'border-bottom-color': ['bottom'],
	'border-left': ['left'],
	'border-left-color': ['left'],
	'border-right': ['right'],
	'border-right-color': ['right'],
};

type Rule = { selector: string; body: string; at: number; line: number };

// Leaf CSS rules only — a declaration block with no nested block inside it. That
// skips `@media`/`@supports` wrappers as containers while still reaching the
// rules within them, which is where two of the six findings lived.
function leafRules(source: string): Rule[] {
	const out: Rule[] = [];
	for (let i = 0; i < source.length; i++) {
		if (source[i] !== '{') continue;
		let depth = 0;
		let j = i;
		for (; j < source.length; j++) {
			if (source[j] === '{') depth++;
			else if (source[j] === '}' && --depth === 0) break;
		}
		if (j >= source.length) continue;
		const body = source.slice(i + 1, j);
		if (body.includes('{')) continue;
		let k = i - 1;
		while (k >= 0 && !'}{;'.includes(source[k])) k--;
		out.push({
			selector: source.slice(k + 1, i).replace(/\/\*[\s\S]*?\*\//g, '').trim(),
			// Comments are stripped from the BODY too: a `/* ... */` between two
			// declarations survives the `;` split and prefixes the next one, so a
			// commented `border-color:` stopped matching the property regex.
			body: body.replace(/\/\*[\s\S]*?\*\//g, ''),
			at: i,
			line: source.slice(0, i).split('\n').length,
		});
	}
	return out;
}

// The compound that a selector actually styles. `.feature .feature-icon` styles
// the icon, not the card, so `.feature`'s border must not be attributed to it —
// reading the whole selector's classes made four landing tiles a false positive.
function subject(selector: string): string {
	const parts = selector.split(/\s*[>+~]\s*|\s+/).filter(Boolean);
	return parts[parts.length - 1] ?? '';
}
const subjectClasses = (s: string) =>
	new Set([...subject(s).matchAll(/\.([\w-]+)/g)].map((m) => m[1]));
const subjectPseudos = (s: string) =>
	new Set([...subject(s).matchAll(/::?[\w-]+(?:\([^)]*\))?/g)].map((m) => m[0]));

const TINTABLE_SURFACES = [...SURFACE_TOKENS, 'color-fill-subtle'];

// A token that app.css does not declare is a component custom property the file
// itself points at one (`--kind-tint: var(--kind-3)`). EVERY value it is pointed
// at is resolved and checked, because a guard written against the one the author
// had in mind is § 519's lesson: `.hero` there resolves six kind tints and the
// two extremes are 0.4 apart.
function tintCandidates(
	marker: string,
	token: string,
	source: string,
): Array<{ name: string; hex: string }> {
	try {
		return [{ name: token, hex: resolveToken(marker, token) }];
	} catch {
		const out: Array<{ name: string; hex: string }> = [];
		for (const m of source.matchAll(
			new RegExp(`--${token}:\\s*var\\(\\s*--([\\w-]+)\\s*\\)`, 'g'),
		)) {
			try {
				out.push({ name: m[1], hex: resolveToken(marker, m[1]) });
			} catch {
				/* points at another undeclared property; nothing to resolve */
			}
		}
		return out;
	}
}

type TintFinding = {
	where: string;
	selector: string;
	theme: string;
	tint: string;
	background: string;
	border: string;
	ratio: number;
};

function tintedBoundaryFindings(): { findings: TintFinding[]; deferred: string[] } {
	const srcRoot = resolve(__dirname, '..');
	const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);
	const findings: TintFinding[] = [];
	const deferred = new Set<string>();
	const files: string[] = [];
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				if (!SKIP_DIRS.has(entry.name)) walk(path);
			} else if (/\.(svelte|css)$/.test(entry.name)) files.push(path);
		}
	})(srcRoot);

	for (const path of files) {
		const source = readFileSync(path, 'utf-8');
		const rules = leafRules(source);
		// File-local custom properties, kept with their selector so a border that
		// reads one resolves through the value that WINS on the element being
		// checked. The plan grid needs this: `.day` draws its box and its kind
		// stripe from one `--day-line`, and `.day.completed` re-points it.
		const localProps: Array<{
			classes: Set<string>;
			pseudos: Set<string>;
			name: string;
			value: string;
		}> = [];
		for (const rule of rules) {
			for (const declaration of rule.body.split(';')) {
				const m = declaration.match(/^\s*--([\w-]+)\s*:\s*([\s\S]+)$/);
				if (!m) continue;
				for (const one of rule.selector.split(',')) {
					localProps.push({
						classes: subjectClasses(one),
						pseudos: subjectPseudos(one),
						name: m[1],
						value: m[2].trim(),
					});
				}
			}
		}
		const expandLocals = (
			declaration: string,
			classes: Set<string>,
			pseudos: Set<string>,
		): string => {
			let out = declaration;
			for (let hop = 0; hop < 4; hop++) {
				let changed = false;
				for (const name of [...out.matchAll(/var\(\s*--([\w-]+)/g)].map((m) => m[1])) {
					const applicable = localProps.filter(
						(p) =>
							p.name === name &&
							[...p.classes].every((c) => classes.has(c)) &&
							[...p.pseudos].every((x) => pseudos.has(x)),
					);
					if (!applicable.length) continue;
					const winner = applicable[applicable.length - 1].value;
					out = out.replace(new RegExp(`var\\(\\s*--${name}\\s*\\)`, 'g'), winner);
					changed = true;
				}
				if (!changed) break;
			}
			return out;
		};
		const borderDecls: Array<{
			selector: string;
			classes: Set<string>;
			pseudos: Set<string>;
			edges: readonly string[];
			declaration: string;
			line: number;
		}> = [];
		for (const rule of rules) {
			for (const declaration of rule.body.split(';')) {
				const property = declaration.match(/^\s*(border[\w-]*)\s*:/)?.[1];
				const edges = property ? BORDER_EDGES[property] : undefined;
				if (!edges) continue;
				for (const one of rule.selector.split(',')) {
					borderDecls.push({
						selector: one.trim(),
						classes: subjectClasses(one),
						pseudos: subjectPseudos(one),
						edges,
						declaration: declaration.trim(),
						line: rule.line,
					});
				}
			}
		}
		for (const rule of rules) {
			const backgrounds = rule.body
				.split(';')
				.filter((d) => /^\s*(background|background-image)\s*:/.test(d));
			if (!backgrounds.length) continue;
			const tints: Array<{ token: string | null; share: number; over: string }> = [];
			for (const declaration of backgrounds) {
				for (const m of declaration.matchAll(TINT_OVER_SURFACE)) {
					if (TINTABLE_SURFACES.includes(m[3])) {
						tints.push({ token: m[1], share: parseFloat(m[2]), over: m[3] });
					}
				}
				const plain = declaration.match(/^\s*background\s*:\s*var\(\s*--([\w-]+)\s*\)\s*$/)?.[1];
				if (plain === 'color-fill-subtle') tints.push({ token: null, share: 0, over: plain });
			}
			if (!tints.length) continue;
			for (const one of rule.selector.split(',').map((s) => s.trim())) {
				const classes = subjectClasses(one);
				const pseudos = subjectPseudos(one);
				if (!classes.size) continue;
				const applicable = borderDecls.filter(
					(b) =>
						b.classes.size > 0 &&
						[...b.classes].every((c) => classes.has(c)) &&
						[...b.pseudos].every((p) => pseudos.has(p)),
				);
				const perEdge: Record<string, (typeof applicable)[number]> = {};
				for (const b of applicable) for (const edge of b.edges) perEdge[edge] = b;
				const effective = [...new Set(Object.values(perEdge))]
					.map((b) => ({ ...b, painted: expandLocals(b.declaration, classes, pseudos) }))
					.filter((b) => b.painted.includes('--color-border'));
				for (const edge of effective) {
					// `var(--x, var(--color-border))` is a per-instance default a
					// parent sets inline — css_token_guard.test.ts draws the same
					// line — so the fallback is not the painted value here.
					if (/var\(\s*--[\w-]+\s*,/.test(edge.painted)) {
						deferred.add(`${path}:${edge.line}  ${edge.declaration.trim()}`);
						continue;
					}
					const accentMix = edge.painted.match(LINE_MIXED_WITH_ACCENT);
					for (const { label, marker } of THEMES) {
						const line = resolveToken(marker, 'color-border');
						for (const tint of tints) {
							const surface = resolveToken(marker, tint.over);
							const candidates = tint.token
								? tintCandidates(marker, tint.token, source)
								: [{ name: tint.over, hex: surface }];
							if (!candidates.length) {
								deferred.add(`${path}:${rule.line}  unresolvable tint --${tint.token}`);
								continue;
							}
							for (const candidate of candidates) {
								const background = tint.token
									? mixOverHex(candidate.hex, tint.share, surface)
									: surface;
								// A card that mixes its own tint into the line resolves BOTH
								// halves from the same property, so they must move together —
								// `.hero`'s six kind tints would otherwise be crossed with
								// each other and read six ratios that no render produces.
								const accents = !accentMix
									? [line]
									: accentMix[1] === tint.token
										? [mixOverHex(candidate.hex, parseFloat(accentMix[2]), line)]
										: tintCandidates(marker, accentMix[1], source).map((c) =>
												mixOverHex(c.hex, parseFloat(accentMix[2]), line),
											);
								for (const border of accents) {
									const ratio = contrastRatio(border, background);
									if (ratio >= AA_NON_TEXT) continue;
									findings.push({
										where: `${path}:${rule.line} (border at :${edge.line})`,
										selector: one,
										theme: label,
										tint: tint.token
											? `--${candidate.name} @${tint.share}% over --${tint.over}`
											: `--${tint.over}`,
										background,
										border,
										ratio,
									});
								}
							}
						}
					}
				}
			}
		}
	}
	return { findings, deferred: [...deferred] };
}

test('every boundary drawn on a tinted surface clears 3:1 where it lands', () => {
	const { findings } = tintedBoundaryFindings();
	assert.equal(
		findings.length,
		0,
		`A --color-border boundary is drawn on an accent-tinted background and falls below ` +
			`${AA_NON_TEXT}:1 (WCAG 1.4.11). Mix the surface's OWN accent into the line at ` +
			`roughly twice the tint's share — that moves the line further toward the accent ` +
			`than the tint moved the surface, so the gap widens:\n` +
			findings
				.map(
					(f) =>
						`  ${f.ratio.toFixed(3)}:1  ${f.where}  ${f.selector}  [${f.theme}]  ` +
						`${f.tint} = ${f.background}, border ${f.border}`,
				)
				.join('\n'),
	);
});

// Count-pinned so the one shape the scan cannot resolve stays the one shape it
// cannot resolve. A new `var(--x, var(--color-border))` edge on a tinted surface
// fails here rather than passing silently.
test('exactly one tinted-surface boundary defers to a per-instance fallback', () => {
	const { deferred } = tintedBoundaryFindings();
	assert.equal(
		deferred.length,
		1,
		`the tinted-boundary scan defers ${deferred.length} declaration(s), expected 1 ` +
			`(the plan grid's kind stripe):\n${deferred.join('\n')}`,
	);
	assert.match(deferred[0], /plans\/\[id\]\/\+page\.svelte/);
});

// The scan's own machinery, in both directions. Each of these is a bug it had
// while being written, and each would make it silently useless rather than loud.
test('the tinted-boundary scan attributes borders to the right element', () => {
	const rules = leafRules('.a { color: red; }\n@media (x) {\n.b:hover { border: 0; }\n}\n');
	assert.deepEqual(
		rules.map((r) => r.selector),
		['.a', '.b:hover'],
		'leafRules must reach into @media and must not return the wrapper itself',
	);
	assert.deepEqual([...subjectClasses('.feature:nth-child(1) .feature-icon')], ['feature-icon']);
	assert.deepEqual([...subjectClasses('.day.completed')].sort(), ['completed', 'day']);
	assert.deepEqual([...subjectPseudos('.relink-run:hover:not(:disabled)')], [
		':hover',
		':not(:disabled)',
	]);
	assert.deepEqual(BORDER_EDGES['border'], ['top', 'right', 'bottom', 'left']);
	assert.deepEqual(BORDER_EDGES['border-top'], ['top']);
});

// A planted violation on the real tree, so the scan is proved to fire and to
// name its site rather than merely to pass today.
test('the tinted-boundary scan fires on a planted violation', () => {
	const path = resolve(__dirname, '../routes/clubs/[slug]/+page.svelte');
	const original = readFileSync(path, 'utf-8');
	const planted = original.replace(
		'border: 1px solid color-mix(in srgb, var(--color-primary) 30%, var(--color-border));',
		'border: 1px solid var(--color-border);',
	);
	assert.notEqual(planted, original, '.next-event-card no longer carries the tinted line');
	writeFileSync(path, planted);
	try {
		const { findings } = tintedBoundaryFindings();
		const hit = findings.find((f) => f.selector === '.next-event-card');
		assert.ok(hit, 'the scan did not flag the planted bare line token');
		assert.ok(
			hit!.ratio < AA_NON_TEXT,
			`the planted violation reports ${hit!.ratio.toFixed(3)}:1, which is not a failure`,
		);
	} finally {
		writeFileSync(path, original);
	}
});

// The race-day hero is a FIXED canvas — it paints its own gradient and follows
// no theme — so its colours cannot be checked against a surface token and were
// therefore never checked at all: `color: white` sat at 2.803:1 on the orange
// stop, the .feasibility inks at 1.989-3.021:1 on the veil they actually paint
// over (the 2.295-3.572:1 in the source comment was measured on the BARE
// gradient, § 503's trap one more time), and the toggle's edge at 1.494:1.
//
// The floor is derived from the panel's own declarations rather than from a
// pinned number: the gradient stops must be the two theme-INDEPENDENT "-strong"
// fills (already held to white-on-AA above and forbidden a dark override), and
// then every white veil the panel layers on top is composited over the WORST
// stop — including the midpoint, which neither end measures.
test('every ink on the race-day fixed canvas clears AA over its own veil', () => {
	const source = readFileSync(resolve(__dirname, 'components/RaceDayPanel.svelte'), 'utf-8');
	const panel = source.match(/\.race-day-panel \{([\s\S]*?)\n\t\}/)?.[1];
	assert.ok(panel, 'RaceDayPanel has no .race-day-panel rule');
	const gradient = panel!.match(/background:\s*(linear-gradient\([\s\S]*?\));/)?.[1];
	assert.ok(gradient, '.race-day-panel declares no gradient background');
	const stopTokens = [...gradient!.matchAll(/var\(\s*--([\w-]+)\s*\)/g)].map((m) => m[1]);
	assert.deepEqual(
		stopTokens,
		['color-warning-strong', 'color-danger-strong'],
		'the hero gradient must be built from the theme-independent "-strong" fills, whose ' +
			'white-on-AA is pinned by the test above; a theme surface token would resolve to ' +
			'the wrong side on a canvas that does not follow the theme.',
	);
	const ends = stopTokens.map((n) => resolveToken(':root {', n));
	const stops = [ends[0], mixOverHex(ends[0], 50, ends[1]), ends[1]];

	// Rule -> the veil it fills with (white OR black — an inset sub-panel is the
	// deeper one) and the ink it sets. A rule that declares no ink of its own
	// takes whatever its class siblings declare, because the verdict and
	// confidence inks live in sibling rules that set only a `color:`; only when
	// no sibling declares one either does it inherit the panel's white.
	const WHITE = '#FFFFFF';
	const offenders: string[] = [];
	for (const rule of source.matchAll(/([^{}]+)\{([^{}]*)\}/g)) {
		const [, selector, body] = rule;
		const veil = body.match(/background:\s*rgba\((255,\s*255,\s*255|0,\s*0,\s*0),\s*([0-9.]+)\)/);
		if (veil == null) continue;
		const [, channel, alpha] = veil;
		const over = channel.startsWith('0') ? '#000000' : WHITE;
		const backings = stops.map((s) => mixOverHex(over, Number(alpha) * 100, s));
		const inks = [...body.matchAll(/(?<![a-z-])color:\s*(#[0-9A-Fa-f]{6}|white)/g)].map((m) =>
			m[1] === 'white' ? WHITE : m[1],
		);
		const base = selector.trim().split(/[\s.:]+/).filter(Boolean)[0];
		const siblingInks = [
			...source.matchAll(
				new RegExp(`\\.${base}[^{}]*\\{[^{}]*?(?<![a-z-])color:\\s*(#[0-9A-Fa-f]{6}|white)`, 'g'),
			),
		].map((m) => (m[1] === 'white' ? WHITE : m[1]));
		const resolved = [...new Set([...inks, ...siblingInks])];
		for (const ink of resolved.length ? resolved : [WHITE]) {
			for (const backing of backings) {
				const ratio = contrastRatio(ink, backing);
				if (ratio < AA_NORMAL) {
					offenders.push(
						`${selector.trim()}: ${ink} on rgba(${channel},${alpha}) over ${backing} is ${ratio.toFixed(3)}:1`,
					);
				}
			}
		}
	}
	assert.equal(
		offenders.length,
		0,
		`An ink on the race-day fixed canvas fails WCAG AA over the veil it paints on. ` +
			`Deepen the veil or darken the ink — the panel follows no theme, so there is no ` +
			`token to route to:\n${offenders.join('\n')}`,
	);

	// A thinned foreground on this canvas is the same class of defect one step
	// removed: 0.85 composited to 3.693:1 over the 0.10 veil beneath it.
	// Comments stripped first: the rule that explains why a thinning was removed
	// quotes the value it removed, and flagging that would push the next editor
	// toward deleting the reasoning.
	const thin = [...source.replace(/\/\*[\s\S]*?\*\//g, '').matchAll(/opacity:\s*(0\.\d+)/g)]
		.map((m) => Number(m[1]))
		.filter((o) => o < 0.9);
	assert.deepEqual(thin, [], 'a foreground on the hero may not be thinned below 0.9.');
});

// The public landing's four feature-icon accents. Each is a base token's tint
// under a theme-aware ink, and the rules are READ OUT OF THE SOURCE so the pair
// cannot drift apart or be re-frozen as a hex: the four literals they replace
// (#4F46E5 / #EC4899 / #10B981 / #F97316) each failed in exactly one theme
// because a fixed hue cannot suit both a near-white and a dark-violet card.
// Marketing copy is still content, so the 4.5:1 floor applies rather than 3:1.
for (const { label, marker } of THEMES) {
	test(`landing feature-icon accents meet AA on their own tint — ${label}`, () => {
		const page = readFileSync(resolve(__dirname, '../routes/+page.svelte'), 'utf-8');
		const rules = [
			...page.matchAll(
				/\.feature:nth-child\((\d)\) \.feature-icon \{\s*background:\s*color-mix\(in srgb, var\(--([\w-]+)\) (\d+)%, var\(--([\w-]+)\)\);\s*color:\s*var\(--([\w-]+)\);/g,
			),
		];
		assert.equal(rules.length, 4, 'the landing must declare four token-based feature accents');
		for (const [, nth, base, pct, surfaceName, ink] of rules) {
			const tint = mixOverHex(
				resolveToken(marker, base),
				Number(pct),
				resolveToken(marker, surfaceName),
			);
			const ratio = contrastRatio(resolveToken(marker, ink), tint);
			assert.ok(
				ratio >= AA_NORMAL,
				`feature card ${nth}: --${ink} on --${base}@${pct}% over --${surfaceName} (${tint}) is ${ratio.toFixed(3)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
			);
		}
	});
}

// The identity-avatar disc. A gradient is the one fill a foreground hex cannot
// be reasoned about by eye, and --gradient-primary proved it: white on its light
// light-mode third stop and its two dark-mode stops read 2.081 / 2.153:1, which
// is § 481's finding on the web side. --gradient-avatar exists so the disc's
// stops are ALL AA-safe under --color-on-primary rather than only some of them,
// and this checks every stop rather than the pair it was written with.
for (const { label, marker } of THEMES) {
	test(`every --gradient-avatar stop pairs AA with --color-on-primary — ${label}`, () => {
		const rootBlock = block(':root {');
		const value = rootBlock.match(/--gradient-avatar:\s*([\s\S]*?);/)?.[1];
		assert.ok(value, 'app.css declares no --gradient-avatar');
		const stops = [
			...[...value!.matchAll(/var\(\s*--([\w-]+)\s*\)/g)].map((m) => resolveToken(marker, m[1])),
			...(value!.match(/#[0-9A-Fa-f]{6}/g) ?? []),
		];
		assert.ok(stops.length >= 2, `--gradient-avatar resolved to ${stops.length} stop(s)`);
		const ink = resolveToken(marker, 'color-on-primary');
		for (const stop of stops) {
			const ratio = contrastRatio(ink, stop);
			assert.ok(
				ratio >= AA_NORMAL,
				`--color-on-primary (${ink}) on the --gradient-avatar stop ${stop} is ${ratio.toFixed(3)}:1 in ${label}; the initial is text and needs >=${AA_NORMAL}:1. A gradient whose stops straddle the mid-luminance band has no legible single foreground — narrow the stops.`,
			);
		}
	});
}

// The seeded (per-entity hue) branch of the same component takes no theme token
// at all, so its floor is asserted over the hue wheel in format/avatar.test.ts.
// What is pinned here is that the component still routes through the clamp — a
// literal `color: white` beside a per-entity hue is the exact defect § 481 named.
test('Avatar paints no fixed foreground beside a per-entity or gradient fill', () => {
	const source = readFileSync(resolve(__dirname, 'components/Avatar.svelte'), 'utf-8');
	assert.match(
		source,
		/color:\s*var\(--av-fg\)/,
		'Avatar.svelte must take its foreground from --av-fg, not a literal.',
	);
	assert.match(source, /seedForeground\(/, 'the seeded branch must pick its ink by contrast.');
	assert.doesNotMatch(
		source,
		/(?<![a-z-])color:\s*(?:white|#[0-9A-Fa-f]{3,8})\s*;/,
		'Avatar.svelte carries a fixed foreground literal.',
	);
});

// --color-success-text / --color-danger-text, checked on every plain surface
// (the signed readiness delta is bare text on the card) AND on the deepest
// same-hue chip tint the source actually paints — which is the tightest case,
// because the tint pulls the background toward the text. The base tokens they
// replace are 3.28:1 (success on white) and 4.14:1 (danger on the page); 96
// sites across 46 files were still using them as bare text.
for (const { label, marker } of THEMES) {
	test(`success/danger -text tokens meet WCAG AA as text — ${label}`, () => {
		for (const status of ['success', 'danger'] as const) {
			const name = `color-${status}-text`;
			const fg = resolveToken(marker, name);
			for (const surfaceName of SURFACE_TOKENS) {
				const surface = resolveToken(marker, surfaceName);
				const ratio = contrastRatio(fg, surface);
				assert.ok(
					ratio >= AA_NORMAL,
					`--${name} (${fg}) on --${surfaceName} (${surface}) is ${ratio.toFixed(2)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
				);
			}
			const base = resolveToken(marker, `color-${status}`);
			for (const { pct, over } of deepestChipTints(status)) {
				for (const surfaceName of over) {
					const chip = mixOverHex(base, pct, resolveToken(marker, surfaceName));
					const ratio = contrastRatio(fg, chip);
					assert.ok(
						ratio >= AA_NORMAL,
						`--${name} (${fg}) on the deepest --color-${status} chip tint (${pct}% over --${surfaceName} = ${chip}) is ${ratio.toFixed(3)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1. Either retune the -text token or shallow the chip.`,
					);
				}
			}
		}
	});
}

// The deepest same-hue tints a status chip paints, READ OUT OF THE SOURCE so
// the floor above cannot go stale when someone deepens a chip. A tint mixed
// against `transparent` composites over whatever happens to be behind it, so it
// is measured over both the card and the page; one mixed against a named
// surface token is opaque and is measured only over that surface. The
// --color-<status>-light tokens are rgba, hence backing-agnostic too.
// Nested tints are the one case this cannot see — a chip inside an already-
// tinted chip composites to 1-(1-a)(1-b), which is why the three RSVP count
// pills mix against --color-surface (opaque, so they cannot compound) rather
// than against transparent.
const UNKNOWN_BACKING = ['color-surface', 'color-bg'];
function deepestChipTints(status: 'success' | 'danger'): Array<{ pct: number; over: string[] }> {
	const deepest = new Map<string, number>();
	const record = (pct: number, backing: string) =>
		deepest.set(backing, Math.max(deepest.get(backing) ?? 0, pct));
	const re = new RegExp(
		`background(?:-color)?:\\s*color-mix\\([^;]*var\\(--color-${status}\\)\\s*(\\d+)%\\s*,\\s*(.*)$`,
	);
	for (const hit of scanSource((line) => re.test(line))) {
		const m = hit.match(re)!;
		record(Number(m[1]), m[2].trim().match(/var\(\s*--([\w-]+)\s*\)/)?.[1] ?? '');
	}
	for (const m of css.matchAll(
		new RegExp(`--color-${status}-light:\\s*rgba\\([^)]*,\\s*([0-9.]+)\\s*\\)`, 'g'),
	)) {
		record(Number(m[1]) * 100, '');
	}
	assert.ok(deepest.size > 0, `no --color-${status} chip tint found to measure`);
	return [...deepest].map(([backing, pct]) => ({
		pct,
		over: backing === '' ? UNKNOWN_BACKING : [backing],
	}));
}

// The light values have always matched mobile's AppSemanticColors and the
// token comment says so; the dark ones silently did not (web reverted to the
// base hue, mobile carries its own pair) until the chip-tint floor above forced
// the question. A Dart file cannot import a CSS custom property, so the lockstep
// the comment claims is checked here, the same way the chart and zone palettes
// already are.
test('success/danger -text tokens match mobile AppSemanticColors', () => {
	const dart = readFileSync(
		resolve(__dirname, '../../../../packages/ui_kit/lib/src/theme/app_theme.dart'),
		'utf-8',
	);
	for (const [marker, symbol] of [
		[':root {', 'light'],
		[':root[data-theme="dark"]', 'dark'],
	] as const) {
		const body = dart.match(
			new RegExp(`static const AppSemanticColors ${symbol} = AppSemanticColors\\(([\\s\\S]*?)\\n  \\);`),
		);
		assert.ok(body, `app_theme.dart has no ${symbol} AppSemanticColors`);
		for (const status of ['success', 'danger']) {
			const hex: string | undefined = body![1].match(new RegExp(`${status}: Color\\(0xFF([0-9A-Fa-f]{6})\\)`))?.[1];
			assert.ok(hex, `${symbol} AppSemanticColors has no ${status}`);
			assert.equal(
				resolveToken(marker, `color-${status}-text`).toUpperCase(),
				`#${hex!.toUpperCase()}`,
				`--color-${status}-text in ${marker} has drifted from AppSemanticColors.${symbol}.${status}.`,
			);
		}
	}
});
