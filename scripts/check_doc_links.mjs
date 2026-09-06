#!/usr/bin/env node
// Guardrail: every relative markdown link in the repo resolves — the file on
// disk, and the heading inside it.
//
// Why this exists: decisions.md § 1258. Nothing in CI had ever read a prose
// link, and 261 of 4,085 did not resolve. The largest class was the in-file
// citation idiom `[§ 739](#739)`, which had NEVER resolved: GitHub's slug for
// `## 739. Title...` is `739-title...`, not `739`. The second class is the one
// that makes a checker worth having — 14 links that resolved when they were
// written and stopped when someone reworded the heading, silently, with the
// link still rendering as a link.
//
// **The slugger is the whole correctness surface.** A checker whose slug
// algorithm is even slightly wrong reports dead links on a clean tree, and is
// then switched off. The measurement this guard was built from was first run
// with a slugger that collapsed a RUN of spaces to one hyphen; it reported 30
// false positives. GitHub (github-slugger) emits one hyphen PER space, after
// deleting the punctuation between them, so `## The erase (§ 378)` is
// `the-erase--378` — two hyphens, because `(§ ` leaves two spaces behind.
// `slugFor` reproduces that, and `slug.test` pins that exact heading.
//
// Two directions, so the guard cannot read as complete while checking little:
//
//   1. **Resolution.** Every relative link target must exist on disk, and a
//      fragment against a markdown target must name a heading slug or an
//      explicit HTML anchor in it.
//   2. **Census.** The file set is `git ls-files '*.md'` less `SKIPPED_TREES`,
//      so a markdown file added anywhere is read without anyone registering
//      it, and a link inside a fenced block or a code span is not a link.
//      Every `KNOWN_UNRESOLVABLE` exemption must match at least once, so a
//      standing permission cannot outlive the line it excuses.
//
// Not checked, deliberately: an absolute URL (this guard makes no network
// call), a site-absolute `/learn/...` target (an app route, not a repo path),
// and a fragment on a NON-markdown target (`#L12` on a source file is
// GitHub-web syntax with no on-disk meaning).
//
// Run: `node scripts/check_doc_links.mjs`
// CI:  the `workflow-lint` job in .github/workflows/ci.yml.
// Unit tests: `node --test scripts/check_doc_links.test.mjs`

import { execFileSync } from 'node:child_process';
import { existsSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, normalize, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

// Overridable so the whole script — exit code and all — can be pointed at a
// mutated copy of the tree, which is how a guard is shown to fail.
export const ROOT = process.env.DOC_LINK_ROOT ?? REPO_ROOT;

/**
 * Trees whose markdown is not repo-relative prose. Each is a PREFIX; a file
 * under one is not read at all.
 */
export const SKIPPED_TREES = [
	// Vendored / generated trees git does not track are already absent from the
	// census, so this list only has to name tracked ones.
	'node_modules/',
];

/**
 * Link targets that cannot resolve on disk and are not defects. Keyed on file
 * plus the exact target text; every entry must match at least once.
 * @type {Array<{ file: string, target: string, reason: string }>}
 */
export const KNOWN_UNRESOLVABLE = [
	{
		file: 'SUPPORT.md',
		target: '../../issues',
		reason:
			'A github.com-relative link: from `owner/repo/blob/main/SUPPORT.md` it walks ' +
			'up to `owner/repo/issues`. It has no on-disk meaning and GitHub is where ' +
			'this file is read.',
	},
];

// ---------------------------------------------------------------------------
// GitHub heading slugs.
// ---------------------------------------------------------------------------

/**
 * A character github-slugger KEEPS: a letter, a number, a combining mark, an
 * underscore, an ASCII hyphen, or an ASCII space (which becomes a hyphen in
 * the next step). Everything else — punctuation, `§`, an em dash, an arrow, a
 * non-breaking space — is DELETED, leaving the spaces around it behind.
 */
const KEPT = /[\p{L}\p{N}\p{M}_\- ]/u;

/**
 * GitHub's heading slug, per github-slugger: lowercase, delete every character
 * outside `KEPT`, then map each remaining space to one hyphen. No trim, and no
 * collapsing of hyphen runs — both are what a hand-rolled slugger gets wrong.
 * @param {string} heading the heading text, markdown markup included
 * @returns {string}
 */
export function slugFor(heading) {
	let out = '';
	for (const ch of heading.toLowerCase()) {
		if (!KEPT.test(ch)) continue;
		out += ch === ' ' ? '-' : ch;
	}
	return out;
}

/**
 * Blank out fenced code blocks and inline code spans, replacing them with
 * spaces so every offset still names the same place. A link inside backticks
 * is a link the reader cannot click.
 * @param {string} md
 * @returns {string}
 */
export function blankCode(md) {
	const lines = md.split('\n');
	/** @type {string[]} */
	const out = [];
	/** @type {string | null} */
	let fence = null;
	for (const line of lines) {
		const opener = line.match(/^\s{0,3}(`{3,}|~{3,})/);
		if (fence === null && opener) {
			fence = opener[1][0].repeat(opener[1].length);
			out.push(' '.repeat(line.length));
			continue;
		}
		if (fence !== null) {
			const closer = line.match(/^\s{0,3}(`{3,}|~{3,})\s*$/);
			if (closer && closer[1][0] === fence[0] && closer[1].length >= fence.length) fence = null;
			out.push(' '.repeat(line.length));
			continue;
		}
		out.push(blankSpans(line));
	}
	return out.join('\n');
}

