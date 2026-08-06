// Source-scan guard for issue #666: status-role colours on web come from the
// app.css token vocabulary (--color-success/-warning/-danger + their -text /
// -light / -strong pairs, --color-crown / --color-on-crown), never from a raw
// Tailwind/Material hex literal. The web counterpart of mobile's
// status_color_literal_guard_test.dart (decisions.md § 480), and the reason it
// was sequenced AFTER § 506: doing it first would have baked every
// fallback-hidden hex into this allowlist as legitimate.
//
// Why a literal is a bug even when it measures well: the tokens are held to
// WCAG AA per THEME by contrast_guard.test.ts, and a frozen hex opts out of
// that in whichever theme it was not eyeballed in. Measured on the surfaces
// the site actually paints, the sweep this guard closes found the fill frozen
// far more often than the ink: `#d1fae5` behind a confidence chip reads
// 14.253:1 against the dark card it sits on — a pale mint panel blazing on
// dark purple — while its own ink was a respectable 4.835:1.
//
// Three kinds of exemption, all narrow, all count-pinned so the allowlist can
// only ever SHRINK:
//  * app.css custom-property DECLARATIONS. The token vocabulary has to be
//    spelled somewhere and this is that place. Only declaration lines are
//    exempt, not the whole file: `.btn-primary` shipped `color: #FFFFFF` over
//    a `--color-primary` fill that flips to a light coral in dark (2.081:1),
//    which is exactly the defect § 506 minted --color-on-primary for.
//  * DATA palettes. Per § 480's line: a colour that communicates state on a
//    theme surface is a status role and takes a token; a colour that IS data
//    — pace ramps, heat scales, zone bands, chart series, cartographic
//    markers, medal metals, badge tiers — keeps its fixed hue.
//  * Fixed canvases that do not follow the device theme at all: the print
//    stylesheet (white paper) and the race-day brand hero.
//
// Count-pinning is what makes those honest: a NEW literal in an exempted file
// still fails, and a migrated palette forces its entry's removal.
//
// When this test fails, route the colour onto the token — do not add an entry.
// Only a genuine new data palette or fixed canvas earns one.
//
// Scope declared, so a future reader does not mistake silence for coverage.
// This file now holds THREE rules of widening reach:
//  1. the status-hue ban below — the 39 named six-digit status hues (with an
//     optional 8-digit alpha suffix), the mobile twin's shape, whose failure
//     message says "route it onto the token" because for a status role that
//     is always the answer;
//  2. the dead-fallback rule in the middle, which is not hue-scoped at all:
//     a hex fallback of any length on any global app.css token, because
//     there the defect is the frozen value, not the hue;
//  3. the COMPLETE REGISTER at the foot, which requires every six-digit
//     literal outside app.css declarations to be recorded with a role and an
//     exact count. That one subsumes (1)'s coverage — (1) is kept for its
//     message, not its reach.
// None of the three polices 3-digit shorthands or rgb()/hsl() spellings.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join, relative, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = resolve(__dirname, '..');
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

// The Tailwind / Material status ramps plus this project's own status + crown
// token VALUES — the last group so a token can never be re-spelled as the
// literal it is defined as, which is how two surfaces drift apart while both
// look correct at their call site.
const BANNED_HEXES = [
	// greens (success)
	'047857', '10B981', '15803D', '16A34A', '1B5E20', '22C55E', '2E7D32',
	'4A9F5A', '66BB6A', '6BC07A', 'D1FAE5', 'ECFDF5',
	// ambers (warning)
	'856404', '9A5B0A', 'B26A00', 'B45309', 'D97706', 'E6A96B', 'EAB308',
	'F59E0B', 'F97316', 'FACC15', 'FBBF24', 'FEF3C7', 'FFF3CD',
	// reds (danger)
	'B0392C', 'B91C1C', 'C84D3F', 'DC2626', 'E07468', 'EF4444', 'EF5350',
	'FEE2E2', 'FEF2F2',
	// crown / rank golds
	'B8860B', 'D4A017', 'D4AF37', 'F5B30A', 'F6D671',
];

// A banned hue, optionally carrying an 8-digit alpha suffix, and NOT part of a
// longer hex run (so `#EF4444` inside a 12-char id string is not a colour).
const BANNED_HEX = new RegExp(
	`#(${BANNED_HEXES.join('|')})(?:[0-9a-fA-F]{2})?(?![0-9a-fA-F])`,
	'gi',
);

// A custom-property declaration in app.css. `--x: <value>` — the token
// vocabulary's one legitimate home. Deliberately anchored to the start of the
// (trimmed) line so a rule that merely MENTIONS a token does not qualify.
const TOKEN_DECLARATION = /^--[a-zA-Z0-9-]+\s*:/;

