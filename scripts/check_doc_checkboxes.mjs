#!/usr/bin/env node
// Guardrail: a Markdown checkbox in this repo is one of exactly three states,
// and the third one names where its unfinished half is tracked.
//
// The roadmap and follow-up surveys are built by grepping `- [ ]`. That
// instrument sees two of the three states actually in use, so every `- [~]`
// is invisible to it — issue #789 was assembled that way and missed the
// category whole, including work filed in no other place. The state also had
// no stated meaning outside `reviews/`, where `reviews/README.md` defines it
// as *deferred*, close to the opposite of the "built, not yet live" sense the
// docs tree had been using it in. `docs/custom_watch/roadmap.md` read it a
// third way again: its own § 101 rule keeps every box `[ ]` until
// bench-verified, and one line broke that while its neighbour, in the same
// build state, did not.
//
// Five rules, each the mechanical form of one sentence in the documents:
//
//   1. Exactly one `<!-- doc-checkbox-states -->` block, in
//      `docs/architecture/conventions.md`. That block lists the legal markers,
//      and this script READS it rather than restating it — the vocabulary has
//      one home, and it is the document.
//   2. `reviews/README.md` describes the same three markers for audit notes.
//      The two lists mean different things (shipped-ness vs audit lifecycle)
//      and legitimately live apart, so the guard holds them to the SET rather
//      than to the wording: adding a state to one forces it into the other.
//   3. Every checkbox in a tracked `*.md` uses a marker those lists define.
//   4. Every `[~]` box links one of the two files the surveys read —
//      `docs/product/followups.md` or `docs/product/roadmap.md` — so the half
//      that is still open is reachable as an ordinary `- [ ]`. This is the rule
//      `reviews/README.md` § 2 already states for a deferred finding, applied
//      to the tree the surveys walk. A file that is a dated snapshot rather
//      than a live list declares `<!-- doc-checkbox-frozen -->` and is held to
//      rule 3 only: `followups_archive.md` is a verbatim capture of the day it
//      was taken, and rewriting its boxes to satisfy a rule written afterwards
//      would destroy the one thing it is for. The declaration lives in the file
//      it describes, so this script carries no list of exceptions — on its own
//      LINE, because matching the marker in prose let two documents that merely
//      describe the mechanism exempt themselves (decisions § 774).
//   5. No document says two different things about one item. A box whose bold
//      lead title repeats in the same file under a DIFFERENT state is an entry
//      that outlived its own closure, and the surveys grep `- [ ]` — so the
//      stale open copy is counted as live work the ticked copy says is
//      finished. `followups.md` carried exactly that for two weeks, over the
//      round-15 pgtap debris item, and nothing looked. Frozen files are held to
//      rule 3 only, this rule included. Measured: one hit across the 666
//      bold-titled checkboxes in the tracked tree, and it is that one.
//
// Run: `node scripts/check_doc_checkboxes.mjs`
// CI:  the `parity-matrix` job in .github/workflows/ci.yml — the one job NOT
//      gated on `needs.changes.outputs.code`, because a docs edit is a
//      docs-only diff, every code-gated job skips it, and the CI gate counts a
//      skip as a pass. A guard for Markdown in a gated job would never run on
//      the PRs it polices.
// Unit tests: `node --test scripts/check_doc_checkboxes.test.mjs`

