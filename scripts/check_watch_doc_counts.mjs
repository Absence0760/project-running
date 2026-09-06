#!/usr/bin/env node
// Guardrail: a number a custom_watch doc states ABOUT a firmware symbol is the
// symbol's own number, read out of the Rust that declares it.
//
// Why this exists: decisions.md § 793 and § 867. The § 793 doc sweep found five
// of these rotted at once — a GATT characteristic count stale in five files, a
// settings-version range wrong at both ends in two, a `face::Metric` count, three
// `Page`-ring counts and a settings-menu row count. Every one was a transcription
// of a Rust `enum` or `const` that nothing compared. `check_watch_wire_vectors.mjs`
// closed the code-against-code half of the same filing; this closes the
// doc-against-code half.
//
// **The design problem this solves is that the phrasings are prose.** A matcher
// that hunts loosely for "a number near a noun" is a matcher that cannot fail
// honestly — it either drowns in false positives or is narrowed until it reads as
// complete while covering four numbers of thirty. The answer taken here is to
// constrain the prose instead: a count about a firmware symbol is written in one
// of a closed set of PHRASE TEMPLATES this file declares, `{n}` marking the
// number, and any sentence that will not take one of those shapes loses its
// number instead (`privacy.md`'s "every characteristic carries justworks" is the
// model — a sentence that cannot rot, and the stronger claim besides). Prose is
// ours to write, so making the matcher exact costs a word.
//
// Two directions, because one alone is a guard that reads as complete:
//
//   1. **Templates.** Every occurrence of a template's tail preceded by a number
//      must carry the number the symbol resolves to. This is what fails when a
//      symbol grows and a doc does not follow. A template that matches NOTHING is
//      a hard error, not a pass: a dead template is a vacuous check (§ 850).
//   2. **The sweep.** Every occurrence of a count-shaped noun from `SWEEP_NOUNS`
//      in the doc set must be claimed by a template match at the same offset, or
//      be named in `NOT_A_SYMBOL_COUNT` with a written reason. This is what fails
//      when a NEW stale count is written — the case the registry cannot see,
//      because it is not in the registry. An exemption that matches nothing is
//      also a hard error, so the list cannot silently rot either.
//
// **A dated log is out of scope, deliberately.** `docs/custom_watch/tier1_log.md`,
// the chronology in `apps/custom_watch/README.md`, and `decisions.md` itself
// stamp their entries with a date and record what was true when it was written;
// § 793 left their counts alone on exactly that rule and so does this. Scanning
// them would demand that history be rewritten every time a page lands. `DOC_FILES`
// is therefore the closed set of PRESENT-TENSE docs — and because a list of files
// is the one thing a registry cannot police from the inside, it plus `DATED_LOGS`
// must account for `docs/custom_watch/` FILE FOR FILE: a doc dropped in that
// neither list claims fails this guard rather than going unread.
//
// Run: `node scripts/check_watch_doc_counts.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml — the UNGATED
//      doc-registry job, not the `watch-wire-vectors` one this guard is a sibling
//      of. Every job in that block is gated on `needs.changes.outputs.code`, and
//      the `changes` filter calls any `*.md` diff a docs-only diff, so a
//      code-gated job would skip on exactly the edits that rot a doc count and
//      the CI gate counts a skip as a pass (decisions § 869).
// Unit tests: `node --test scripts/check_watch_doc_counts.test.mjs`

import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { stripComments } from './comment_strip.mjs';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.WATCH_DOC_COUNT_ROOT ?? REPO_ROOT;

/**
 * Present-tense docs. A dated log is not one — see the header, and `DATED_LOGS`
 * below, which this list has to reconcile against the directory.
 */
export const DOC_FILES = [
	'docs/custom_watch/README.md',
	'docs/custom_watch/firmware.md',
	'docs/custom_watch/navigation.md',
	'docs/custom_watch/privacy.md',
	'docs/custom_watch/quality_standards.md',
	'docs/custom_watch/roadmap.md',
	'docs/custom_watch/tier2_scope.md',
	'docs/custom_watch/vision.md',
	'docs/custom_watch/prototyping.md',
	'docs/custom_watch/performance_path.md',
	'docs/custom_watch/bom.md',
	'docs/custom_watch/parts.md',
	'docs/custom_watch/competitive_landscape.md',
	'docs/custom_watch/vendor_research.md',
	'apps/custom_watch/CLAUDE.md',
	'apps/custom_watch/local_testing.md',
	'CLAUDE.md',
];

