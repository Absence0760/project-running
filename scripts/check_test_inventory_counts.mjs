#!/usr/bin/env node
// Guardrail: a per-file test count stated in `docs/testing/test_inventory.md`
// is the count the file's own recompute command reports.
//
// Why this exists: decisions.md § 1259. The census was re-measured by hand in
// § 1217 and 49 of the 111 measurable counts were wrong, one of them by a
// factor of four (23 stated against 94). A hand re-measurement is a snapshot;
// the next round that adds a test makes it stale again, which is how it got to
// 49 in the first place.
//
// **The population is the thing that cannot be removed.** A guard keyed on the
// sentence shape can be escaped by rewording, so this one is keyed on the
// heading NAMING A FILE: every `### ` heading above the `Suite totals` divider
// must name at least one path (or be exempted by name), and every path it
// names must carry a count claim (or be exempted, with the reason). Deleting
// the number therefore fails, and so does deleting the path — a census heading
// that names no file has stopped being an index entry, which is the whole
// purpose of the section.
//
// Two carve-outs, both already stated in the document's own text:
//
//   1. **A parameterised count is a RUNTIME count**, not a declaration count.
//      `l10n_generated_parity_test.dart` declares `1 + 3 per catalogue` and
//      `catalogues.test.ts` one per locale; a naive sweep would "correct" two
//      correct numbers into wrong ones. Each is named in `PARAMETERISED` with
//      the arithmetic that makes it right.
//   2. **Everything BELOW the `Suite totals` divider is a per-round historical
//      record** and is deliberately not refreshed. Twenty of those headings
//      name paths that no longer exist, which is what a record of a past round
//      looks like.
//
// The counters are the commands the document prescribes, line-anchored exactly
// as `grep -cE` applies them, so a commented-out declaration does not count
// and neither does one nested inside another call's arguments.
//
// **The second claim is about the files the census does NOT name.** It names
// 1,004 of the 2,227 suites the tree holds, so "walk the tree and fail on a
// file the index omits" is a 1,223-row change, not the four the filing assumed.
// What the omission actually costs is that an unnamed suite can stop declaring
// tests and no number moves. So the rule is turned round: no test file may
// declare ZERO. A suite that counts nothing is one the census could only ever
// state a wrong number for, and it reads exactly like a suite that passes
// (decisions § 1535).
//
// **The third claim is that the census SAYS which of the two it is.** The
// paragraph above was this file's header comment and nowhere else, so a reader
// counting the document's coverage found 60 of 549 mobile suites named, no
// statement of intent anywhere in it, and re-filed the gap. The guessed rule —
// "web suites plus anything with no web twin" — was then measured and is false:
// 343 of the 549 have no web twin AND no mention, and the per-tree coverage
// (60/549 mobile, 74/439 web, 80/80 watch_wear, 79/79 job_worker) is a
// selection showing rather than a rule. `checkScope` requires the document to
// carry the scope statement, prints the live coverage on every pass so nobody
// has to trust a transcribed figure, and holds a FLOOR under the index —
// the figures themselves are deliberately NOT compared against the tree,
// because a suite is added most weeks and a stated total would have to be
// retyped in a document nobody was otherwise editing (decisions § 1586).
//
// That rule is only as honest as the counters, and the Dart one had a blind
// spot big enough to hide 16 committed suites: `realtimeWidgetTest` is a
// `testWidgets` wrapper this repo defines, and the document's own recompute
// command — `grep -cE '^\s*(test|testWidgets)\('` — reports 0 for every file
// that uses it. `DART_TEST_WRAPPERS` names the wrapper WITH the file that
// defines it, and that definition is re-read: an entry whose wrapper has
// stopped wrapping a test declaration fails rather than inflating counts.
//
// Run: `node scripts/check_test_inventory_counts.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_test_inventory_counts.test.mjs`

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join, posix } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.TEST_INVENTORY_ROOT ?? REPO_ROOT;

export const INVENTORY = 'docs/testing/test_inventory.md';

/** Everything from this heading down is a per-round record, not the census. */
export const DIVIDER = /^##\s+Suite totals/;

/**
 * Census headings that name no file. Each must match at least once, so an
 * exemption cannot outlive the heading it excuses.
 * @type {Array<{ heading: string, reason: string }>}
 */