import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { dirname, join, normalize, posix, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const CONVENTIONS_PATH = join(REPO_ROOT, 'docs', 'architecture', 'conventions.md');
export const REVIEWS_README_PATH = join(REPO_ROOT, 'reviews', 'README.md');
/// The files a survey of open work actually reads. A `[~]` is invisible to
/// that survey, so it points at one of them for the half still open.
///
/// Repo-relative PATHS, not basenames. Matching the basename anywhere in a
/// link accepted `docs/custom_watch/roadmap.md` — a different document, which
/// no survey greps, and the one this guard's own header names as reading `[~]`
/// a third incompatible way. decisions § 774.
export const SURVEY_FILES = ['docs/product/followups.md', 'docs/product/roadmap.md'];

export const FROZEN_MARKER = '<!-- doc-checkbox-frozen -->';

export const OPEN_MARKER = '<!-- doc-checkbox-states -->';
export const CLOSE_MARKER = '<!-- /doc-checkbox-states -->';

/// The markers a `- \`[m]\` meaning` list declares, in document order. Both
/// homes write the vocabulary in that one shape, so one parser reads both.
/**
 * @param {string} text
 * @returns {string[]}
 */
export function readMarkerList(text) {
	return [...text.matchAll(/^[-*+] {1,3}`\[(.)\]`/gm)].map((m) => m[1]);
}

/**
 * @param {string} conventions
 * @returns {string[]}
 */
export function readDocumentedMarkers(conventions) {
	const opens = conventions.split(OPEN_MARKER).length - 1;
	const closes = conventions.split(CLOSE_MARKER).length - 1;
	if (opens !== 1 || closes !== 1) {
		throw new Error(
			`docs/architecture/conventions.md must carry exactly one ${OPEN_MARKER} … ${CLOSE_MARKER} block; ` +
				`found ${opens} open and ${closes} close. The checkbox vocabulary has one home.`
		);
	}
	const block = conventions.split(OPEN_MARKER)[1].split(CLOSE_MARKER)[0];
	const markers = readMarkerList(block);
	if (markers.length === 0) {
		throw new Error(
			`the ${OPEN_MARKER} block declares no markers. Each line reads "- \`[m]\` name — meaning".`
		);
	}
	return markers;
}

/// The document's lines with fenced blocks removed. A `- [ ]` inside one is
/// sample output, not a box, and a `<!-- doc-checkbox-frozen -->` inside one
/// is an illustration, not a declaration.
/**
 * @param {string} text
 * @returns {{ line: number, text: string }[]}
 */
export function unfencedLines(text) {
	/** @type {{ line: number, text: string }[]} */
	const out = [];
	/** @type {string | null} */
	let fence = null;
	text.split('\n').forEach((line, index) => {
		const edge = line.match(/^\s*(`{3,}|~{3,})/);
		if (edge) {
			const glyph = edge[1][0];
			if (fence === null) fence = glyph;
			else if (fence === glyph) fence = null;
			out.push({ line: index + 1, text: '' });
			return;
		}
		out.push({ line: index + 1, text: fence === null ? line : '' });
	});
	return out;
}

/// A dated snapshot exempts itself from the link rule by declaring the marker
/// ON ITS OWN LINE. `text.includes(...)` matched it in prose too, so any
/// document that merely DESCRIBES the mechanism exempted itself — which
/// `docs/architecture/conventions.md` and `docs/architecture/decisions.md`
/// both did, silently, from the day the rule shipped. decisions § 774.
/**
 * @param {string} text
 * @returns {boolean}
 */
export function declaresFrozen(text) {
	return unfencedLines(text).some((l) => l.text.trim() === FROZEN_MARKER);
}

/// Every checkbox bullet in one document, with the whole bullet's text — a
/// bullet wraps over continuation lines, and the link rule reads all of it.
/// A more-indented CHILD bullet is part of it too: flushing on any bullet at
/// all meant a `[~]` whose follow-up link sat on a sub-bullet was reported as
/// linking nothing (decisions § 774).
/**
 * @typedef {{ line: number, marker: string, indent: number, text: string }} Checkbox
 */

/// The bold lead a survey entry opens with, which is the handle a reader (and
/// a `- [ ]` grep's output) identifies the item by. Null for a box that has
/// none — most boxes outside the two survey files.
/**
 * @param {string} bulletText
 * @returns {string | null}
 */
export function leadTitle(bulletText) {
	const m = bulletText.match(/^\s*[-*+] \[.\]\s*\*\*(.+?)\*\*/s);
	return m === null ? null : m[1].replace(/\s+/g, ' ').trim();
}
/**
 * @param {string} text
 * @returns {Checkbox[]}
 */
export function checkboxesIn(text) {
	/** @type {Checkbox[]} */
	const found = [];
	/** @type {Checkbox | null} */
	let open = null;

	const flush = () => {
		if (open) found.push(open);
		open = null;
	};

	for (const { line: number, text: line } of unfencedLines(text)) {
		const box = line.match(/^(\s*)[-*+] \[(.)\]/);
		if (box) {
			flush();
			open = { line: number, marker: box[2], indent: box[1].length, text: line };
			continue;
		}
		if (!open) continue;
		if (line.trim() === '' || /^\s*#{1,6} /.test(line)) {
			flush();
			continue;
		}
		const bullet = line.match(/^(\s*)[-*+] /);
		if (bullet && bullet[1].length <= open.indent) {
			flush();
			continue;
		}
		open.text += '\n' + line;
	}
	flush();
	return found;
}

/** @returns {string[]} Repo-relative paths of every tracked `*.md`. */
export function trackedMarkdown() {
	return execFileSync('git', ['ls-files', '*.md'], { cwd: REPO_ROOT, encoding: 'utf-8' })
		.split('\n')
		.filter(Boolean);
}

/// A `[~]` box points at a survey file, as a link rather than a bare mention —
/// `reviews/README.md` § 2 asks for a link, and naming the file in prose is not
/// one. The href is RESOLVED against the linking document, so the rule holds
/// the box to the two files the surveys read rather than to anything whose
/// name happens to end the same way.
/**
 * @param {string} bulletText
 * @param {string} relPath the linking document, repo-relative
 */
export function linksSurvey(bulletText, relPath) {
	const dir = dirname(relPath);
	for (const link of bulletText.matchAll(/\]\(\s*<?([^)\s>]+)>?(?:\s+["'(][^)]*)?\)/g)) {
		const href = link[1].split('#')[0];
		// A scheme or a site-absolute path is not a repo file this resolves.
		if (!href || /^[A-Za-z][A-Za-z0-9+.-]*:/.test(href) || href.startsWith('/')) continue;
		const resolved = normalize(join(dir, decodeURIComponent(href))).split(sep).join(posix.sep);
		if (SURVEY_FILES.includes(resolved)) return true;
	}
	return false;
}

/**
 * @param {string} relPath
 * @param {string} text
 * @param {readonly string[]} documented
 * @returns {string[]}
 */
export function auditDoc(relPath, text, documented) {
	const problems = [];
	const frozen = declaresFrozen(text);
	/** @type {Map<string, Checkbox[]>} */
	const byTitle = new Map();

	for (const box of checkboxesIn(text)) {
		if (!documented.includes(box.marker)) {
			problems.push(
				`${relPath}:${box.line} uses the checkbox marker \`[${box.marker}]\`, which no document defines. ` +
					`Use one of ${documented.map((m) => `\`[${m}]\``).join(' ')}, or document the new state in the ` +
					`${OPEN_MARKER} block first.`
			);
			continue;
		}
		if (box.marker === '~' && !frozen && !linksSurvey(box.text, relPath)) {
			problems.push(
				`${relPath}:${box.line} is a partial \`[~]\` box linking neither ${SURVEY_FILES.join(' nor ')}. ` +
					`The surveys of open work grep \`- [ ]\`, so the half of this item that is still open is ` +
					`reachable from nowhere. File the remaining work in one of those and link it — or, if nothing ` +
					`remains, tick the box.`
			);
		}
		const title = leadTitle(box.text);
		if (title === null || frozen) continue;
		const group = byTitle.get(title) ?? [];
		group.push(box);
		byTitle.set(title, group);
	}

	for (const [title, group] of byTitle) {
		const states = [...new Set(group.map((b) => b.marker))];
		if (states.length < 2) continue;
		problems.push(
			`${relPath} states two different things about "${title}": lines ` +
				`${group.map((b) => `${b.line} \`[${b.marker}]\``).join(', ')}. One entry outlived its ` +
				`own closure, and the surveys grep \`- [ ]\` — so the open copy is counted as ` +
				`live work that the ticked copy says is finished. Delete the stale one.`
		);
	}

	return problems;
}