// file -> hex -> exact expected occurrence count. Every entry names why the
// hue is not a status role there. Paths are POSIX-relative to apps/web/src.
const DATA_PALETTES: Record<string, Record<string, number>> = {
	// Badge tier metals (bronze / silver / gold / platinum). A four-rung metal
	// ladder is data; only the gold rung collides with the crown hue.
	'lib/components/BadgeGrid.svelte': { D4AF37: 1 },
	'lib/components/SocialFeed.svelte': { D4AF37: 1 },
	'routes/share/badge/[id]/+page.svelte': { D4AF37: 1 },
	// Rank-1 medal gradient. The opaque pill's fill carries the meaning and
	// its foreground is fixed with it (§ 495); AA pinned by the
	// "fixed medal rank pills" test in contrast_guard.test.ts.
	'lib/components/ChallengeLeaderboard.svelte': { F6D671: 1, D4A017: 1 },
	'lib/components/RunSegmentEfforts.svelte': { B45309: 1 },
	// Per-stat-card accent gradients: four chart series, separated by hue.
	'lib/components/PeriodSummary.svelte': { '10B981': 1, F97316: 1, F59E0B: 1, EF4444: 1 },
	// Cartographic: privacy-zone marker, its fill and its outline. Drawn on
	// the basemap, not on a theme surface.
	'lib/components/PrivacyZonePicker.svelte': { DC2626: 3 },
	// Painted start / finish caps on the mini track preview — the exact twin
	// of mobile's track_preview.dart allowlist entry.
	'lib/components/TrackPreview.svelte': { '22C55E': 1, EF4444: 1 },
	// Course start / finish checkpoint hues, twin of mobile's
	// roadbook_screen.dart entry.
	'routes/routes/[id]/roadbook/+page.svelte': { '22C55E': 1, EF4444: 1 },
	// Fixed brand hero. The canvas follows no theme, so the ONE literal left is
	// the verdict green shared by the confidence chip and the feasibility pill,
	// which are the same "good" role on the same white pill (4.862:1 worst case
	// across the ramp). The eight it replaces were the redesign: the gradient
	// stops are the two theme-independent "-strong" fills now, the three pale
	// .feasibility pastels are dark inks on an opaque pill, and the whole
	// canvas is measured per-veil by contrast_guard.test.ts. The amber and red
	// inks that came with it are not on the ban list, and the active toggle's
	// #8F2F24 is deliberately NOT --color-danger-strong's value.
	'lib/components/RaceDayPanel.svelte': { '047857': 2 },
	// Fixed canvas: the @media print sheet targets white paper, so a theme
	// token would resolve to the SCREEN theme and print dark-on-dark. The
	// amber was deepened from #b26a00 (4.238:1 on paper, under AA) to
	// #9E5C00 (5.270:1 on white, 5.031:1 on the mint price card).
	'routes/compare/+page.svelte': { '1B5E20': 1 },
	// Gold star over a FIXED 0.65-black scrim on a route thumbnail, not on a
	// theme surface. --color-crown is the deliberately dark light-mode gold
	// and would read 1.123:1 here against 4.196:1 for this hue — the naive
	// swap is 3.7x worse, which is § 503's "measure it where it lands".
	'routes/routes/+page.svelte': { FBBF24: 1 },
};

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

// Blank out comment bodies, preserving line count and column offsets so a
// reported line number still points at the source line. A hex quoted in a
// comment is documentation — every contrast note in app.css and in this
// project's ADR-style comments cites the measured hexes — and flagging those
// would push a future editor toward deleting the reasoning.
export function maskComments(source: string): string {
	const chars = [...source];
	const n = chars.length;
	const blank = (from: number, to: number): void => {
		for (let i = from; i < to && i < n; i++) if (chars[i] !== '\n') chars[i] = ' ';
	};
	let i = 0;
	while (i < n) {
		if (chars[i] === '/' && chars[i + 1] === '*') {
			let j = i + 2;
			while (j < n && !(chars[j] === '*' && chars[j + 1] === '/')) j++;
			blank(i, j + 2);
			i = j + 2;
			continue;
		}
		if (chars[i] === '<' && source.startsWith('<!--', i)) {
			const j = source.indexOf('-->', i);
			blank(i, j < 0 ? n : j + 3);
			i = (j < 0 ? n : j + 3);
			continue;
		}
		// A `//` line comment, recognised only when it OPENS the line. CSS has
		// no line comments at all, so this exists for the <script> block, and
		// the bias is deliberately toward masking too little: masking too much
		// silently drops violations, while masking too little at worst flags a
		// hex quoted in a trailing comment, which is visible and fixable. A
		// `url('https://x/a//b#EF4444')` is exactly the case that punishes the
		// looser rule.
		if (chars[i] === '/' && chars[i + 1] === '/') {
			let k = i - 1;
			while (k >= 0 && (chars[k] === ' ' || chars[k] === '\t')) k--;
			if (k < 0 || chars[k] === '\n') {
				let j = i;
				while (j < n && chars[j] !== '\n') j++;
				blank(i, j);
				i = j;
				continue;
			}
		}
		i++;
	}
	return chars.join('');
}

// Every banned hue a line paints, uppercased. `isAppCss` exempts a custom
// property DECLARATION, which is the only place the vocabulary may be spelled.
export function bannedHexesOn(line: string, isAppCss = false): string[] {
	if (isAppCss && TOKEN_DECLARATION.test(line.trim())) return [];
	return [...line.matchAll(BANNED_HEX)].map((m) => m[1].toUpperCase());
}

