// Source-scan guard for the web half of § 482's micro-label floor.
//
// Mobile pins 11 px as the smallest type any surface may use — `labelSmall` on
// `AppTheme.textTheme`, enumerated by `packages/ui_kit/test/type_scale_test.dart`
// and enforced against hand-written literals by
// `apps/mobile_android/test/font_size_literal_guard_test.dart`. Web had no
// equivalent, and the drift showed: 45 `font-size` declarations sat under it, the
// narrowest at 8 px, and `PlanCalendar`'s `.kind-pill` — on the one plan surface
// every phone user opens — dropped from 0.65rem to 0.55rem (8.8 px) under 40 rem.
// § 525 closed that one and pinned the other 42; the sweep since leaves 9.
//
// This is a FLOOR guard, not mobile's literal guard, and the difference is not
// laziness. Mobile's rule is "name the step", which is enforceable because the
// scale is closed: seven steps on one `textTheme`, so a literal is either a step
// spelled by hand or a value between two steps. Web's CSS carries ~1860 numeric
// `font-size` declarations against three named size tokens, so banning literals
// would need an allowlist longer than the codebase and would assert nothing. What
// transfers is the conformance content of § 482 — the 11 px minimum — and a floor
// says exactly that.
//
// The floor is read out of `app_theme.dart` rather than written here, so the two
// platforms cannot drift the way the line token did before § 518 pinned it.
//
// When this test fails: raise the declaration to at least the floor. Prefer
// `var(--font-size-section-label)` (0.7rem = 11.2 px), the micro-label token —
// and prefer the token over its value, which is a distinction § 525 ran
// together when it called this "the micro-label token 80 declarations already
// use". Recomputed: 81 declarations spelled the literal `0.7rem`, and 21 used
// the token. Both land on 11.2 px today, but only the token moves if the floor
// does, and per § 522 a hand-spelled value sitting exactly ON a floor is the
// fragile kind. The 81 literals are out of this guard's reach by construction —
// they are at the floor, not under it — and are recorded as remaining work.
//
// If a narrow viewport no longer fits the text, tighten the box or let the text
// reflow — SC 1.4.4 and 1.4.10 both ask for reflow rather than a smaller size.
// Never re-shrink it in a media query: that is the defect § 525 found on
// `PlanCalendar` and this round closed on both week ribbons, and a source scan
// cannot see which of a base rule and its override actually paints. The
// resolved-cascade half lives in Playwright — `tests-e2e/plans/calendar.spec.ts`
// and `tests-e2e/cross-cutting/week-strip-type-floor.spec.ts`.