export const NOT_A_FILE_SECTION = [
	{
		heading: 'Screen + widget smoke tests',
		reason:
			'A shape, not a file set: it describes how the ~48 widget suites are written. ' +
			'Its two figures are written with a `~` and claim to be approximate.',
	},
	{
		heading: 'Pure-helper extractions',
		reason: 'Same shape as the widget-smoke section above — a pattern, not a file set.',
	},
];

/**
 * Paths whose stated number is not a declaration count. Keyed on the path plus
 * the exact heading fragment, and each must match.
 * @type {Array<{ path: string, reason: string }>}
 */
export const PARAMETERISED = [
	{
		path: 'apps/mobile_android/test/l10n_generated_parity_test.dart',
		reason:
			'`1 + 3 per catalogue`: the file declares 4 `test(` calls, three of them inside ' +
			'a loop over the ARB catalogues, so the 22 it states is what the RUNNER reports. ' +
			'Replacing it with the declaration count would make a correct number wrong.',
	},
	{
		path: 'apps/web/src/lib/i18n/catalogues.test.ts',
		reason:
			'One `test(` per locale, generated in a loop over the catalogue list. Same ' +
			'runtime-versus-declaration split as `l10n_generated_parity_test.dart`.',
	},
	{
		path: 'apps/watch_garmin/scripts/check_garmin_source.sh',
		reason:
			'The 5 is the number of source-level claims the shell guard asserts, not a count ' +
			'of test declarations — the file is a `.sh` and declares none.',
	},
];

// ---------------------------------------------------------------------------
// Counters.
// ---------------------------------------------------------------------------

/**
 * Test-declaration wrappers this repo defines itself. A counter that knows only
 * the framework's own spelling reports a file built on one of these as holding
 * no tests at all, which is both a wrong census number and a hole in the
 * zero-declaration rule below.
 *
 * Each names the file that DEFINES it and the declaration it wraps, and both
 * are re-read: an entry is a claim about the tree, not a permission.
 * @type {Array<{ call: string, definedIn: string, wraps: string, reason: string }>}
 */
export const DART_TEST_WRAPPERS = [
	{
		call: 'realtimeWidgetTest',
		definedIn: 'apps/mobile_android/test/realtime_drain.dart',
		wraps: 'testWidgets',
		reason:
			'`realtime_client` arms a 50 s disconnect timer from inside `unsubscribe`, which a ' +
			'screen calls from `dispose`, so every screen holding a channel fails the pending-' +
			'timer check on teardown unless the test unmounts and pumps past it. The wrapper is ' +
			'that teardown; 16 committed suites are written on it and counted 0 without this.',
	},
];

/**
 * How a declaration is counted, per file kind. Each is the document's own
 * prescribed recompute command, line-anchored the way `grep -cE` applies it.
 * @type {Array<{ id: string, match: (path: string) => boolean, count: (src: string) => number }>}
 */