// Both directions. `flags` is what the matcher must extract; an empty array
// means the line must be left entirely alone.
const MATCHER_FIXTURES: Array<{ source: string; flags: string[]; appCss?: true; why: string }> = [
	// --- must flag ---
	{ source: '\tcolor: #EF4444;', flags: ['EF4444'], why: 'the plain case' },
	{ source: '\tcolor: #ef4444;', flags: ['EF4444'], why: 'lowercase spelling of the same hue' },
	{ source: '\t.x { background: #d1fae5; color: #047857; }', flags: ['D1FAE5', '047857'], why: 'two hues on one line' },
	{ source: "\tconst c = '#22c55e';", flags: ['22C55E'], why: 'a quoted JS/MapLibre paint value' },
	{ source: '\t<circle fill="#ef4444" />', flags: ['EF4444'], why: 'an SVG presentation attribute' },
	{ source: '\tbackground: color-mix(in srgb, #f5b30a 12%, transparent);', flags: ['F5B30A'], why: 'nested in a CSS function' },
	{ source: '\tbackground: linear-gradient(90deg, #F97316, #F59E0B);', flags: ['F97316', 'F59E0B'], why: 'two stops of one gradient' },
	{ source: '\tcolor: #EF444480;', flags: ['EF4444'], why: 'the 8-digit alpha spelling must not dodge the ban' },
	{ source: '\t--tier-color: #d4af37;', flags: ['D4AF37'], why: 'a local custom property outside app.css is still paint' },
	{ source: '\tcolor: #FEF3C7;', flags: ['FEF3C7'], why: 'a pale status TINT is banned too — a frozen fill was the commoner defect' },
	// --- must spare ---
	{ source: '\tcolor: var(--color-danger-text);', flags: [], why: 'the token, which is the fix' },
	{ source: '\tcolor: #1d4ed8;', flags: [], why: 'a hue outside the declared status vocabulary' },
	{ source: '\tcolor: #F2A07B;', flags: [], why: '--color-accent-orange is not a status role' },
	{ source: '\tid = "abcdefEF4444";', flags: [], why: 'no # sigil' },
	{ source: '\tcolor: #EF4444AABB;', flags: [], why: 'part of a longer hex run, so not a colour' },
	{ source: '\t--color-danger: #C84D3F;', flags: [], appCss: true, why: 'the app.css declaration that DEFINES the token' },
	{ source: '\t--gradient-primary: linear-gradient(135deg, #2C5F6E 0%, #F97316 100%);', flags: [], appCss: true, why: 'a declaration whose value is a gradient' },
	{ source: '\tcolor: #EF4444;', flags: ['EF4444'], appCss: true, why: 'a RULE in app.css is not a declaration and is still scanned' },
];

test('the banned-hue matcher flags paint and spares app.css declarations', () => {
	for (const { source, flags, appCss, why } of MATCHER_FIXTURES) {
		assert.deepEqual(
			bannedHexesOn(source, appCss),
			flags,
			`${why}: ${JSON.stringify(source)}`,
		);
	}
});

test('comment masking hides a documented hex but not the rule beneath it', () => {
	const masked = maskComments(
		[
			'/* #EF4444 was 3.763:1 on the card. */',
			'\tcolor: var(--color-danger-text);',
			'<!-- #22c55e -->',
			'\t// #d1fae5',
			'\tbackground: #fef3c7;',
			"\tsrc: url('https://x.test//a#FACC15');",
		].join('\n'),
	);
	assert.deepEqual(
		masked.split('\n').flatMap((l) => bannedHexesOn(l)),
		['FEF3C7', 'FACC15'],
		'only the two painting lines survive masking',
	);
	assert.equal(masked.split('\n').length, 6, 'masking must preserve line numbering');
});

test('no status-role hex literal outside the allowlists', () => {
	const violations: string[] = [];
	const seenFiles = new Set<string>();
	for (const path of walkFiles(SRC_ROOT).sort()) {
		const rel = relative(SRC_ROOT, path).split(sep).join('/');
		seenFiles.add(rel);
		const allowed = DATA_PALETTES[rel] ?? {};
		const source = maskComments(readFileSync(path, 'utf-8'));
		const counts: Record<string, number> = {};
		const lines: Record<string, number[]> = {};
		source.split('\n').forEach((line, i) => {
			for (const hex of bannedHexesOn(line, rel === 'app.css')) {
				counts[hex] = (counts[hex] ?? 0) + 1;
				(lines[hex] ??= []).push(i + 1);
			}
		});
		for (const [hex, count] of Object.entries(counts)) {
			const expected = allowed[hex] ?? 0;
			if (count !== expected) {
				violations.push(
					`${rel}: #${hex} x${count} (allowed ${expected}) at line${
						lines[hex].length > 1 ? 's' : ''
					} ${lines[hex].join(', ')}`,
				);
			}
		}
		for (const [hex, count] of Object.entries(allowed)) {
			if (!(hex in counts)) {
				violations.push(
					`${rel}: the allowlist expects #${hex} x${count} but the file paints none — ` +
						`palette migrated? Remove the entry.`,
				);
			}
		}
	}
	for (const rel of Object.keys(DATA_PALETTES)) {
		assert.ok(
			seenFiles.has(rel),
			`${rel} is allowlisted but was not scanned — if it moved, move its entry with it so the exemption stays scoped.`,
		);
	}
	assert.equal(
		violations.length,
		0,
		`Status-role colours must come from the app.css tokens ` +
			`(--color-success/-warning/-danger + their -text / -light / -strong pairs, ` +
			`--color-crown / --color-on-crown). A literal opts out of the per-theme AA ` +
			`guarantee contrast_guard.test.ts holds those tokens to. Violations:\n` +
			violations.join('\n'),
	);
});