import { test } from 'node:test';
import { strict as assert } from 'node:assert';
import { readFileSync, readdirSync, rmSync, writeFileSync } from 'node:fs';
import { resolve, dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SRC_ROOT = resolve(__dirname, '..');
const SKIP_DIRS = new Set(['node_modules', '.svelte-kit', 'build', 'dist']);

// Nothing in the tree overrides the root font-size, so 1rem is the browser
// default 16 px and a rem value converts by multiplication. A guard that assumed
// otherwise would be wrong for every reader who scales their default up — but so
// would the CSS, which is why the floor is stated in px and the conversion is
// pinned by this constant rather than sprinkled.
const ROOT_FONT_PX = 16;

// The lookbehind is load-bearing: `--font-size-section-label: 0.7rem` and
// `--font-size-page-title: 1.5rem` are custom-property DECLARATIONS, and without
// it the scan would read the token that defines the floor as a 0.7 px violation
// of it. `\b` on the unit keeps `0.55remish` out.
const FONT_SIZE_DECLARATION = /(?<![\w-])font-size:\s*([\d.]+)(rem|px|em)\b/g;

function mobileMicroLabelFloorPx(): number {
	const dart = readFileSync(
		resolve(__dirname, '../../../../packages/ui_kit/lib/src/theme/app_theme.dart'),
		'utf-8',
	);
	const sizes = [...dart.matchAll(/labelSmall:\s*TextStyle\(\s*fontSize:\s*([\d.]+)/g)].map((m) =>
		parseFloat(m[1]),
	);
	assert.ok(sizes.length >= 2, 'app_theme.dart declares labelSmall in fewer than two brightnesses');
	assert.equal(
		new Set(sizes).size,
		1,
		`labelSmall differs between brightnesses in app_theme.dart (${sizes.join(', ')}) — the floor is one number.`,
	);
	return sizes[0];
}

const FLOOR_PX = mobileMicroLabelFloorPx();

type Declaration = { file: string; line: number; raw: string; px: number };

function scanFontSizes(): { sized: Declaration[]; relative: string[] } {
	const sized: Declaration[] = [];
	const relativeUnits: string[] = [];
	(function walk(dir: string): void {
		for (const entry of readdirSync(dir, { withFileTypes: true })) {
			const path = join(dir, entry.name);
			if (entry.isDirectory()) {
				if (!SKIP_DIRS.has(entry.name)) walk(path);
				continue;
			}
			if (!/\.(svelte|css)$/.test(entry.name)) continue;
			readFileSync(path, 'utf-8')
				.split('\n')
				.forEach((line, i) => {
					for (const m of line.matchAll(FONT_SIZE_DECLARATION)) {
						const value = parseFloat(m[1]);
						const where = `${relative(SRC_ROOT, path)}:${i + 1}  ${m[0]}`;
						if (m[2] === 'em') {
							relativeUnits.push(where);
							continue;
						}
						sized.push({
							file: relative(SRC_ROOT, path),
							line: i + 1,
							raw: m[0],
							px: m[2] === 'rem' ? value * ROOT_FONT_PX : value,
						});
					}
				});
		}
	})(SRC_ROOT);
	return { sized, relative: relativeUnits };
}

// file -> exact number of `font-size` declarations below the floor.
//
// Two groups, and the split is what the entry means rather than how it is
// checked. The equality pin is the same either way: a NEW sub-floor declaration
// in a listed file still fails, and a file that gets fixed forces its entry out.
//
// Every entry below is a named, justified exemption rather than an unexamined
// literal — which is the state § 525 asked for and did not yet have. What it
// took was reading each site's markup rather than its file: two of § 525's three
// "text inside a graphic" entries were files that also held a plain-debt
// declaration, and `PersonalHeatmap`'s was not a graphic at all (see below). The
// list can only shrink from here.
const BELOW_FLOOR = <Record<string, number>>{
	// --- Text inside a graphic, which is the class mobile's guard exempts too:
	// drawn over basemap tiles or inside an SVG plot, not on a theme surface, so
	// the size is a dimension of the drawing rather than a step on a type scale.
	//
	// `.extreme-text` is SVG text — it paints `fill:` — inside the elevation
	// plot, which scales with its own fixed viewBox.
	'lib/components/ElevationProfile.svelte': 1,
	// Two, and only one is a graphic: `.km-marker` is the 8 px numeral inside a
	// 20 px km pin drawn over basemap tiles (mobile exempts
	// `route_builder_screen.dart` for exactly this). `.shortcuts-hint kbd` is a
	// keyboard-shortcut hint in flowing layout and is plain debt.
	'lib/components/RouteBuilder.svelte': 2,

	// --- Micro-labels that are simply under the floor. Every one of these is
	// owed a fix; they are pinned so the count can only shrink, not so they are
	// blessed.
	//
	// `.bar-label` (base + a 0.6rem narrow-viewport shrink, the same pattern the
	// two week ribbons and `PlanCalendar` have now lost) and `.source-badge` —
	// the last member of its family still under the floor, the other three being
	// `PeriodSummary` at 0.7rem, `RunShareView` and `/runs`.
	'routes/dashboard/+page.svelte': 3,
	// `.collapse-toggle-label`, the sidebar section-label toggle.
	'routes/+layout.svelte': 1,
	// `.segment-eyebrow` and `.segment-stat-label`.
	'routes/runs/[id]/+page.svelte': 2,
};

test(`no font-size declaration falls below the ${FLOOR_PX} px micro-label floor`, () => {
	const { sized } = scanFontSizes();
	const under = sized.filter((d) => d.px < FLOOR_PX);
	const byFile = new Map<string, Declaration[]>();
	for (const d of under) byFile.set(d.file, [...(byFile.get(d.file) ?? []), d]);

	const unlisted = [...byFile.entries()].filter(([file]) => !(file in BELOW_FLOOR));
	assert.equal(
		unlisted.length,
		0,
		`Type below the ${FLOOR_PX} px floor § 482 pins on mobile, in files with no entry:\n` +
			unlisted
				.flatMap(([, ds]) => ds.map((d) => `  ${d.px.toFixed(2)}px  ${d.file}:${d.line}  ${d.raw}`))
				.join('\n'),
	);
	for (const [file, expected] of Object.entries(BELOW_FLOOR)) {
		const found = byFile.get(file) ?? [];
		assert.equal(
			found.length,
			expected,
			`${file} carries ${found.length} sub-floor font-size declaration(s), expected ${expected}. ` +
				`If a size was raised, drop the entry (or lower the count); if one was ADDED, raise it ` +
				`to at least ${FLOOR_PX} px instead:\n` +
				found.map((d) => `  ${d.px.toFixed(2)}px  ${d.file}:${d.line}  ${d.raw}`).join('\n'),
		);
	}
});

// An `em` font-size compounds with whatever the ancestor resolved to, so no
// static scan can price it and the floor above cannot see it. Count-pinned so a
// new micro-label cannot slip under the floor by switching unit.
//
// § 525 left the six at that and called them unmeasurable. They are not — only
// un-measured-statically, and each is now classified rather than merely counted:
//
//   - Three are Material Symbols glyph sizing (`ChallengeProgressBar` 1.05em,
//     `RunGearChips` 0.95em, `settings/gear` 1.1em). An icon's `font-size` is the
//     glyph's box, so this is the `em` analogue of the text-inside-a-graphic
//     exemption above. Deliberately NOT held to the floor: a legibility minimum
//     on an icon asserts the wrong thing.
//   - Three are real text, and `tests-e2e/cross-cutting/type-floor-em-units.spec.ts`
//     reads each with `getComputedStyle` — the same resolved-cascade move § 525
//     made for the media-query override a source scan cannot see. Measured:
//     `cookie-notice` `.manage-consent-hint` 0.9em -> 14.4 px, and CoachChat's
//     inline `code` and `pre code` 0.85em -> 13.6 px off a `.md` that resolves
//     to 16 px.
//
// The two code rules do NOT compound, and that is the one number here worth
// keeping: both set 0.85em on the same element and `.md pre` sets no size, so
// `pre code` is 13.6 px, not 0.85 x 0.85 = 11.56 px. If `pre` ever gains a
// font-size the product lands within 0.6 px of the floor, which is why the
// resolved check exists rather than a comment asserting it is fine.
test('exactly six font-size declarations use the unresolvable em unit', () => {
	const { relative: ems } = scanFontSizes();
	assert.equal(
		ems.length,
		6,
		`${ems.length} \`font-size\` declarations use em, expected 6. An em cannot be checked ` +
			`against the ${FLOOR_PX} px floor — use rem (or the section-label token) for a ` +
			`micro-label:\n${ems.join('\n')}`,
	);
});

// The token every micro-label should reach for. It clears the floor by 0.2 px,
// which is headroom rather than an exact meet — so, unlike a value that lands ON
// a floor (§ 522), it survives a small later adjustment. It is deliberately NOT
// theme- or breakpoint-overridden: a media query that shrank it would move 80
// declarations under the floor at once, which is the bug this round closed on
// `.kind-pill` generalised to the whole tree.
test('the section-label token clears the floor and is declared exactly once', () => {
	const css = readFileSync(resolve(__dirname, '../app.css'), 'utf-8');
	const declarations = [...css.matchAll(/--font-size-section-label:\s*([\d.]+)(rem|px)\s*;/g)];
	assert.equal(
		declarations.length,
		1,
		`--font-size-section-label is declared ${declarations.length} times; one declaration is what ` +
			`makes it a floor rather than a suggestion.`,
	);
	const [, value, unit] = declarations[0];
	const px = unit === 'rem' ? parseFloat(value) * ROOT_FONT_PX : parseFloat(value);
	assert.ok(
		px >= FLOOR_PX,
		`--font-size-section-label is ${px.toFixed(2)}px, under the ${FLOOR_PX}px floor.`,
	);
});

// The scan's own conversion and matcher, both directions. A guard that read
// `--font-size-section-label: 0.7rem` as a 0.7 px declaration, or that missed the
// `font-size:0.55rem` with no space, would pass while measuring nothing.
test('the font-size scan converts units and matches only real declarations', () => {
	const cases: Array<[line: string, expected: Array<[number, string]>]> = [
		['\tfont-size: 0.55rem;', [[8.8, 'rem']]],
		['\tfont-size:0.55rem;', [[8.8, 'rem']]],
		['\tfont-size: 8px;', [[8, 'px']]],
		['\tfont-size: 0.7rem; line-height: 1.1;', [[11.2, 'rem']]],
		['\t--font-size-section-label: 0.7rem;', []],
		['\t--font-size-page-title: 1.5rem;', []],
		['\tfont-size: var(--font-size-section-label);', []],
		['\tfont-size: inherit;', []],
		['\tfont-size: 0.85em;', []],
	];
	for (const [line, expected] of cases) {
		const found = [...line.matchAll(FONT_SIZE_DECLARATION)]
			.filter((m) => m[2] !== 'em')
			.map(
				(m) => [parseFloat(m[1]) * (m[2] === 'rem' ? ROOT_FONT_PX : 1), m[2]] as [number, string],
			);
		assert.deepEqual(found, expected, `the scan mis-reads \`${line.trim()}\``);
	}
});

// A planted violation in a file with no entry, so the walker is proved to reach a
// new file rather than only to re-count the ones already listed. The allowlist's
// equality pin covers the other direction on every run.
test('the floor scan fires on a planted violation in an unlisted file', () => {
	const path = resolve(SRC_ROOT, 'lib/__font_size_floor_probe.css');
	writeFileSync(path, '.probe { font-size: 0.55rem; }\n');
	try {
		const under = scanFontSizes().sized.filter((d) => d.px < FLOOR_PX);
		const hit = under.find((d) => d.file.endsWith('__font_size_floor_probe.css'));
		assert.ok(hit, 'the scan did not reach a newly added CSS file');
		assert.equal(hit!.px, 8.8, 'the scan mis-converted the planted 0.55rem');
		assert.ok(!(hit!.file in BELOW_FLOOR), 'the probe path must have no allowlist entry');
	} finally {
		rmSync(path);
	}
});