/**
 * The dated logs, excluded on § 793's own rule: they record what was true when
 * written, and scanning them would demand history be rewritten every time a page
 * lands. Named rather than merely absent, so `docs/custom_watch/` reconciles
 * exactly and a NEW doc cannot arrive unread.
 */
export const DATED_LOGS = ['docs/custom_watch/tier1_log.md'];

/** The directory `DOC_FILES` plus `DATED_LOGS` must account for, file for file. */
export const WATCH_DOC_DIR = 'docs/custom_watch';

/**
 * Markdown under `WATCH_DOC_DIR` that neither list claims. A doc added there and
 * not registered is a doc whose counts go unread, which is the one hole a
 * registry of files cannot see from the inside.
 * @param {string[]} entries file names in the directory
 * @returns {string[]}
 */
export function unregisteredDocs(entries) {
	const known = new Set([...DOC_FILES, ...DATED_LOGS]);
	return entries
		.filter((f) => f.endsWith('.md'))
		.map((f) => `${WATCH_DOC_DIR}/${f}`)
		.filter((f) => !known.has(f))
		.sort();
}

const CORE = 'apps/custom_watch/core/src';

/**
 * Number words the docs actually spell out. Kept closed rather than general: a
 * word this table does not hold simply does not match a template, which fails
 * loudly as a template that matched nothing rather than passing quietly.
 * @type {Record<string, number>}
 */
const WORDS = {
	one: 1, two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8,
	nine: 9, ten: 10, eleven: 11, twelve: 12, thirteen: 13, fourteen: 14,
	fifteen: 15, sixteen: 16, seventeen: 17, eighteen: 18, nineteen: 19,
	twenty: 20, thirty: 30, forty: 40, fifty: 50, sixty: 60,
	'twenty-one': 21, 'twenty-five': 25, 'thirty-two': 32, 'forty-one': 41,
	'forty-five': 45,
};

const NUMBER_ALTS = ['\\d{1,4}', ...Object.keys(WORDS).sort((a, b) => b.length - a.length)];
// `**eight** rows` and `**41 built-ins today**` are both live phrasings, so the
// emphasis markers around the number are optional on either side.
const NUMBER_RE = `(?:\\*\\*)?(${NUMBER_ALTS.join('|')})(?:\\*\\*)?`;