// § 506 kept `var(--declared-token, #hex)` legal, and for the case it named
// that is right: a fallback is the documented default for a component custom
// property a parent sets per instance (`style:--x={...}`). That rationale does
// not survive the token being GLOBAL. Nothing sets --color-primary per
// instance, so the fallback can never apply, and 20 such fallbacks were each
// frozen at a value the token had long since moved off — `#4f46e5` / `#3b82f6`
// / `#2563eb` for a primary that is now teal, `#e5e7eb` for a cream border,
// `#374151` for near-black text. Dead code that reads as the colour at the
// call site is worse than no comment: the next editor believes the blue.
//
// The line, then, is WHERE the token is declared: a fallback on a token the
// same file declares is a per-instance default and stays legal; a fallback on
// an app.css theme token is dead and is deleted. Scoped to a HEX fallback of
// any digit length, because a frozen COLOUR is what this item is about — the
// remaining non-colour fallbacks on global tokens (spacing, radii, shadows,
// z-index) and the nested `var(--a, var(--b))` chains are a separate class
// this rule does not claim to cover.
const GLOBAL_COLOUR_FALLBACK = /var\(\s*--([a-zA-Z0-9-]+)\s*,\s*#[0-9a-fA-F]{3,8}\s*\)/g;

test('no hardcoded-colour var() fallback on a global app.css theme token', () => {
	const appCss = readFileSync(join(SRC_ROOT, 'app.css'), 'utf-8');
	const globalTokens = new Set(
		[...appCss.matchAll(/^\s*--([a-zA-Z0-9-]+)\s*:/gm)].map((m) => m[1]),
	);
	const offenders: string[] = [];
	for (const path of walkFiles(SRC_ROOT).sort()) {
		const rel = relative(SRC_ROOT, path).split(sep).join('/');
		if (rel === 'app.css') continue;
		const source = readFileSync(path, 'utf-8');
		const localTokens = new Set([
			...[...source.matchAll(/--([a-zA-Z0-9-]+)\s*[:=]/g)].map((m) => m[1]),
			...[...source.matchAll(/style:--([a-zA-Z0-9-]+)/g)].map((m) => m[1]),
		]);
		maskComments(source)
			.split('\n')
			.forEach((line, i) => {
				for (const m of line.matchAll(GLOBAL_COLOUR_FALLBACK)) {
					const name = m[1];
					if (globalTokens.has(name) && !localTokens.has(name)) {
						offenders.push(`${rel}:${i + 1}  ${m[0]}`);
					}
				}
			});
	}
	assert.equal(
		offenders.length,
		0,
		`A hardcoded-colour var() fallback on a token app.css declares globally is ` +
			`dead code — the ` +
			`token always resolves, so the fallback never paints, and it drifts from ` +
			`the token silently. Drop the fallback. (A fallback on a token the SAME ` +
			`file declares is a per-instance default and stays legal.)\n` +
			offenders.join('\n'),
	);
});

// Both directions for that rule, since it turns entirely on which set the
// token name lands in.
test('the global-colour-fallback scan spares a per-instance default', () => {
	const globals = new Set(['color-primary', 'space-md']);
	const check = (line: string, locals: Set<string> = new Set()): string[] =>
		[...line.matchAll(GLOBAL_COLOUR_FALLBACK)]
			.filter((m) => globals.has(m[1]) && !locals.has(m[1]))
			.map((m) => m[1]);
	assert.deepEqual(check('color: var(--color-primary, #4f46e5);'), ['color-primary'], 'a 6-digit hex fallback');
	assert.deepEqual(check('fill: var(--color-primary, #999);'), ['color-primary'], 'a 3-digit hex fallback');
	assert.deepEqual(check('color: var(--color-primary, #4f46e580);'), ['color-primary'], 'an 8-digit hex fallback');
	assert.deepEqual(check('background: color-mix(in srgb, var(--color-primary, #d33) 22%, transparent);'), ['color-primary'], 'nested in a CSS function');
	assert.deepEqual(check('padding: var(--space-md, 1rem);'), [], 'a non-colour fallback is a separate class');
	assert.deepEqual(check('color: var(--color-primary, blue);'), [], 'a keyword fallback is not a hex literal');
	assert.deepEqual(check('width: var(--bar-w, #fff);'), [], 'a token app.css does not declare');
	assert.deepEqual(check('color: var(--color-primary);'), [], 'no fallback at all');
	assert.deepEqual(
		check('color: var(--color-primary, #4f46e5);', new Set(['color-primary'])),
		[],
		'the same file declares it, so the fallback is a per-instance default',
	);
});

// The one non-status literal this guard pins, because it is the same defect
// one role over and § 506 minted the token for it without reaching its most
// important call site: the shared `.btn-primary` rule paired a frozen white
// with a fill that flips to a light coral in dark, so the app's primary button
// drew 2.081:1 label text in one of two themes (9.120:1 on the token).
test('app.css pairs a --color-primary fill with --color-on-primary, not a literal', () => {
	const css = readFileSync(join(SRC_ROOT, 'app.css'), 'utf-8');
	const rule = css.match(/\.btn-primary\s*\{[^}]*\}/);
	assert.ok(rule, 'app.css is missing the .btn-primary rule');
	assert.match(
		rule![0],
		/color:\s*var\(--color-on-primary\)/,
		'.btn-primary fills with --color-primary, which is a dark teal in light and a ' +
			'light coral in dark; its label must take --color-on-primary rather than a ' +
			`frozen white. Rule was:\n${rule![0]}`,
	);
});