/// `files` is overridable so the walk's own floor below can be exercised: a
/// rule that only fires over a state the real repo never reaches is a rule
/// nothing tests.
/**
 * @param {readonly string[]} [files]
 * @returns {string[]}
 */
export function run(files = trackedMarkdown()) {
	const documented = readDocumentedMarkers(readFileSync(CONVENTIONS_PATH, 'utf-8'));

	const reviewsMarkers = readMarkerList(readFileSync(REVIEWS_README_PATH, 'utf-8'));
	const drifted =
		[...new Set(documented)].sort().join(' ') !== [...new Set(reviewsMarkers)].sort().join(' ');
	if (drifted) {
		throw new Error(
			`the checkbox states differ between docs/architecture/conventions.md ` +
				`(${documented.map((m) => `[${m}]`).join(' ')}) and reviews/README.md ` +
				`(${reviewsMarkers.map((m) => `[${m}]`).join(' ')}). The two describe different meanings on ` +
				`purpose, but they describe the same set of markers — add the state to both, or to neither.`
		);
	}

	if (files.length === 0) {
		throw new Error(
			`no tracked *.md files to audit: \`git ls-files '*.md'\` came back empty. Rules 3 and 4 would ` +
				`then run over no document at all and this guard would report the tree clean. Run it from a ` +
				`checkout with history, or repair trackedMarkdown().`
		);
	}

	const problems = [];
	for (const rel of files) {
		problems.push(...auditDoc(rel, readFileSync(join(REPO_ROOT, rel), 'utf-8'), documented));
	}
	return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	let problems;
	try {
		problems = run();
	} catch (err) {
		console.error(err instanceof Error ? err.message : String(err));
		process.exit(1);
	}
	if (problems.length > 0) {
		console.error(problems.join('\n'));
		process.exit(1);
	}
	console.log('doc checkboxes: every marker is documented and every [~] names its follow-up');
}