/**
 * Blank inline code spans on one line. A span opens on a run of N backticks
 * and closes on the next run of exactly N.
 * @param {string} line
 * @returns {string}
 */
function blankSpans(line) {
	let out = '';
	let i = 0;
	while (i < line.length) {
		if (line[i] !== '`') {
			out += line[i];
			i++;
			continue;
		}
		let n = 0;
		while (line[i + n] === '`') n++;
		const close = findRun(line, i + n, n);
		if (close === -1) {
			out += line.slice(i, i + n);
			i += n;
			continue;
		}
		out += ' '.repeat(close + n - i);
		i = close + n;
	}
	return out;
}

/**
 * @param {string} line @param {number} from @param {number} n
 * @returns {number} index of the next run of EXACTLY n backticks, or -1
 */
function findRun(line, from, n) {
	for (let i = from; i < line.length; i++) {
		if (line[i] !== '`') continue;
		let len = 0;
		while (line[i + len] === '`') len++;
		if (len === n) return i;
		i += len - 1;
	}
	return -1;
}

/**
 * Heading slugs of a markdown document, in GitHub's order, with GitHub's
 * duplicate suffixes (`-1`, `-2`, ...). Headings inside a fenced block are not
 * headings.
 * @param {string} md
 * @returns {Set<string>}
 */
export function headingSlugs(md) {
	const lines = blankCodeBlocksOnly(md).split('\n');
	/** @type {Map<string, number>} */
	const seen = new Map();
	/** @type {Set<string>} */
	const slugs = new Set();
	for (const line of lines) {
		const m = line.match(/^\s{0,3}#{1,6}\s+(.*?)\s*#*\s*$/);
		if (!m) continue;
		const base = slugFor(stripInlineMarkup(m[1]));
		const n = seen.get(base) ?? 0;
		seen.set(base, n + 1);
		slugs.add(n === 0 ? base : `${base}-${n}`);
	}
	return slugs;
}

/**
 * Fenced blocks only — a heading's own backticks are part of its text and must
 * survive, where a heading INSIDE a fence is not a heading at all.
 * @param {string} md
 * @returns {string}
 */
function blankCodeBlocksOnly(md) {
	/** @type {string[]} */
	const out = [];
	/** @type {string | null} */
	let fence = null;
	for (const line of md.split('\n')) {
		const opener = line.match(/^\s{0,3}(`{3,}|~{3,})/);
		if (fence === null && opener) {
			fence = opener[1];
			out.push('');
			continue;
		}
		if (fence !== null) {
			const closer = line.match(/^\s{0,3}(`{3,}|~{3,})\s*$/);
			if (closer && closer[1][0] === fence[0] && closer[1].length >= fence.length) fence = null;
			out.push('');
			continue;
		}
		out.push(line);
	}
	return out.join('\n');
}

/**
 * Strip the inline markup GitHub renders away before slugging: link syntax
 * (the TEXT survives, the target does not), emphasis markers and backticks.
 * `## [§ 39](#x) and **bold** and \`code\`` slugs off `§ 39 and bold and code`.
 *
 * An underscore is stripped ONLY in the word-boundary `_emphasis_` form GFM
 * actually italicises. An intraword one is a literal — dropping every `_`
 * turns `## 39. mobile_android and mobile_ios ...` into `39-mobileandroid-...`
 * and reports the 24 links that name the real slug as dead, which is precisely
 * the false-positive failure mode this guard exists to avoid.
 * @param {string} text
 * @returns {string}
 */