export const COUNTERS = [
	{
		id: 'dart',
		match: (p) => p.endsWith('.dart'),
		count: (src) =>
			lineMatches(
				src,
				new RegExp(
					`^\\s*(?:test|testWidgets${DART_TEST_WRAPPERS.map((w) => `|${w.call}`).join('')})\\(`,
				),
			),
	},
	{
		id: 'deno',
		match: (p) => p.includes('/supabase/functions/') && /\.(?:ts|mjs|js)$/.test(p),
		count: (src) => lineMatches(src, /^\s*Deno\.test\(/),
	},
	{
		id: 'js',
		match: (p) => /\.(?:ts|mjs|js)$/.test(p),
		count: (src) => lineMatches(src, /^\s*(?:test|it)\(/),
	},
	{ id: 'go', match: (p) => p.endsWith('.go'), count: (src) => lineMatches(src, /^func Test/) },
	{ id: 'rust', match: (p) => p.endsWith('.rs'), count: (src) => lineMatches(src, /^\s*#\[test\]/) },
	{ id: 'kotlin', match: (p) => p.endsWith('.kt'), count: (src) => lineMatches(src, /^\s*@Test\b/) },
	{
		id: 'pgtap',
		match: (p) => p.endsWith('.sql'),
		count: (src) =>
			[...src.matchAll(/\bplan\((\d+)\)/g)].reduce((sum, m) => sum + Number(m[1]), 0),
	},
];

/** @param {string} src @param {RegExp} re @returns {number} */
function lineMatches(src, re) {
	let n = 0;
	for (const line of src.split('\n')) if (re.test(line)) n++;
	return n;
}

/**
 * @param {string} path
 * @returns {(src: string) => number}
 */
export function counterFor(path) {
	const hit = COUNTERS.find((c) => c.match(path));
	if (!hit) {
		throw new Error(
			`check_test_inventory_counts: no counter knows how to read ${path}. Teach ` +
				'COUNTERS its kind — a guard must not report a verdict about a file it ' +
				'could not count.',
		);
	}
	return hit.count;
}

// ---------------------------------------------------------------------------
// Parsing the census.
// ---------------------------------------------------------------------------

/** File suffixes a backticked heading token has to be resolved as a path. */
const TEST_SUFFIXES = ['.dart', '.ts', '.mjs', '.js', '.go', '.rs', '.kt', '.sql', '.sh'];

/**
 * @typedef {object} Claim
 * @property {string} token the backticked text as written
 * @property {number | null} count the first number attributed to the token
 * @property {'tests' | 'files'} unit what that number counts
 * @property {number | null} across the `across N files` figure, when stated
 */

/**
 * Parse one heading into the path tokens it names and the number attributed to
 * each. A number is attributed only when it FOLLOWS the token immediately, via
 * ` — ` or ` (`; a figure further along the sentence (`(3 added)`) belongs to
 * the round, not to the file, and is left alone.
 * @param {string} heading heading text, `### ` already removed
 * @returns {Claim[]}
 */
export function claimsIn(heading) {
	/** @type {Claim[]} */
	const out = [];
	const re = /`([^`]+)`(?:\s*(?:—|-{2})\s*|\s*\()?\s*(~?)([\d,]+)?/g;
	for (const m of heading.matchAll(re)) {
		const token = m[1];
		if (!looksLikePath(token)) continue;
		const approximate = m[2] === '~';
		const digits = m[3];
		const tail = heading.slice(m.index + m[0].length);
		// `— 1 added` is what one ROUND contributed, not what the file holds. A
		// grammar that reads it as the count would demand the delta be kept
		// current, which is the opposite of what a delta means.
		const delta = /^\s*(?:added|replaced|removed|new|more)\b/.test(tail);
		const count =
			digits === undefined || approximate || delta ? null : Number(digits.replace(/,/g, ''));
		const unit = /^\s*files\b/.test(tail) ? 'files' : 'tests';
		const acrossMatch = tail.match(/^[^`]*?\bacross\s+([\d,]+)\s+\S*\s*files\b/);
		out.push({
			token,
			count,
			unit,
			across: acrossMatch ? Number(acrossMatch[1].replace(/,/g, '')) : null,
		});
	}
	return out;
}

/** @param {string} token @returns {boolean} */
export function looksLikePath(token) {
	if (token.endsWith('/')) return true;
	if (token.includes('*')) return true;
	return TEST_SUFFIXES.some((s) => token.endsWith(s));
}

/**
 * Census headings, in order, each with its claims, plus the per-file bullets
 * underneath it. A heading is a `### ` line above the divider.
 *
 * The bullets are a much larger population than the headings — 78 against 148 —
 * and drift for the same reason. They are checked only WHEN THEY STATE A
 * COUNT, unlike a heading, which must state one: a bullet is prose inside a
 * section whose heading already carries the aggregate, so a bullet losing its
 * number loses no coverage, where a heading losing its number would leave the
 * file it names entirely unquantified.
 * @param {string} md
 * @returns {Array<{ heading: string, line: number, claims: Claim[], bullets: Array<{ line: number, claim: Claim }> }>}
 */
export function censusHeadings(md) {
	/** @type {Array<{ heading: string, line: number, claims: Claim[], bullets: Array<{ line: number, claim: Claim }> }>} */
	const out = [];
	const lines = md.split('\n');
	let fenced = false;
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (/^\s{0,3}(?:`{3,}|~{3,})/.test(line)) {
			fenced = !fenced;
			continue;
		}
		if (fenced) continue;
		if (DIVIDER.test(line)) break;
		const m = line.match(/^###\s+(.*?)\s*$/);
		if (m) {
			out.push({ heading: m[1], line: i + 1, claims: claimsIn(m[1]), bullets: [] });
			continue;
		}
		const bullet = line.match(/^-\s+\*\*(`[^`]+`)\*\*(.*)$/);
		if (!bullet || out.length === 0) continue;
		const [claim] = claimsIn(`${bullet[1]}${bullet[2]}`);
		if (claim && claim.count !== null) {
			out[out.length - 1].bullets.push({ line: i + 1, claim });
		}
	}
	return out;
}

