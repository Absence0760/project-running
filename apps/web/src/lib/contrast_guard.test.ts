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
import { readFileSync, readdirSync } from 'node:fs';
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

// The base --color-warning / -secondary / -accent-cyan tokens are tuned for
// tints, borders and dark-mode use; as a bare `color:` (text/icon) on a light
// surface they fail WCAG 1.4.3 (issue #368). The theme-aware -text variants
// exist for foreground use — this scan stops the bare tokens creeping back as
// text. Quoted JS props (`color: 'var(--color-accent-cyan)'`, the macro-ring
// stroke colours) are not text and don't match (the `'` breaks `color:\s*var`).
test('no source file uses a bare accent/status token as a text colour', () => {
	// `color:` (rejecting `background-color:`/`border-color:` via the leading
	// boundary) set to a base accent token, NOT its -text / -strong / -hover
	// variant (the trailing `(?!-)` guards those).
	const offender = /(?<![a-z-])color:\s*var\(\s*--color-(?:warning|secondary|accent-cyan)\)(?!-)/;
	const hits = scanSource((line) => offender.test(line));
	assert.equal(
		hits.length,
		0,
		`A base accent token (--color-warning / -secondary / -accent-cyan) is used as a text ` +
			`colour; it fails WCAG AA on light surfaces (2.05-3.06:1). Use the theme-aware ` +
			`--color-<token>-text variant instead:\n${hits.join('\n')}`,
	);
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

// The mobile TrainingLoadPalette is the same palette by value — a Dart file
// cannot import a CSS custom property, so the lockstep is checked here.
test('training-load series match mobile TrainingLoadPalette', () => {
	const dart = readFileSync(
		resolve(__dirname, '../../../mobile_android/lib/widgets/training_load_chart.dart'),
		'utf-8',
	);
	const expected: Array<[string, string, string]> = [
		[':root {', 'light', 'chart-fitness'],
		[':root {', 'light', 'chart-fatigue'],
		[':root {', 'light', 'chart-form'],
		[':root[data-theme="dark"]', 'dark', 'chart-fitness'],
		[':root[data-theme="dark"]', 'dark', 'chart-fatigue'],
		[':root[data-theme="dark"]', 'dark', 'chart-form'],
	];
	for (const [marker, brightness, token] of expected) {
		const series = token.replace('chart-', '');
		const body = dart.match(
			new RegExp(`static const ${brightness} = TrainingLoadPalette\\(([\\s\\S]*?)\\n  \\);`),
		);
		assert.ok(body, `training_load_chart.dart has no ${brightness} palette`);
		const hex = body![1].match(new RegExp(`${series}: Color\\(0xFF([0-9A-Fa-f]{6})\\)`))?.[1];
		assert.ok(hex, `${brightness} palette has no ${series} colour`);
		assert.equal(
			resolveToken(marker, token).toUpperCase(),
			`#${hex!.toUpperCase()}`,
			`--${token} in ${marker} has drifted from TrainingLoadPalette.${brightness}.${series}.`,
		);
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

// Mobile cannot import a CSS custom property, so the lockstep is checked here.
test('HR zone tokens match the mobile hr_zone_palette', () => {
	const dart = readFileSync(
		resolve(__dirname, '../../../mobile_android/lib/hr_zone_palette.dart'),
		'utf-8',
	);
	for (const [marker, symbol] of [
		[':root {', 'hrZoneColoursLight'],
		[':root[data-theme="dark"]', 'hrZoneColoursDark'],
	] as const) {
		const body = dart.match(
			new RegExp(`const ${symbol} = <Color>\\[([\\s\\S]*?)\\];`),
		);
		assert.ok(body, `hr_zone_palette.dart has no ${symbol}`);
		const hexes = [...body![1].matchAll(/Color\(0xFF([0-9A-Fa-f]{6})\)/g)].map(
			(m) => `#${m[1].toUpperCase()}`,
		);
		assert.equal(hexes.length, 5, `${symbol} does not carry five bands`);
		hexes.forEach((hex, i) => {
			assert.equal(
				resolveToken(marker, `zone-${i + 1}`).toUpperCase(),
				hex,
				`--zone-${i + 1} in ${marker} has drifted from ${symbol}[${i}].`,
			);
		});
	}
});

// --color-success-text / --color-danger-text. Same shape as the ACCENT_TEXT
// trio above but checked on the plain surfaces rather than a chip tint: the
// signed readiness delta is bare text on the card. The base tokens they
// replace are 3.28:1 (success on white) and 4.14:1 (danger on the page) —
// tuned for fills and borders, below AA as text. They carry the same values as
// mobile's AppSemanticColors so the delta reads identically on both platforms.
for (const { label, marker } of THEMES) {
	test(`success/danger -text tokens meet WCAG AA as text — ${label}`, () => {
		for (const name of ['color-success-text', 'color-danger-text']) {
			const fg = resolveToken(marker, name);
			for (const surfaceName of SURFACE_TOKENS) {
				const surface = resolveToken(marker, surfaceName);
				const ratio = contrastRatio(fg, surface);
				assert.ok(
					ratio >= AA_NORMAL,
					`--${name} (${fg}) on --${surfaceName} (${surface}) is ${ratio.toFixed(2)}:1 in ${label}; WCAG AA requires >=${AA_NORMAL}:1.`,
				);
			}
		}
	});
}