export function stripInlineMarkup(text) {
	return text
		.replace(/!\[([^\]]*)\]\([^)]*\)/g, '$1')
		.replace(/\[([^\]]*)\]\([^)]*\)/g, '$1')
		.replace(/[`*~]/g, '')
		.replace(/(^|[^\w])__?([^_]+)__?(?![\w])/g, '$1$2');
}

/**
 * Explicit HTML anchors a fragment may also name. GitHub rewrites the `id` to
 * `user-content-<id>` and its own fragment JS strips that prefix back off, so
 * `<a id="x">` is reachable as `#x`.
 * @param {string} md
 * @returns {Set<string>}
 */
export function htmlAnchors(md) {
	/** @type {Set<string>} */
	const out = new Set();
	for (const m of blankCodeBlocksOnly(md).matchAll(/<a\b[^>]*\b(?:id|name)\s*=\s*"([^"]+)"/gi)) {
		out.add(m[1]);
	}
	return out;
}

// ---------------------------------------------------------------------------
// Links.
// ---------------------------------------------------------------------------

/**
 * @typedef {object} Link
 * @property {string} target the raw target text, fragment included
 * @property {number} line 1-based
 */

/**
 * Inline links `[text](target)` and reference definitions `[label]: target`,
 * outside code.
 * @param {string} md
 * @returns {Link[]}
 */
export function linksIn(md) {
	const body = blankCode(md);
	/** @type {Link[]} */
	const out = [];
	const lineAt = lineIndexer(body);
	const inline = /\[(?:[^\][]|\[[^\][]*\])*\]\(\s*(<[^>]*>|[^()\s]*)(?:\s+(?:"[^"]*"|'[^']*'))?\s*\)/g;
	for (const m of body.matchAll(inline)) {
		const raw = m[1].startsWith('<') ? m[1].slice(1, -1) : m[1];
		if (raw !== '') out.push({ target: raw, line: lineAt(m.index) });
	}
	const refdef = /^\s{0,3}\[([^\]]+)\]:\s*(<[^>]*>|\S+)/gm;
	for (const m of body.matchAll(refdef)) {
		const raw = m[2].startsWith('<') ? m[2].slice(1, -1) : m[2];
		out.push({ target: raw, line: lineAt(m.index) });
	}
	return out;
}

/**
 * @param {string} body
 * @returns {(offset: number) => number}
 */
function lineIndexer(body) {
	/** @type {number[]} */
	const starts = [0];
	for (let i = 0; i < body.length; i++) if (body[i] === '\n') starts.push(i + 1);
	return (offset) => {
		let lo = 0;
		let hi = starts.length - 1;
		while (lo < hi) {
			const mid = (lo + hi + 1) >> 1;
			if (starts[mid] <= offset) lo = mid;
			else hi = mid - 1;
		}
		return lo + 1;
	};
}

/**
 * Whether a target is one this guard resolves at all.
 * @param {string} target
 * @returns {boolean}
 */
export function isRepoRelative(target) {
	if (target === '') return false;
	if (/^[a-zA-Z][a-zA-Z0-9+.-]*:/.test(target)) return false;
	if (target.startsWith('//')) return false;
	if (target.startsWith('/')) return false;
	return true;
}

// ---------------------------------------------------------------------------
// The check.
// ---------------------------------------------------------------------------

/**
 * @param {string[]} files repo-relative markdown paths
 * @param {(path: string) => string} read repo-relative -> content
 * @param {(path: string) => boolean} exists repo-relative -> on disk
 * @param {Array<{ file: string, target: string, reason: string }>} [exemptions]
 * @returns {{ errors: string[], ok: string[] }}
 */
export function check(files, read, exists, exemptions = KNOWN_UNRESOLVABLE) {
	/** @type {string[]} */
	const errors = [];
	/** @type {Set<number>} */
	const usedExemptions = new Set();

	/** @type {Map<string, Set<string>>} path -> heading slugs + html anchors */
	const anchorCache = new Map();
	/** @param {string} path @returns {Set<string>} */
	const anchorsOf = (path) => {
		const hit = anchorCache.get(path);
		if (hit) return hit;
		const md = read(path);
		const set = new Set([...headingSlugs(md), ...htmlAnchors(md)]);
		anchorCache.set(path, set);
		return set;
	};

	let checked = 0;
	for (const file of files) {
		const md = read(file);
		const dir = dirname(file);
		for (const { target, line } of linksIn(md)) {
			if (!isRepoRelative(target)) continue;
			const exemptAt = exemptions.findIndex((e) => e.file === file && e.target === target);
			if (exemptAt !== -1) {
				usedExemptions.add(exemptAt);
				continue;
			}
			checked++;
			const hash = target.indexOf('#');
			const rawPath = hash === -1 ? target : target.slice(0, hash);
			const fragment = hash === -1 ? '' : decodeURIComponent(target.slice(hash + 1));
			const path = rawPath === '' ? file : normalize(join(dir, decodeURIComponent(rawPath)));
			const where = `${file}:${line}`;

			if (path.startsWith('..')) {
				errors.push(`${where}: \`${target}\` leaves the repository.`);
				continue;
			}
			if (!exists(path)) {
				errors.push(
					`${where}: \`${target}\` names ${path}, which is not in the repository.`,
				);
				continue;
			}
			if (fragment === '') continue;
			if (!path.endsWith('.md')) continue;

			if (anchorsOf(path).has(fragment)) continue;
			errors.push(
				`${where}: \`${target}\` names no heading in ${path}. ${adviseFragment(fragment, path, read)}`,
			);
		}
	}

	exemptions.forEach((e, i) => {
		if (usedExemptions.has(i)) return;
		errors.push(
			`the KNOWN_UNRESOLVABLE entry for \`${e.target}\` in ${e.file} matches nothing. ` +
				'Delete it rather than leaving a standing permission nobody re-reads.',
		);
	});

	return {
		errors,
		ok:
			errors.length === 0
				? [`${checked} relative link(s) across ${files.length} markdown file(s) resolve`]
				: [],
	};
}

/**
 * The correct slug is derivable whenever the fragment OPENS with the number of
 * a numbered heading — which is every `§ N` citation, dead because it is bare
 * and dead because the heading was reworded alike. Naming the replacement is
 * what makes 263 links maintainable: the failure is a copy-paste, not a hunt.
 * @param {string} fragment @param {string} path @param {(p: string) => string} read
 * @returns {string}
 */
export function adviseFragment(fragment, path, read) {
	const n = fragment.match(/^(\d+)(?:-|$)/);
	const generic = 'The heading was reworded; re-slug the link against its current text.';
	if (!n) return generic;
	const heading = blankCodeBlocksOnly(read(path))
		.split('\n')
		.find((l) => new RegExp(`^\\s{0,3}#{1,6}\\s+${n[1]}\\.\\s`).test(l));
	if (!heading) return `No heading numbered ${n[1]} exists in ${path}.`;
	const slug = slugFor(stripInlineMarkup(heading.replace(/^\s{0,3}#{1,6}\s+/, '')));
	if (slug === fragment) return generic;
	return `Write \`#${slug}\`.`;
}

// ---------------------------------------------------------------------------

/** @returns {string[]} every tracked markdown file, less `SKIPPED_TREES` */
export function loadFiles() {
	const listed = execFileSync('git', ['ls-files', '-z', '*.md'], {
		cwd: ROOT,
		encoding: 'utf-8',
		maxBuffer: 32 * 1024 * 1024,
	})
		.split('\0')
		.filter(Boolean);
	if (listed.length === 0) {
		throw new Error(
			'check_doc_links: `git ls-files` returned no markdown at all. A guard that ' +
				'read nothing must not report a clean tree.',
		);
	}
	return listed.filter((f) => !SKIPPED_TREES.some((t) => f.startsWith(t))).sort();
}

/** @param {string} path @returns {string} */
export function loadFile(path) {
	return readFileSync(join(ROOT, path), 'utf-8');
}

/** @param {string} path @returns {boolean} */
export function onDisk(path) {
	const full = resolve(ROOT, path);
	if (relative(ROOT, full).startsWith('..')) return false;
	if (!existsSync(full)) return false;
	// A link to a directory resolves on GitHub; a link to a file must be a file.
	return statSync(full).isFile() || statSync(full).isDirectory();
}

const invokedDirectly = process.argv[1] && import.meta.url === `file://${process.argv[1]}`;
if (invokedDirectly) {
	const { errors, ok } = check(loadFiles(), loadFile, onDisk);
	for (const line of ok) console.log(`[OK] check_doc_links: ${line}`);
	for (const line of errors) console.error(`::error::check_doc_links: ${line}`);
	if (errors.length > 0) {
		console.error(
			`\ncheck_doc_links: ${errors.length} link(s) do not resolve. A link that renders ` +
				'as a link and goes nowhere is worse than plain text.',
		);
		process.exit(1);
	}
}