/**
 * The directory a bare basename in a section resolves against: the directory
 * of the section heading's first path token.
 * @param {Claim[]} claims
 * @returns {string}
 */
export function sectionDir(claims) {
	const first = claims.find((c) => c.token.includes('/'));
	if (!first) return '';
	const token = first.token;
	if (token.endsWith('/')) return token.slice(0, -1);
	const fixed = token.split('/').filter((seg) => !seg.includes('*'));
	return fixed.length === token.split('/').length ? posix.dirname(token) : fixed.join('/');
}

// ---------------------------------------------------------------------------
// The check.
// ---------------------------------------------------------------------------

/**
 * @param {string} md the inventory document
 * @param {(pattern: string) => string[]} expand a token -> the repo-relative files it names
 * @param {(path: string) => string} read
 * @param {Array<{ heading: string, reason: string }>} [notAFileSection]
 * @param {Array<{ path: string, reason: string }>} [parameterised]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(md, expand, read, notAFileSection = NOT_A_FILE_SECTION, parameterised = PARAMETERISED) {
	/** @type {string[]} */
	const errors = [];
	/** @type {Set<number>} */
	const usedSections = new Set();
	/** @type {Set<number>} */
	const usedParams = new Set();

	const headings = censusHeadings(md);
	let verified = 0;

	for (const { heading, line, claims, bullets } of headings) {
		const where = `${INVENTORY}:${line}`;
		if (claims.length === 0) {
			const at = notAFileSection.findIndex((e) => heading.startsWith(e.heading));
			if (at === -1) {
				errors.push(
					`${where}: "${heading}" names no test file, so nothing can re-derive what it ` +
						'says. Name the file in backticks, or add it to NOT_A_FILE_SECTION with ' +
						'a reason.',
				);
				continue;
			}
			usedSections.add(at);
			continue;
		}

		/** @type {string} the directory a bare basename resolves against */
		let base = '';
		for (const claim of claims) {
			if (claim.token.includes('/')) base = posix.dirname(claim.token);
			verified += verify(claim, base, where, true);
		}

		const dir = sectionDir(claims);
		for (const { line: bl, claim } of bullets) {
			verified += verify(claim, dir, `${INVENTORY}:${bl}`, false);
		}
	}

	/**
	 * @param {Claim} claim
	 * @param {string} base directory a bare basename resolves against
	 * @param {string} where
	 * @param {boolean} countRequired a heading must state one; a bullet need not
	 * @returns {number} 1 when a figure was re-derived, 0 otherwise
	 */
	function verify(claim, base, where, countRequired) {
		// A token is tried as written first and then against the section's own
		// directory: `_shared/webhook_security.test.ts` carries a slash and is
		// still relative to the section, so "has a slash means repo-relative"
		// silently resolves 25 of the deno bullets to nothing.
		const candidates = [claim.token, posix.join(base, claim.token)];
		const files = candidates.map(expand).find((f) => f.length > 0) ?? [];
		if (files.length === 0) {
			errors.push(
				`${where}: \`${claim.token}\` names no file in the repository. A census entry ` +
					'for a file that has moved or gone documents nothing.',
			);
			return 0;
		}

		const paramAt = parameterised.findIndex((p) => files.length === 1 && p.path === files[0]);
		if (paramAt !== -1) {
			usedParams.add(paramAt);
			return 0;
		}
		if (claim.count === null) {
			if (!countRequired) return 0;
			errors.push(
				`${where}: \`${claim.token}\` carries no count, so the census entry states ` +
					'nothing a reader can trust. Write `— N tests`, or name the file in ' +
					'PARAMETERISED if its number is a runtime count.',
			);
			return 0;
		}

		if (claim.unit === 'files') {
			if (claim.count !== files.length) {
				errors.push(
					`${where}: \`${claim.token}\` states ${claim.count} files where ${files.length} match.`,
				);
			}
			return 1;
		}

		let want = 0;
		try {
			for (const f of files) want += counterFor(f)(read(f));
		} catch (err) {
			errors.push(err instanceof Error ? err.message : String(err));
			return 0;
		}
		if (claim.count !== want) {
			errors.push(
				`${where}: \`${claim.token}\` states ${claim.count} tests where the recompute ` +
					`command counts ${want}${files.length > 1 ? ` across ${files.length} files` : ''}.`,
			);
		}
		if (claim.across !== null && claim.across !== files.length) {
			errors.push(
				`${where}: \`${claim.token}\` states "across ${claim.across} files" where ` +
					`${files.length} match.`,
			);
		}
		return 1;
	}

	notAFileSection.forEach((e, i) => {
		if (usedSections.has(i)) return;
		errors.push(
			`the NOT_A_FILE_SECTION entry for "${e.heading}" matches no census heading. Delete ` +
				'it rather than leaving a standing permission nobody re-reads.',
		);
	});
	parameterised.forEach((p, i) => {
		if (usedParams.has(i)) return;
		errors.push(
			`the PARAMETERISED entry for ${p.path} matches no census claim. Delete it rather ` +
				'than leaving a standing permission nobody re-reads.',
		);
	});

	return {
		errors,
		ok:
			errors.length === 0
				? [
						`${verified} count(s) across ${headings.length} census heading(s) agree with ` +
							'the recompute commands',
					]
				: [],
	};
}