// ---------------------------------------------------------------------------
// The complete register.
//
// Everything above bans 39 NAMED status hues. § 511 was explicit that this
// leaves a hole and logged its size: 172 literals across 29 files carrying
// hues outside the status vocabulary, exempt by never having been in scope.
// A named-hue ban cannot close that — the next frozen fill just picks a
// fortieth hue — and it forced the second register § 511 declined to build,
// when it considered a "no hex in a border" rule and rejected it as a
// 12-entry allowlist duplicating this one.
//
// So the ban is inverted here: EVERY six-digit literal outside app.css's
// declaration lines must appear below with an exact count and a role from a
// closed vocabulary. That answers the border question by making it moot —
// the register is keyed on the file and the hue, never on the CSS property,
// so a border literal is an entry like any other and there is one register,
// not two. It also removes the hue list's blind spot: a new literal fails
// wherever it lands and whatever it paints.
//
// A role is not an excuse on its own. Where a contrast bar applies, the
// entry's comment carries the measured figure and names the ground it was
// measured against, because § 503's trap is measuring on a convenient
// background and § 519 found two of § 511's own figure sets had moved.
//
// The roles, and what each claims:
//  * 'cartographic'  drawn on the basemap. Graded against the real basemap
//                    samples by basemap_contrast.test.ts, not exempted. A
//                    pin FILL qualifies only when a basemap-keyed ring
//                    carries its 3:1 — the fill is then identity data.
//  * 'brand-mark'    a third party's logo geometry. Fixed by them, not by
//                    us; the mark's own hues are not ours to re-tone. What
//                    is still ours is whatever we draw ON it.
//  * 'brand-hue'     a third party's colour reused as OUR paint. This is
//                    NOT the same exemption: nothing about Strava's orange
//                    requires it to be our label ink, so these owe their
//                    bar like any other paint.
//  * 'data'          the colour IS the datum — tier metals, medal metals,
//                    chart series, workout-kind tints (§ 480's line).
//  * 'fixed-canvas'  a surface that follows no device theme: the @media
//                    print sheet, a rasterised share card, a fixed scrim.
//                    Exempt from THEMING, never from contrast.
//  * 'gradient-stop' a stop of a decorative ramp. Anything drawn over it is
//                    measured by gradient_foreground_guard.test.ts.
//  * 'svg-art'       illustration geometry with no text on it.
//  * 'theme-pair'    a literal that IS theme-keyed, declared once per theme
//                    as a local custom property. Wants a token; the entry
//                    records the debt.
type LiteralRole =
	| 'cartographic'
	| 'brand-mark'
	| 'brand-hue'
	| 'data'
	| 'fixed-canvas'
	| 'gradient-stop'
	| 'svg-art'
	| 'theme-pair';

