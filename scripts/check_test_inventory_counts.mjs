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
 * How a declaration is counted, per file kind. Each is the document's own
 * prescribed recompute command, line-anchored the way `grep -cE` applies it.
 * @type {Array<{ id: string, match: (path: string) => boolean, count: (src: string) => number }>}
 */
export const COUNTERS = [
	{
		id: 'dart',
		match: (p) => p.endsWith('.dart'),
		count: (src) => lineMatches(src, /^\s*(?:test|testWidgets)\(/),
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
	const { errors, ok } = check(loadFile(INVENTORY), expander(tracked()), loadFile);
	for (const line of ok) console.log(`[OK] check_test_inventory_counts: ${line}`);
	for (const line of errors) console.error(`::error::check_test_inventory_counts: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_test_inventory_counts: ${errors.length} census disagreement(s). The suite ` +
				'is the fact; the inventory is the transcription.',
		);
		process.exit(1);
	}
}