// ---------------------------------------------------------------------------

/**
 * A file whose NAME says it is a test suite, under each convention this repo
 * uses. Not "a file some counter can read" — that is every `.ts` in the tree —
 * and not a roster, so a suite added under one of these names is measured the
 * day it lands.
 */
export const TEST_FILE =
	/(?:^|\/)(?:[^/]+_test\.(?:dart|go)|[^/]+\.test\.(?:ts|mjs|js)|[^/]+Test\.kt)$/;

/** pgTAP suites are named for what they cover, so they are located instead. */
export const PGTAP_DIR = 'apps/backend/supabase/tests/';

/**
 * The floor under the WALK. A predicate that stopped matching would find no
 * suites and agree with a repo that has none, and two broken halves pass by
 * agreeing. Measured at 2,219 the day this landed.
 */
export const MIN_TEST_FILES = 1800;

/**
 * Suites that legitimately declare nothing. Each must still match a tracked
 * file AND still count zero, so an exemption cannot outlive what it excused.
 * @type {Array<{ path: string, reason: string }>}
 */
export const ZERO_DECLARATIONS_OK = [
	{
		path: 'apps/graph_cycle/internal/graph/testhelpers_test.go',
		reason:
			'Go compiles `_test.go` files only under `go test`, so an in-package helper has to ' +
			'carry the suffix to be visible to the suite. This one holds two constructors and ' +
			'no `func Test`, which is the convention working rather than a suite that stopped.',
	},
];