const REGISTER: Record<string, Record<string, [number, LiteralRole]>> = {
	// Running-shoe / apple loader illustration. No text on it.
	'lib/components/ActivityLoader.svelte': {
		'7C5A3A': [1, 'svg-art'], '4FB477': [1, 'svg-art'],
		FF6B5B: [1, 'svg-art'], FF8C7E: [1, 'svg-art'],
	},
	// Badge tier metals: bronze / silver / gold / platinum, a four-rung
	// ladder where the rung IS the datum.
	'lib/components/BadgeGrid.svelte': {
		B08D57: [1, 'data'], '9AA3AD': [1, 'data'], D4AF37: [1, 'data'], '7FD3E0': [1, 'data'],
	},
	'lib/components/SocialFeed.svelte': {
		B08D57: [1, 'data'], '9AA3AD': [1, 'data'], D4AF37: [1, 'data'], '7FD3E0': [1, 'data'],
	},
	'routes/share/badge/[id]/+page.svelte': {
		B08D57: [1, 'data'], '9AA3AD': [1, 'data'], D4AF37: [1, 'data'], '7FD3E0': [1, 'data'],
	},
	// Medal-rank pills. Each is an OPAQUE fill carrying the meaning, so its
	// ink is fixed with it (§ 495): gold ink 9.381 / 5.612:1 across its two
	// stops, silver 12.735 / 8.223, bronze 8.301 / 4.822 — measured on the
	// stops themselves, which is where the ink lands.
	'lib/components/ChallengeLeaderboard.svelte': {
		'3A2E0A': [1, 'data'], F6D671: [1, 'data'], D4A017: [1, 'data'],
		E4E7EB: [1, 'data'], B4BCC4: [1, 'data'], E6B27E: [1, 'data'], C08043: [1, 'data'],
	},
	// The other medal pair, on the segment-effort list. Silver ink reads
	// 6.161:1 on its own fill, bronze's white 5.022:1; gold alone is
	// theme-aware through --color-crown.
	'lib/components/RunSegmentEfforts.svelte': {
		'94A3B8': [1, 'data'], '1F2328': [1, 'data'], B45309: [1, 'data'],
	},
	// Four per-stat-card accent bars, 2px and text-free: chart series
	// separated by hue.
	'lib/components/PeriodSummary.svelte': {
		'4F46E5': [1, 'gradient-stop'], '7C3AED': [1, 'gradient-stop'],
		'10B981': [1, 'gradient-stop'], '06B6D4': [1, 'gradient-stop'],
		F97316: [1, 'gradient-stop'], F59E0B: [1, 'gradient-stop'],
		EC4899: [1, 'gradient-stop'], EF4444: [1, 'gradient-stop'],
	},
	// Privacy-zone centre marker, fill and outline. 4.208:1 on the light
	// land sample, 3.560 on the dark, 3.011 over light-basemap water — the
	// thinnest margin in the register, and the reason the water sample is
	// asserted at all.
	'lib/components/PrivacyZonePicker.svelte': { DC2626: [3, 'cartographic'] },
	// Start / finish caps on the mini track preview and the roadbook course
	// schedule. Painted on a track thumbnail, not on a live basemap, so
	// these are the twin of mobile's own two allowlist entries.
	'lib/components/TrackPreview.svelte': { '22C55E': [1, 'cartographic'], EF4444: [1, 'cartographic'] },
	'routes/routes/[id]/roadbook/+page.svelte': { '22C55E': [1, 'cartographic'], EF4444: [1, 'cartographic'] },
	// Route + club pin FILLS, whose basemap-keyed ring carries the 3:1
	// (17.191:1 on dark ground, 13.930 on light). MapLibre paint cannot
	// consume a CSS custom property, so a literal here is structural. The
	// violet pair is the kept-route accent, declared once per theme.
	'lib/components/RouteHeatmap.svelte': {
		'7FB3C2': [1, 'cartographic'], F2A07B: [2, 'cartographic'],
		'6D28D9': [1, 'theme-pair'], A78BFA: [2, 'theme-pair'],
	},
	// Marketing hero + closing-CTA ramps and the on-hero button. Every ink
	// over them is measured by gradient_foreground_guard.test.ts.
	'routes/+page.svelte': {
		'0F172A': [1, 'gradient-stop'], '1E1B4B': [2, 'gradient-stop'],
		'4F46E5': [3, 'gradient-stop'], '7C3AED': [1, 'gradient-stop'],
		FFFFFF: [4, 'fixed-canvas'], F0EFFF: [1, 'fixed-canvas'],
	},
	// Header over that same hero: white hover ink, 5.699:1 on the ramp's
	// palest stop.
	'lib/components/PublicHeader.svelte': { FFFFFF: [2, 'fixed-canvas'] },
	// Sign-in brand pane (a fixed canvas; ramp + white copy measured per
	// veil by gradient_foreground_guard.test.ts), the Google "G" mark, and
	// Apple's required black button plus its hairline.
	'routes/login/+page.svelte': {
		'2A4E5A': [1, 'gradient-stop'], '3A5A66': [1, 'gradient-stop'], '7E4527': [1, 'gradient-stop'],
		FFFFFF: [2, 'fixed-canvas'],
		'4285F4': [1, 'brand-mark'], '34A853': [1, 'brand-mark'],
		FBBC05: [1, 'brand-mark'], EA4335: [1, 'brand-mark'],
		'1A1A1A': [1, 'brand-mark'], '334155': [1, 'brand-mark'],
	},
	// The same two marks on the linked-accounts rows.
	'routes/settings/account/+page.svelte': {
		'4285F4': [2, 'brand-mark'], '34A853': [2, 'brand-mark'],
		FBBC05: [2, 'brand-mark'], EA4335: [2, 'brand-mark'],
		'1A1A1A': [1, 'brand-mark'],
	},
	// The 1080x1080 share card: rasterised to a PNG, so no device theme
	// reaches it. Ramp + ink measured by gradient_foreground_guard; the
	// match pill is a fixed near-black scrim over the basemap whose ink
	// (8.022:1) and hairline (4.111:1) are fixed with it.
	'routes/runs/[id]/+page.svelte': {
		'9B4A24': [1, 'gradient-stop'], '6E4F94': [1, 'gradient-stop'], '5B4478': [1, 'gradient-stop'],
		FFFFFF: [1, 'fixed-canvas'], F7F3EC: [1, 'fixed-canvas'], B5ADC3: [1, 'fixed-canvas'],
	},
	// The @media print sheet: white paper, where a theme token resolves to
	// the SCREEN theme and prints dark-on-dark. The amber was deepened from
	// #b26a00 (4.238:1 on paper) to #9E5C00 (5.270 on white, 5.031 on the
	// mint price card) — a fixed canvas is exempt from theming, not from
	// contrast.
	'routes/compare/+page.svelte': {
		F6FBF6: [1, 'fixed-canvas'], '1B5E20': [1, 'fixed-canvas'], '9E5C00': [1, 'fixed-canvas'],
	},
	// Gold star over a FIXED 0.65-black scrim on a route thumbnail.
	// --color-crown is the deliberately dark light-mode gold and would read
	// 1.123:1 here against 4.196 for this hue — the naive swap is 3.7x
	// worse, § 503 pointing the other way for once.
	'routes/routes/+page.svelte': { FBBF24: [1, 'fixed-canvas'] },
	// Race-day brand hero: a fixed canvas, its verdict inks on the same
	// white pill (4.862:1 worst across the ramp), and an active toggle whose
	// #8F2F24 is deliberately NOT --color-danger-strong's value.
	'lib/components/RaceDayPanel.svelte': {
		'047857': [2, 'fixed-canvas'], '8A4A00': [2, 'fixed-canvas'],
		'991B1B': [2, 'fixed-canvas'], '8F2F24': [1, 'fixed-canvas'],
	},
};