/** @param {string} s @returns {string} */
function escapeRe(s) {
	return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

/**
 * @param {string} token a digit run or a word from `WORDS`
 * @returns {number}
 */
export function numberOf(token) {
	const lower = token.toLowerCase();
	if (/^\d+$/.test(lower)) return Number(lower);
	const n = WORDS[lower];
	if (n === undefined) throw new Error(`check_watch_doc_counts: unreadable number "${token}"`);
	return n;
}

// ---------------------------------------------------------------------------
// Resolvers. Each reads one number out of the Rust that declares it.
// ---------------------------------------------------------------------------

/**
 * `pub const NAME: <ty> = <int>;` — a plain integer constant.
 * @param {string} src @param {string} name @returns {number}
 */
export function constValue(src, name) {
	const m = stripComments(src, 'rust').match(
		new RegExp(`\\bconst\\s+${name}\\s*:\\s*[A-Za-z0-9_]+\\s*=\\s*(\\d+)\\s*;`),
	);
	if (!m) {
		throw new Error(
			`check_watch_doc_counts: \`${name}\` is no longer a plain integer const. ` +
				'Teach the resolver its new shape — a guard must not report a verdict ' +
				'about source it could not read.',
		);
	}
	return Number(m[1]);
}

/**
 * `pub const NAME: [<ty>; <len>] = …;` — a fixed-length array's length.
 * @param {string} src @param {string} name @returns {number}
 */
export function arrayLen(src, name) {
	const m = stripComments(src, 'rust').match(
		new RegExp(`\\bconst\\s+${name}\\s*:\\s*\\[[^\\]]+;\\s*(\\d+)\\s*\\]`),
	);
	if (!m) throw new Error(`check_watch_doc_counts: \`${name}\` is not a fixed-length array const`);
	return Number(m[1]);
}

/**
 * Count of `#[attr(` attributes — the GATT table is declared as one attribute
 * per characteristic, so the table's size is the attribute count.
 * @param {string} src @param {string} attr @returns {number}
 */
export function attributeCount(src, attr) {
	const hits = stripComments(src, 'rust').match(new RegExp(`#\\[\\s*${attr}\\s*\\(`, 'g'));
	if (!hits) throw new Error(`check_watch_doc_counts: no \`#[${attr}(\` attributes found`);
	return hits.length;
}

/**
 * The module names `core/src/lib.rs` declares, in declaration order.
 *
 * `lib.rs`'s own list is the population, not the directory listing: a `.rs`
 * file no `mod` declares is not compiled and its tests do not run, so counting
 * the directory would report tests that do not exist.
 * @param {string} src @returns {string[]}
 */
export function declaredModules(src) {
	const mods = [
		...stripComments(src, 'rust').matchAll(/^\s*(?:pub\s+)?mod\s+([a-z_][a-z0-9_]*)\s*;/gm),
	].map((m) => m[1]);
	if (mods.length === 0) {
		throw new Error('check_watch_doc_counts: no `mod` declarations in core/src/lib.rs');
	}
	return mods;
}

/**
 * `#[test]` attributes in a Rust source, comments stripped.
 *
 * A grep is only trustworthy here because it was measured against the runtime:
 * `cargo test --target <host> -p watch_core` reports 2428 for the lib target
 * and this count is 2428, so the crate declares its tests plainly — no
 * generated tests, no `#[cfg(feature)]`-gated ones. If that stops being true
 * the two diverge and this number is no longer the one that runs, which is
 * what the doc sentence it backs promises.
 * @param {string} src @returns {number}
 */
export function testFnCount(src) {
	return (stripComments(src, 'rust').match(/#\[\s*test\s*\]/g) ?? []).length;
}

/**
 * The variant names of `pub enum <name>`, in declaration order.
 *
 * Comments go first (a doc comment names other variants), then attributes
 * (`#[default]`, `#[cfg_attr(…)]`), and what is left is split at depth 0 so a
 * tuple or struct variant counts once rather than once per field.
 * @param {string} src @param {string} name @returns {string[]}
 */
export function enumVariants(src, name) {
	const code = stripComments(src, 'rust');
	const at = code.search(new RegExp(`\\benum\\s+${name}\\s*\\{`));
	if (at === -1) throw new Error(`check_watch_doc_counts: no \`enum ${name}\` found`);
	const open = code.indexOf('{', at);
	let depth = 0;
	let end = -1;
	for (let i = open; i < code.length; i++) {
		if (code[i] === '{') depth++;
		else if (code[i] === '}') {
			depth--;
			if (depth === 0) {
				end = i;
				break;
			}
		}
	}
	if (end === -1) throw new Error(`check_watch_doc_counts: \`enum ${name}\` never closes`);
	const body = stripAttributes(code.slice(open + 1, end));

	/** @type {string[]} */
	const out = [];
	let depth2 = 0;
	let start = 0;
	const push = (/** @type {string} */ chunk) => {
		const m = chunk.trim().match(/^([A-Za-z_][A-Za-z0-9_]*)/);
		if (m) out.push(m[1]);
	};
	for (let i = 0; i < body.length; i++) {
		const c = body[i];
		if (c === '{' || c === '(' || c === '[') depth2++;
		else if (c === '}' || c === ')' || c === ']') depth2--;
		else if (c === ',' && depth2 === 0) {
			push(body.slice(start, i));
			start = i + 1;
		}
	}
	push(body.slice(start));
	if (out.length === 0) throw new Error(`check_watch_doc_counts: \`enum ${name}\` parsed empty`);
	return out;
}

/** @param {string} body @returns {string} */
function stripAttributes(body) {
	let out = '';
	for (let i = 0; i < body.length; i++) {
		if (body[i] === '#' && body[i + 1] === '[') {
			let depth = 0;
			let j = i + 1;
			for (; j < body.length; j++) {
				if (body[j] === '[') depth++;
				else if (body[j] === ']') {
					depth--;
					if (depth === 0) break;
				}
			}
			i = j;
			continue;
		}
		out += body[i];
	}
	return out;
}

/**
 * A constant three rails DERIVE rather than write down. The reader resolves the
 * derivation and REFUSES a definition that has stopped deriving, rather than
 * reading a fresh literal as agreement — the rule § 793's re-arm row already
 * states.
 * @param {string} src @param {string} name @param {string} expr the expected right-hand side, whitespace-insensitive
 * @param {number} value
 * @returns {number}
 */
export function derivedValue(src, name, expr, value) {
	const code = stripComments(src, 'rust');
	const m = code.match(new RegExp(`\\bconst\\s+${name}\\s*:\\s*[A-Za-z0-9_]+\\s*=\\s*([^;]+);`));
	if (!m) throw new Error(`check_watch_doc_counts: no \`const ${name}\` found`);
	const got = m[1].replace(/\s+/g, ' ').trim();
	const want = expr.replace(/\s+/g, ' ').trim();
	if (got !== want) {
		throw new Error(
			`check_watch_doc_counts: \`${name}\` is now \`${got}\`, not the derivation ` +
				`\`${want}\` this guard resolves. A rail that has stopped deriving must not ` +
				'be read as agreement — re-resolve it here, deliberately.',
		);
	}
	return value;
}

// ---------------------------------------------------------------------------
// The registry.
// ---------------------------------------------------------------------------

/**
 * @typedef {object} Row
 * @property {string} id
 * @property {string} symbol what the number IS, for the failure message
 * @property {(read: (path: string) => string) => number} resolve
 * @property {string[]} phrases templates, `{n}` marking the number
 */

/** @type {Row[]} */
export const REGISTRY = [
	{
		id: 'core.host_tests',
		symbol: '`#[test]` fns across the modules `core/src/lib.rs` declares',
		resolve: (read) => {
			const lib = read(`${CORE}/lib.rs`);
			let n = testFnCount(lib);
			for (const m of declaredModules(lib)) n += testFnCount(read(`${CORE}/${m}.rs`));
			return n;
		},
		phrases: ['{n} host tests in `watch_core`'],
	},
	{
		id: 'privacy.host_tests',
		symbol: '`#[test]` fns in `core/src/privacy.rs`',
		resolve: (read) => testFnCount(read(`${CORE}/privacy.rs`)),
		phrases: ['with {n} host tests'],
	},
	{
		id: 'ble.characteristics',
		symbol: '`#[characteristic(...)]` rows in `app/src/tasks/ble.rs`',
		resolve: (read) =>
			attributeCount(read('apps/custom_watch/app/src/tasks/ble.rs'), 'characteristic'),
		phrases: ['is {n} on one service'],
	},
	{
		id: 'page.builtins',
		symbol: '`Page` variants less the `Screen*` seats, in `core/src/page.rs`',
		resolve: (read) =>
			enumVariants(read(`${CORE}/page.rs`), 'Page').filter((v) => !v.startsWith('Screen')).length,
		phrases: [
			'{n} built-in pages',
			'the {n} built-ins',
			'at {n} built-ins',
			'{n} built-ins today',
			'{n} built-ins plus',
			'a {n}-page ring',
			'full {n}-page mask',
			'{n}-page built-in glance cycle',
			'{n}-page cycle since',
			'{n} codes need',
			'ceil({n}/4)`',
			'depth `ceil({n}/4)',
			'{n} built-in glance pages',
			'separate {n} pages',
			'code pairs at {n}',
			'at {n} it sits three',
		],
	},
	{
		id: 'page.total',
		symbol: '`Page` variants in `core/src/page.rs`, composed seats included',
		resolve: (read) => enumVariants(read(`${CORE}/page.rs`), 'Page').length,
		phrases: [
			'(`ceil({n}/4) − 7`)',
			'at {n} — so the ring',
			'Any of {n}, on a fully-composed',
			'the {n}-page ring a fully-composed',
			'{n}-code set',
			'fully-composed {n}-page',
		],
	},
	{
		id: 'screens.max',
		symbol: '`screens::MAX_SCREENS`',
		resolve: (read) => constValue(read(`${CORE}/screens.rs`), 'MAX_SCREENS'),
		phrases: [
			'up to {n} composed',
			'all {n} composed screens',
			'the {n} §364 seats',
			'the {n} seats were',
			'the {n} composed screens carry',
			'{n} runner-composed screens',
			'up to {n} more seats',
			'`MAX_SCREENS` is {n}',
		],
	},
	{
		id: 'screens.slots',
		symbol: '`screens::SCREEN_SLOTS`',
		resolve: (read) => constValue(read(`${CORE}/screens.rs`), 'SCREEN_SLOTS'),
		phrases: ['`SCREEN_SLOTS` is {n}', '× {n} slots'],
	},
	{
		id: 'menu.items',
		symbol: '`settings_menu::MENU_ITEMS`',
		resolve: (read) => constValue(read(`${CORE}/settings_menu.rs`), 'MENU_ITEMS'),
		phrases: [
			'{n} items at tier 1',
			'all {n} rows',
			'({n} items,',
			'{n} rows over a',
			'the {n} settings-menu rows',
			'legibility of {n} rows',
			"the {n}-ring's",
		],
	},
	{
		id: 'menu.visible',
		symbol: '`settings_menu::MENU_VISIBLE` (`face::ROWS` less `MENU_TOP_ROW`)',
		resolve: (read) => {
			const menu = read(`${CORE}/settings_menu.rs`);
			const rows = constValue(read(`${CORE}/face.rs`), 'ROWS');
			const top = constValue(menu, 'MENU_TOP_ROW');
			return derivedValue(menu, 'MENU_VISIBLE', 'ROWS - MENU_TOP_ROW', rows - top);
		},
		phrases: ['{n} visible rows'],
	},
	{
		id: 'flash.slots',
		symbol: '`flash_store::SLOT_COUNT`',
		resolve: (read) => constValue(read(`${CORE}/flash_store.rs`), 'SLOT_COUNT'),
		phrases: [
			'{n} run slots',
			'{n} slots of 4 KiB',
			'one of {n} slots',
			'all {n} slots',
			'{n} 4 KiB internal-flash slots',
			'{n} × 4 KiB internal-flash slots',
			'up to {n} runs',
			'of the {n} slots',
		],
	},
	{
		id: 'flash.points',
		symbol: '`flash_store::MAX_POINTS_PER_RUN`',
		resolve: (read) => {
			const flash = read(`${CORE}/flash_store.rs`);
			const runStore = read(`${CORE}/run_store.rs`);
			const slot = constValue(flash, 'SLOT_LEN');
			const header = constValue(runStore, 'HEADER_LEN');
			const footer = constValue(runStore, 'FOOTER_LEN');
			const point = constValue(runStore, 'POINT_LEN');
			return derivedValue(
				flash,
				'MAX_POINTS_PER_RUN',
				'((SLOT_LEN - HEADER_LEN - FOOTER_LEN) / POINT_LEN) as u32',
				Math.floor((slot - header - footer) / point),
			);
		},
		phrases: [
			'{n} records per run',
			'{n} points per run',
			'{n}-record-per-run cap',
			'{n}-record cap',
			'{n}-point flash cap',
			'{n}-point-per-run cap',
			'{n}-point cap',
			'instead of {n} records',
		],
	},
	{
		id: 'waypoints.max',
		symbol: '`waypoints::MAX_WAYPOINTS`',
		resolve: (read) => constValue(read(`${CORE}/waypoints.rs`), 'MAX_WAYPOINTS'),
		phrases: ['{n} waypoints', 'an {n}-slot newest-wins', 'the {n}-slot store'],
	},
	{
		id: 'metric.variants',
		symbol: '`face::Metric` variants in `core/src/face.rs`',
		resolve: (read) => enumVariants(read(`${CORE}/face.rs`), 'Metric').length,
		phrases: ['at the landing, {n} today'],
	},
	{
		id: 'timers.presets',
		symbol: '`timers::PRESETS_S` length',
		resolve: (read) => arrayLen(read(`${CORE}/timers.rs`), 'PRESETS_S'),
		phrases: ['clamped {n}-rung ladder', 'the {n}-rung preset ladder'],
	},
	{
		id: 'idle.faces',
		symbol: '`face::IdleView` variants in `core/src/face.rs`',
		resolve: (read) => enumVariants(read(`${CORE}/face.rs`), 'IdleView').length,
		phrases: ['{n} idle faces', '{n} faces BTN4 walks', 'widened to {n} faces'],
	},
	{
		id: 'settings.version',
		symbol: '`settings::SETTINGS_VERSION`',
		resolve: (read) => constValue(read(`${CORE}/settings.rs`), 'SETTINGS_VERSION'),
		phrases: ['frame is now v{n}'],
	},
	{
		id: 'course.points',
		symbol: '`course::MAX_COURSE_POINTS`',
		resolve: (read) => constValue(read(`${CORE}/course.rs`), 'MAX_COURSE_POINTS'),
		phrases: [
			'{n}-point course cap',
			'up to {n} points',
			'{n} points / 4 KiB RAM',
			'{n}-point budget',
			'{n}-point `CRS1`',
		],
	},
	{
		id: 'trackback.crumbs',
		symbol: '`trackback::BREADCRUMB_CAP`',
		resolve: (read) => constValue(read(`${CORE}/trackback.rs`), 'BREADCRUMB_CAP'),
		phrases: ['the {n}-point trackback breadcrumb', '{n} points at 20 m spacing'],
	},
	{
		id: 'gnss.modes',
		symbol: '`gnss_mode::GnssMode` variants',
		resolve: (read) => enumVariants(read(`${CORE}/gnss_mode.rs`), 'GnssMode').length,
		phrases: ['defines {n} modes'],
	},
	{
		id: 'run_store.laps',
		symbol: '`run_store::MAX_STORED_LAPS`',
		resolve: (read) => constValue(read(`${CORE}/run_store.rs`), 'MAX_STORED_LAPS'),
		phrases: ['{n}-lap storage budget', 'lap budget is {n} records'],
	},
	{
		id: 'autolap.rungs',
		symbol: '`auto_lap::AutoLap` variants',
		resolve: (read) => enumVariants(read(`${CORE}/auto_lap.rs`), 'AutoLap').length,
		phrases: ['closed {n}-rung catalogue'],
	},
	{
		id: 'elevation.profile',
		symbol: '`record::ELEV_PROFILE_CAP`',
		resolve: (read) => constValue(read(`${CORE}/record.rs`), 'ELEV_PROFILE_CAP'),
		phrases: ['{n}-sample elevation ring'],
	},
	{
		id: 'panel.cols',
		symbol: '`face::COLS`',
		resolve: (read) => constValue(read(`${CORE}/face.rs`), 'COLS'),
		phrases: ['{n} text columns'],
	},
	{
		id: 'panel.rows',
		symbol: '`face::ROWS`',
		resolve: (read) => constValue(read(`${CORE}/face.rs`), 'ROWS'),
		phrases: ['{n} rows of the 8×16 font', 'a panel of {n} (144 px', 'filled the {n}-row'],
	},
	{
		id: 'grid.capacity',
		symbol: '`page_grid::GRID_CAPACITY` (`GRID_COLS` × `face::ROWS` less `GRID_TOP_ROW`)',
		resolve: (read) => {
			const grid = read(`${CORE}/page_grid.rs`);
			const cols = constValue(grid, 'GRID_COLS');
			const top = constValue(grid, 'GRID_TOP_ROW');
			const rows = constValue(read(`${CORE}/face.rs`), 'ROWS');
			derivedValue(grid, 'GRID_BODY_ROWS', 'ROWS - GRID_TOP_ROW', rows - top);
			return derivedValue(
				grid,
				'GRID_CAPACITY',
				'GRID_COLS * GRID_BODY_ROWS',
				cols * (rows - top),
			);
		},
		phrases: ['= {n} cells'],
	},
	{
		id: 'profiles.count',
		symbol: '`profiles::ActivityProfile` variants',
		resolve: (read) => enumVariants(read(`${CORE}/profiles.rs`), 'ActivityProfile').length,
		phrases: ['the {n} profiles as'],
	},
];

// ---------------------------------------------------------------------------
// The sweep.
// ---------------------------------------------------------------------------

/**
 * Count-shaped nouns whose numbered occurrences must be claimed by a template or
 * exempted. Deliberately narrow: a noun broad enough to catch every prose use of
 * "pages" or "rows" would need an exemption list nobody reads, and an exemption
 * list nobody reads is the § 850 defect with extra steps.
 */
export const SWEEP_NOUNS = [
	'characteristics?',
	'built-ins?',
	'built-in pages?',
	'(?:runner-)?composed(?: data)? screens?',
	'(?:settings-)?menu rows?',
	'visible rows?',
	'run slots?',
	'waypoints?',
	'idle faces?',
	'records? per run',
	'points? per run',
	'-record(?:-per-run)? cap',
	'-point(?:-per-run)? cap',
	'-page (?:ring|mask|cycle)',
	'-code set',
	'-rung preset ladder',
	'-slot newest-wins',
	'-point course cap',
	'-point trackback',
	'-lap storage budget',
	'-rung catalogue',
	'text columns',
	'host tests?',
	'-sample elevation ring',
];

/**
 * Numbered occurrences of a `SWEEP_NOUNS` phrase that are NOT a live claim about
 * a firmware symbol. Keyed on file plus the exact text; every entry must match at
 * least once, so an exemption cannot outlive the sentence it excuses.
 * @type {Array<{ file: string, text: string, reason: string }>}
 */
export const NOT_A_SYMBOL_COUNT = [
	{
		file: 'docs/custom_watch/roadmap.md',
		text: '407 host tests',
		reason:
			'The tail of "2,407", and a WORKSPACE sweep figure — every crate plus the ' +
			'integration binaries — not `watch_core`\'s own. It carries its command and its ' +
			'measurement date in the same sentence, which is what makes it honest as a ' +
			'dated snapshot; nothing here can re-derive it without running cargo.',
	},
	{
		file: 'docs/custom_watch/quality_standards.md',
		text: 'two host tests',
		reason:
			'Two named tests over `Recorder` that guarded the #330 re-anchor, not a count ' +
			'of any symbol. The sentence is about which guards existed when the fixture ' +
			'was written.',
	},
	{
		file: 'docs/custom_watch/firmware.md',
		text: 'two characteristics',
		reason:
			'The design-era proposal this doc exists to correct, quoted so it can be ' +
			'corrected. The sentence beside it states the shipped size and IS registered.',
	},
	{
		file: 'docs/custom_watch/roadmap.md',
		text: 'five characteristics',
		reason:
			'The characteristics that ACCEPT a push, not the whole table — `note_push` is a ' +
			'write path, so `push_status` and the notify rows are outside it.',
	},
	{
		file: 'docs/custom_watch/navigation.md',
		text: 'at 37 built-ins the',
		reason:
			'A deliberate then-and-now: the sentence measures how the press margin moved ' +
			'between the ring § 289 was chosen against and the ring today.',
	},
	{
		file: 'docs/custom_watch/navigation.md',
		text: 'a 36-page ring',
		reason:
			'The ring size at which the grid first needed a sixth move — a fact about a ' +
			'past ring, which is the whole point of the paragraph.',
	},
	{
		file: 'docs/custom_watch/roadmap.md',
		text: '37-page ring it was chosen against',
		reason: 'Same then-and-now as `navigation.md`: the ring `MAX_SCREENS` was sized against.',
	},
	{
		file: 'apps/custom_watch/local_testing.md',
		text: 'two idle faces',
		reason:
			'An account of what the screenshot harness once wrongly "proved" — the sentence ' +
			'is about the defect, and the number is the defect.',
	},
];

// ---------------------------------------------------------------------------

/**
 * @param {string} phrase a template with `{n}` where the number goes
 * @returns {RegExp}
 */
function templateRe(phrase) {
	const parts = phrase.split('{n}');
	if (parts.length < 2) {
		throw new Error(`check_watch_doc_counts: template "${phrase}" has no {n}`);
	}
	return new RegExp(parts.map(escapeRe).join(NUMBER_RE), 'gi');
}

/**
 * @param {Record<string, string>} docs path -> markdown
 * @param {(path: string) => string} readSource
 * @param {Row[]} [registry] overridable so the unit tests can drive one row over
 *   a fixture doc set; production always passes the whole registry.
 * @param {Array<{ file: string, text: string, reason: string }>} [exemptions]
 * @param {string[]} [sweepNouns]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(
	docs,
	readSource,
	registry = REGISTRY,
	exemptions = NOT_A_SYMBOL_COUNT,
	sweepNouns = SWEEP_NOUNS,
) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];

	// Exemptions are resolved FIRST and win outright. A registered template can
	// be broad enough to reach a sentence that deliberately states a past number
	// (`navigation.md` measures the press margin at 37 built-ins against 41
	// today), and a guard that cannot be told "this one is history" is a guard
	// that gets its templates narrowed until they check nothing.
	/** @type {Map<string, Array<[number, number]>>} */
	const exempt = new Map();
	/** @type {Set<number>} */
	const usedExemptions = new Set();
	for (const file of Object.keys(docs)) exempt.set(file, []);
	exemptions.forEach((e, i) => {
		const md = docs[e.file];
		if (md === undefined) {
			errors.push(
				`the NOT_A_SYMBOL_COUNT entry for "${e.text}" names ${e.file}, which is not in ` +
					'DOC_FILES, so it excuses nothing.',
			);
			// Reported once. The stale-exemption sweep below would otherwise say
			// the same thing again in weaker words.
			usedExemptions.add(i);
			return;
		}
		const spans = exempt.get(e.file) ?? [];
		for (let at = md.indexOf(e.text); at !== -1; at = md.indexOf(e.text, at + 1)) {
			spans.push([at, at + e.text.length]);
			usedExemptions.add(i);
		}
	});

	/** @type {Map<string, Array<[number, number]>>} spans a template claimed, per file */
	const claimed = new Map();
	for (const file of Object.keys(docs)) claimed.set(file, []);

	/** @type {(spans: Array<[number, number]>, a: number, b: number) => boolean} */
	const overlaps = (spans, a, b) => spans.some(([x, y]) => a < y && x < b);

	let statements = 0;
	for (const row of registry) {
		let want;
		try {
			want = row.resolve(readSource);
		} catch (err) {
			errors.push(err instanceof Error ? err.message : String(err));
			continue;
		}
		for (const phrase of row.phrases) {
			const re = templateRe(phrase);
			let phraseHits = 0;
			for (const [file, md] of Object.entries(docs)) {
				for (const m of md.matchAll(re)) {
					const a = m.index;
					const b = a + m[0].length;
					if (overlaps(exempt.get(file) ?? [], a, b)) continue;
					phraseHits++;
					statements++;
					const span = claimed.get(file);
					if (span) span.push([a, b]);
					const got = numberOf(m[1]);
					if (got === want) continue;
					errors.push(
						`${file}: "${m[0].trim()}" states ${got} where ${row.symbol} is ${want}. ` +
							`The source is the fact; the sentence is the transcription (${row.id}).`,
					);
				}
			}
			if (phraseHits === 0) {
				errors.push(
					`the template "${phrase}" (${row.id}) matches nothing in the doc set, so it ` +
						'checks nothing. Delete it, or fix the sentence it was written for — a ' +
						'template that cannot fail is worse than no template.',
				);
			}
		}
	}

	// The other direction: a count-shaped noun no template claimed. Without this
	// the registry would read as complete while covering only the numbers someone
	// remembered to add, which is worse than covering none.
	const sweepRe = new RegExp(
		`(?<![§#\\d])${NUMBER_RE}[ -]?(?:${sweepNouns.join('|')})`,
		'gi',
	);
	for (const [file, md] of Object.entries(docs)) {
		const spans = claimed.get(file) ?? [];
		const exemptSpans = exempt.get(file) ?? [];
		for (const m of md.matchAll(sweepRe)) {
			const a = m.index;
			const b = a + m[0].length;
			if (overlaps(spans, a, b)) continue;
			if (overlaps(exemptSpans, a, b)) continue;
			errors.push(
				`${file}: "${m[0].trim()}" is a count about a firmware symbol that no template ` +
					'in this registry reads. Register it against the symbol it describes, write ' +
					'the sentence count-free, or name it in NOT_A_SYMBOL_COUNT with a reason.',
			);
		}
	}
	exemptions.forEach((e, i) => {
		if (usedExemptions.has(i)) return;
		errors.push(
			`the NOT_A_SYMBOL_COUNT entry for "${e.text}" in ${e.file} matches nothing. The ` +
				'sentence it excuses is gone — delete the exemption rather than leaving a ' +
				'standing permission nobody re-reads.',
		);
	});

	if (errors.length === 0) {
		ok.push(
			`${statements} doc statement(s) agree with ${registry.length} firmware symbol(s) ` +
				`across ${Object.keys(docs).length} present-tense doc(s)`,
		);
	}
	return { errors, ok };
}

/** @returns {Record<string, string>} */
export function loadDocs() {
	const stray = unregisteredDocs(readdirSync(join(ROOT, WATCH_DOC_DIR)));
	if (stray.length > 0) {
		throw new Error(
			`check_watch_doc_counts: ${stray.join(', ')} is under ${WATCH_DOC_DIR} but in ` +
				'neither DOC_FILES nor DATED_LOGS, so any firmware count it states goes ' +
				'unread. Add it to DOC_FILES, or to DATED_LOGS if it stamps its entries ' +
				'with a date and records what was true when written.',
		);
	}
	/** @type {Record<string, string>} */
	const out = {};
	for (const f of DOC_FILES) out[f] = readFileSync(join(ROOT, f), 'utf-8');
	return out;
}

/** @param {string} path @returns {string} */
export function loadSource(path) {
	return readFileSync(join(ROOT, path), 'utf-8');
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const { errors, ok } = check(loadDocs(), loadSource);
	for (const line of ok) console.log(`[OK] check_watch_doc_counts: ${line}`);
	for (const line of errors) console.error(`::error::check_watch_doc_counts: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_watch_doc_counts: ${errors.length} disagreement(s) between the docs and the ` +
				'firmware. The Rust declares the number; the prose restates it.',
		);
		process.exit(1);
	}
}