/**
 * Claim 2: every suite the tree holds declares at least one test, counted the
 * way the census would count it.
 *
 * @param {string[]} files every tracked path
 * @param {(path: string) => string} read
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkPopulation(files, read) {
	/** @type {string[]} */
	const errors = [];
	const suites = files.filter(
		(f) => TEST_FILE.test(f) || (f.startsWith(PGTAP_DIR) && f.endsWith('.sql')),
	);
	if (suites.length < MIN_TEST_FILES) {
		return {
			errors: [
				`the suite walk found ${suites.length} file(s) and this guard's floor is ` +
					`${MIN_TEST_FILES}. Either TEST_FILE stopped matching — in which case this ` +
					`claim measures nothing and would agree with a repo holding no tests — or the ` +
					`suites went, in which case lower the floor deliberately.`,
			],
			ok: [],
		};
	}

	for (const wrapper of DART_TEST_WRAPPERS) {
		if (!files.includes(wrapper.definedIn)) {
			errors.push(
				`DART_TEST_WRAPPERS counts \`${wrapper.call}(\` as a test declaration and names ` +
					`${wrapper.definedIn} as where it is defined, which the tree no longer holds. A ` +
					`counter crediting a call nothing defines inflates every number below it.`,
			);
			continue;
		}
		const src = read(wrapper.definedIn);
		const defines = new RegExp(`\\b${wrapper.call}\\s*\\(`).test(src);
		if (!defines || !src.includes(`${wrapper.wraps}(`)) {
			errors.push(
				`${wrapper.definedIn} no longer defines \`${wrapper.call}\` as a \`${wrapper.wraps}\` ` +
					`wrapper, so counting that call as a test declaration is a guess. Re-point the ` +
					`entry or delete it.`,
			);
		}
	}

	/** @type {Set<number>} */
	const usedExemptions = new Set();
	let counted = 0;
	for (const path of suites) {
		let n;
		try {
			n = counterFor(path)(read(path));
		} catch (err) {
			errors.push(err instanceof Error ? err.message : String(err));
			continue;
		}
		const at = ZERO_DECLARATIONS_OK.findIndex((e) => e.path === path);
		if (n > 0) {
			if (at !== -1) {
				errors.push(
					`ZERO_DECLARATIONS_OK excuses ${path}, which now declares ${n} test(s). Delete ` +
						'the entry — an exemption that has outlived its subject is cover for nothing ' +
						'and hides the next one.',
				);
				usedExemptions.add(at);
			}
			counted++;
			continue;
		}
		if (at !== -1) {
			usedExemptions.add(at);
			continue;
		}
		errors.push(
			`${path} is named as a test suite and declares no test the census's own recompute ` +
				'command can see. Either it has stopped running anything — which reads exactly ' +
				'like a suite that passes, and which no count in the inventory would move — or it ' +
				'declares them through a wrapper the counters do not know, which is a wrong number ' +
				'wherever the census states one. Teach DART_TEST_WRAPPERS the wrapper, or declare ' +
				'the file in ZERO_DECLARATIONS_OK with the reason it holds none.',
		);
	}
	ZERO_DECLARATIONS_OK.forEach((e, i) => {
		if (usedExemptions.has(i)) return;
		errors.push(
			`the ZERO_DECLARATIONS_OK entry for ${e.path} matches no test file. Delete it rather ` +
				'than leaving a standing permission nobody re-reads.',
		);
	});

	return {
		errors,
		ok:
			errors.length === 0
				? [
						`${counted} of ${suites.length} suite(s) declare at least one test; ` +
							`${ZERO_DECLARATIONS_OK.length} declared empty with a reason`,
					]
				: [],
	};
}


// ---------------------------------------------------------------------------
// Claim 3: the census says what it undertakes to index, and the index has a
// floor under it.
// ---------------------------------------------------------------------------

/**
 * The scope statement the census has to carry, matched by phrase. A phrase
 * that matches NOTHING is a hard error rather than a pass — rule 6's shape in
 * `check_ci_diagnostics.mjs`, and for the same reason: a paragraph nobody
 * checks is a paragraph a sweep deletes.
 */
export const SCOPE_ANCHOR = /\*\*What this document indexes, and what it does not\.\*\*/;

/**
 * The floor under the INDEX, deliberately below what the census names today
 * (1,004 suites of 2,227 on 2026-09-08). It is not a target: retiring a suite
 * and its section is a legitimate drop of one, where a sweep that deletes
 * sections wholesale is the thing worth failing on. The same shape, and the
 * same reasoning, as MIN_TEST_FILES above.
 */
export const MIN_INDEXED_SUITES = 900;

/**
 * The suites the census names, resolved the way `check` resolves them: a
 * heading's or bullet's token, against the section's directory when the token
 * is a bare basename.
 *
 * @param {string} md the inventory document
 * @param {(pattern: string) => string[]} expand
 * @param {string[]} files every tracked path
 * @returns {{ named: Set<string>, suites: string[] }}
 */
export function indexedSuites(md, expand, files) {
	/** @type {Set<string>} */
	const named = new Set();
	for (const heading of censusHeadings(md)) {
		const dir = sectionDir(heading.claims);
		for (const claim of [...heading.claims, ...heading.bullets.map((b) => b.claim)]) {
			const token = claim.token.includes('/')
				? claim.token
				: dir
					? posix.join(dir, claim.token)
					: claim.token;
			for (const file of expand(token)) named.add(file);
		}
	}
	const suites = files.filter(
		(f) => TEST_FILE.test(f) || (f.startsWith(PGTAP_DIR) && f.endsWith('.sql')),
	);
	return { named: new Set(suites.filter((f) => named.has(f))), suites };
}