// Every literal the register knows is still a measured FAILURE, with the
// worst figure and the ground it was measured against. Recorded rather than
// silently exempted: a register whose whole point is completeness has to be
// able to say "known bad, not yet fixed" — otherwise the honest thing gets
// dropped from the register to keep the suite green, which is how § 511's
// hole opened in the first place. Pinned as an exact set, so closing one
// forces its removal and a new failure cannot join without an edit here.
//
// EMPTY as of § 529: all five entries § 526 recorded were closed together,
// because all five were one defect — an identity or brand accent frozen as a
// hex and then asked to be BOTH the tint and the ink on it. Each is now a
// `--section-<x>` / `--provider-<x>` fill with a theme-keyed `-ink` rung
// beside it (app.css), and every call site is measured composited in
// contrast_guard.test.ts. § 526's own figures were leads, not facts: three of
// the five were measured against the wrong ground or the wrong floor. The
// provider glyphs sit on the CARD, not on --color-bg-tertiary (the per-provider
// rule replaces that background outright), which moves Strava from 2.375 to
// 2.921:1 and clears four of the six § 526 failed; the VerifiedBadge ribbon is
// aria-hidden SVG geometry, so it owes 1.4.11's 3:1 and not AA text — it was
// never failing at 3.127. Two failures § 526 missed showed up instead: the
// dashboard's `.gym-footer-cta` is real TEXT in #4E7C5E and owed 4.5:1 at
// 4.346 light / 3.949 dark, and ultrasignup + chronotrack fail in DARK.
const OPEN_DEBTS: Record<string, string> = {};

// The figure format the entries above must carry, pinned in both directions so
// the rule survives the set being empty — § 511's point about a floor read out
// of the tree: a matcher that matches nothing must not pass for that reason.
const DEBT_FIGURE_FIXTURES: Array<[ok: boolean, figure: string]> = [
	[true, '2.375:1 (#FC4C02 glyph on its own 12% disc over #EBE5D8)'],
	[true, '10.291:1 (white on the full accent)'],
	// A figure with no ground is exactly § 503's trap: a convenient background.
	[false, '2.375:1'],
	// Two decimals is a rounded claim, not a measurement.
	[false, '2.37:1 (#FC4C02 on #EBE5D8)'],
	// A ground with no figure records the worry and not the number.
	[false, 'fails on #EBE5D8'],
];

const ANY_SIX_HEX = /#([0-9a-fA-F]{6})(?![0-9a-fA-F])/g;

export function literalsOn(line: string, isAppCss = false): string[] {
	if (isAppCss && TOKEN_DECLARATION.test(line.trim())) return [];
	return [...line.matchAll(ANY_SIX_HEX)].map((m) => m[1].toUpperCase());
}

