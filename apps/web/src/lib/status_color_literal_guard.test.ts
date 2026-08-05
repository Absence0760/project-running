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
// Scope declared, so a future reader does not mistake silence for coverage:
// the literal ban covers the 39 named six-digit status hues below (with an
// optional 8-digit alpha suffix), the same bounded shape as the mobile twin —
// it does not police 3-digit shorthands, rgb()/hsl() spellings, or hues
// outside the list. The separate dead-fallback rule at the foot of this file
// is NOT hue-scoped: it bans a hex fallback of any length on any global
// app.css token, because there the defect is the frozen value, not the hue.

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
	// Workout-kind tint palette (easy / tempo / interval / marathon_pace /
	// long). Only the marathon_pace rung collides with --color-warning.
	'lib/components/CurrentWeekStrip.svelte': { E6A96B: 1 },
	'lib/components/PlanCalendar.svelte': { E6A96B: 1 },
	'routes/plans/[id]/+page.svelte': { E6A96B: 1 },
	'routes/plans/[id]/workouts/[wid]/+page.svelte': { E6A96B: 1 },
	// Per-stat-card accent gradients: four chart series, separated by hue.
	'lib/components/PeriodSummary.svelte': { '10B981': 1, F97316: 1, F59E0B: 1, EF4444: 1 },
	// Cartographic: privacy-zone marker, its fill and its outline. Drawn on
	// the basemap, not on a theme surface.
	'lib/components/PrivacyZonePicker.svelte': { DC2626: 3 },
	// Cartographic: waypoint colouring (implicated / start) plus the
	// generate-by-distance start + end picker pins.
	'lib/components/RouteBuilder.svelte': { EF4444: 1, '22C55E': 1, '16A34A': 1, DC2626: 1 },
	// Cartographic: the featured-cluster gold halo on the heatmap pins.
	'lib/components/RouteHeatmap.svelte': { FACC15: 1 },
	// Cartographic: the segment-effort overlay line + its two marker classes
	// (animated replay dot, segment pin) and the start / finish map markers.
	// The overlay accent is the web twin of mobile's live_run_map.dart entry;
	// #F59E0B computes to 1.87:1 against a light basemap, so its contrast is
	// carried by the white ring around it, not by the hue.
	'lib/components/RunMap.svelte': { F59E0B: 5, '22C55E': 1, EF4444: 1 },
	// Painted start / finish caps on the mini track preview — the exact twin
	// of mobile's track_preview.dart allowlist entry.
	'lib/components/TrackPreview.svelte': { '22C55E': 1, EF4444: 1 },
	// Course start / finish checkpoint hues, twin of mobile's
	// roadbook_screen.dart entry.
	'routes/routes/[id]/roadbook/+page.svelte': { '22C55E': 1, EF4444: 1 },
	// Cartographic: the coarse (privacy-clipped) live position marker and its
	// outline — the web twin of mobile's coarse-position ring.
	'routes/live/event/[id]/[instance]/+page.svelte': { E6A96B: 2 },
	// Fixed brand hero: the panel paints its own orange -> red gradient and
	// every colour inside is calibrated to that canvas, not to the theme.
	// Recorded rather than swept, with the numbers, because the gaps here are
	// contrast-on-a-fixed-canvas and not theme drift: the panel's own
	// `color: white` is 2.803:1 on the orange stop, the three .feasibility
	// inks are 2.295-3.572:1 on the gradient, and .toggle-btn.active is
	// 3.763:1 on its white pill. Fixing those is a redesign of the hero.
	'lib/components/RaceDayPanel.svelte': {
		F97316: 1,
		EF4444: 2,
		'047857': 1,
		B45309: 1,
		B91C1C: 1,
		ECFDF5: 1,
		FEF3C7: 1,
		FEE2E2: 1,
	},
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