/**
 * Claim 3. The document states what it indexes, and the index has not been
 * gutted.
 *
 * The FIGURES in that statement are deliberately not compared against the
 * tree: a suite is added most weeks and the total would then have to be
 * retyped in a document nobody was otherwise touching, which is how a stated
 * number becomes a lie in the first place. What is enforced instead is that
 * the statement EXISTS, that the coverage is printed here on every run so a
 * reader who wants the live figure runs this rather than trusting prose, and
 * that the index cannot silently collapse (decisions § 1586).
 *
 * @param {string} md
 * @param {(pattern: string) => string[]} expand
 * @param {string[]} files
 * @returns {{ errors: string[], ok: string[] }}
 */
export function checkScope(md, expand, files) {
	/** @type {string[]} */
	const errors = [];
	/** @type {string[]} */
	const ok = [];
	if (!SCOPE_ANCHOR.test(md)) {
		errors.push(
			`the census holds no scope statement matching /${SCOPE_ANCHOR.source}/. It names a ` +
				'fraction of the repo\'s suites and says so in that paragraph; without it the next ' +
				'reader who counts re-files the gap, which is what happened before it was written ' +
				'(decisions § 1586).',
		);
	}
	const { named, suites } = indexedSuites(md, expand, files);
	if (named.size < MIN_INDEXED_SUITES) {
		errors.push(
			`the census names ${named.size} suite(s) and this guard's floor is ` +
				`${MIN_INDEXED_SUITES}. Either sections were deleted, or the token reader stopped ` +
				'resolving them — in which case every count above is being checked against an ' +
				'index nothing populates. Lower the floor deliberately if the shrink is real.',
		);
	}
	if (errors.length === 0) {
		ok.push(
			`the census states its scope and indexes ${named.size} of the ${suites.length} suite(s) ` +
				`the tree holds; the other ${suites.length - named.size} are covered by the ` +
				'zero-declaration rule instead',
		);
	}
	return { errors, ok };
}

/** @returns {string[]} every file git tracks, repo-relative */
function tracked() {
	return execFileSync('git', ['ls-files', '-z'], {
		cwd: ROOT,
		encoding: 'utf-8',
		maxBuffer: 64 * 1024 * 1024,
	})
		.split('\0')
		.filter(Boolean);
}

/**
 * A heading token -> the tracked files it names. A trailing `/` is a directory
 * prefix; `*` is a glob segment; anything else is one exact path.
 * @param {string[]} files
 * @returns {(token: string) => string[]}
 */
export function expander(files) {
	const set = new Set(files);
	return (token) => {
		if (token.endsWith('/')) return files.filter((f) => f.startsWith(token));
		if (!token.includes('*')) return set.has(token) ? [token] : [];
		return files.filter((f) => globRe(token).test(f));
	};
}

/**
 * A glob to a regex, with a doubled star spanning any number of directory
 * segments INCLUDING none: the internal/ Go token has to reach both
 * `internal/x_test.go` and `internal/livehub/x_test.go`, or the guard states a
 * total for a subtree it never walked.
 * @param {string} token
 * @returns {RegExp}
 */
export function globRe(token) {
	const segs = token.split('/');
	let out = '^';
	for (let i = 0; i < segs.length; i++) {
		const seg = segs[i];
		const last = i === segs.length - 1;
		if (seg === '**') {
			out += last ? '.*' : '(?:[^/]+/)*';
			continue;
		}
		out += seg.split('*').map(escapeRe).join('[^/]*');
		if (!last) out += '/';
	}
	return new RegExp(`${out}$`);
}

/** @param {string} s @returns {string} */
function escapeRe(s) {
	return s.replace(/[.+?^${}()|[\]\\]/g, '\\$&');
}

/** @param {string} path @returns {string} */
export function loadFile(path) {
	return readFileSync(join(ROOT, path), 'utf-8');
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const files = tracked();
	const md = loadFile(INVENTORY);
	const census = check(md, expander(files), loadFile);
	const population = checkPopulation(files, loadFile);
	const scope = checkScope(md, expander(files), files);
	const ok = [...census.ok, ...population.ok, ...scope.ok];
	const errors = [...census.errors, ...population.errors, ...scope.errors];
	for (const line of ok) console.log(`[OK] check_test_inventory_counts: ${line}`);
	for (const line of errors) console.error(`::error::check_test_inventory_counts: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_test_inventory_counts: ${errors.length} problem(s) across the census and the ` +
				'suites it does not name. The suite is the fact; the inventory is the transcription.',
		);
		process.exit(1);
	}
}