test('every six-digit literal is in the register at its exact count', () => {
	const violations: string[] = [];
	const seen = new Set<string>();
	for (const path of walkFiles(SRC_ROOT).sort()) {
		const rel = relative(SRC_ROOT, path).split(sep).join('/');
		seen.add(rel);
		const allowed = REGISTER[rel] ?? {};
		const counts: Record<string, number> = {};
		const lines: Record<string, number[]> = {};
		maskComments(readFileSync(path, 'utf-8'))
			.split('\n')
			.forEach((line, i) => {
				for (const hex of literalsOn(line, rel === 'app.css')) {
					counts[hex] = (counts[hex] ?? 0) + 1;
					(lines[hex] ??= []).push(i + 1);
				}
			});
		for (const [hex, count] of Object.entries(counts)) {
			const expected = allowed[hex]?.[0] ?? 0;
			if (count !== expected) {
				violations.push(
					`${rel}: #${hex} x${count} (registered ${expected}) at line${
						lines[hex].length > 1 ? 's' : ''
					} ${lines[hex].join(', ')}`,
				);
			}
		}
		for (const [hex, [count]] of Object.entries(allowed)) {
			if (!(hex in counts)) {
				violations.push(
					`${rel}: the register expects #${hex} x${count} but the file paints ` +
						`none — swept? Remove the entry.`,
				);
			}
		}
	}
	for (const rel of Object.keys(REGISTER)) {
		assert.ok(seen.has(rel), `${rel} is registered but was not scanned`);
	}
	assert.equal(
		violations.length,
		0,
		`Every six-digit hex literal in apps/web/src must be in REGISTER with a ` +
			`role and an exact count — a role is a claim about WHY the value is ` +
			`frozen, and where a contrast bar applies the entry carries the number ` +
			`and the ground it was measured against. Prefer routing the colour onto ` +
			`a token; only add an entry when the value genuinely cannot follow the ` +
			`theme. Violations:\n${violations.join('\n')}`,
	);
});

test('the open-debt set is exactly what is recorded', () => {
	for (const rel of Object.keys(OPEN_DEBTS)) {
		assert.ok(
			rel in REGISTER,
			`${rel} carries an open debt but is not in the register`,
		);
	}
	// Frozen so closing one is a deliberate edit here, and so a future round
	// cannot quietly reclassify a new failure as an old one. Empty since § 529
	// closed all five; the fixtures below keep the format rule alive regardless.
	assert.deepEqual(Object.keys(OPEN_DEBTS).sort(), []);
	const FIGURE = /^\d+\.\d{3}:1 \(.+\)$/;
	for (const [rel, figure] of Object.entries(OPEN_DEBTS)) {
		assert.match(
			figure,
			FIGURE,
			`${rel}: an open debt must carry its measured figure AND the ground ` +
				`it was measured against — § 503's trap is a convenient background`,
		);
	}
	for (const [ok, figure] of DEBT_FIGURE_FIXTURES) {
		assert.equal(
			FIGURE.test(figure),
			ok,
			`the open-debt figure format ${ok ? 'must accept' : 'must reject'} ${figure}`,
		);
	}
	// Every file § 526 recorded a debt against carries no six-digit literal at
	// all now, so the closure cannot be undone by re-freezing one of the hues
	// under a different name: the register scan above would fail on it.
	for (const rel of [
		'lib/components/VerifiedBadge.svelte',
		'routes/+layout.svelte',
		'routes/dashboard/+page.svelte',
		'routes/history/+page.svelte',
		'routes/settings/integrations/+page.svelte',
	]) {
		assert.ok(
			!(rel in REGISTER),
			`${rel} was closed in § 529 — a new entry for it needs a new open debt`,
		);
	}
});

test('the register is keyed on the hue, never on the CSS property', () => {
	// § 511 considered a "no hex in a border" rule and declined it because it
	// would need a 12-entry allowlist duplicating the one above. This is the
	// decision it deferred: because the register keys on (file, hue) and the
	// scan reads every line whatever it declares, a border literal is an
	// entry like any other. Both of the surviving border literals are
	// registered, so there is one register and not two.
	assert.equal(REGISTER['routes/runs/[id]/+page.svelte']?.B5ADC3?.[0], 1);
	assert.equal(REGISTER['routes/login/+page.svelte']?.['334155']?.[0], 1);
	// And the matcher itself has no property in it.
	assert.deepEqual(literalsOn('\tborder: 1px solid #B5ADC3;'), ['B5ADC3']);
	assert.deepEqual(literalsOn('\tcolor: #B5ADC3;'), ['B5ADC3']);
});

test('the universal matcher catches a hue the status list never named', () => {
	// The hole this closes. `#1d4ed8` is not on BANNED_HEXES and never was.
	assert.deepEqual(bannedHexesOn('\tcolor: #1d4ed8;'), []);
	assert.deepEqual(literalsOn('\tcolor: #1d4ed8;'), ['1D4ED8']);
	// app.css declarations stay the vocabulary's one home, in both rules.
	assert.deepEqual(literalsOn('\t--color-primary: #2C5F6E;', true), []);
	assert.deepEqual(literalsOn('\tcolor: #2C5F6E;', true), ['2C5F6E']);
	// 3-digit shorthands and rgb() spellings remain out of scope, declared
	// rather than assumed.
	assert.deepEqual(literalsOn('\tcolor: #d33;'), []);
	assert.deepEqual(literalsOn('\tcolor: rgb(200, 40, 40);'), []);
});
