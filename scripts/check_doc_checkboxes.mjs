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
// Four rules, each the mechanical form of one sentence in the documents:
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
//      it describes, so this script carries no list of exceptions.
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
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');

export const CONVENTIONS_PATH = join(REPO_ROOT, 'docs', 'architecture', 'conventions.md');
export const REVIEWS_README_PATH = join(REPO_ROOT, 'reviews', 'README.md');
/// The files a survey of open work actually reads. A `[~]` is invisible to
/// that survey, so it points at one of them for the half still open.
export const SURVEY_FILES = ['followups.md', 'roadmap.md'];

export const FROZEN_MARKER = '<!-- doc-checkbox-frozen -->';

export const OPEN_MARKER = '<!-- doc-checkbox-states -->';
export const CLOSE_MARKER = '<!-- /doc-checkbox-states -->';

/// The markers a `- \`[m]\` meaning` list declares, in document order. Both
/// homes write the vocabulary in that one shape, so one parser reads both.
export function readMarkerList(text) {
	return [...text.matchAll(/^[-*+] {1,3}`\[(.)\]`/gm)].map((m) => m[1]);
}

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

/// Every checkbox bullet in one document, with the whole bullet's text — a
/// bullet wraps over continuation lines, and the link rule reads all of it.
/// Fenced blocks are skipped: a `- [ ]` inside one is sample output, not a box.
export function checkboxesIn(text) {
	const lines = text.split('\n');
	const found = [];
	let fence = null;
	let open = null;

	const flush = () => {
		if (open) found.push(open);
		open = null;
	};

	for (const [index, line] of lines.entries()) {
		const fenceEdge = line.match(/^\s*(`{3,}|~{3,})/);
		if (fenceEdge) {
			const glyph = fenceEdge[1][0];
			if (fence === null) fence = glyph;
			else if (fence === glyph) fence = null;
			flush();
			continue;
		}
		if (fence !== null) continue;

		const box = line.match(/^(\s*)[-*+] \[(.)\]/);
		if (box) {
			flush();
			open = { line: index + 1, marker: box[2], indent: box[1].length, text: line };
			continue;
		}
		if (!open) continue;
		if (line.trim() === '' || /^\s*[-*+] /.test(line) || /^\s*#{1,6} /.test(line)) flush();
		else open.text += '\n' + line;
	}
	flush();
	return found;
}

export function trackedMarkdown() {
	return execFileSync('git', ['ls-files', '*.md'], { cwd: REPO_ROOT, encoding: 'utf-8' })
		.split('\n')
		.filter(Boolean);
}

/// A `[~]` box points at a survey file, as a link rather than a bare mention —
/// `reviews/README.md` § 2 asks for a link, and naming the file in prose is not
/// one.
export function linksSurvey(bulletText) {
	return SURVEY_FILES.some((name) =>
		new RegExp(`\\]\\([^)]*${name.replace('.', '\\.')}(?:#[^)]*)?\\)`).test(bulletText)
	);
}

export function auditDoc(relPath, text, documented) {
	const problems = [];
	const frozen = text.includes(FROZEN_MARKER);
	for (const box of checkboxesIn(text)) {
		if (!documented.includes(box.marker)) {
			problems.push(
				`${relPath}:${box.line} uses the checkbox marker \`[${box.marker}]\`, which no document defines. ` +
					`Use one of ${documented.map((m) => `\`[${m}]\``).join(' ')}, or document the new state in the ` +
					`${OPEN_MARKER} block first.`
			);
			continue;
		}
		if (box.marker === '~' && !frozen && !linksSurvey(box.text)) {
			problems.push(
				`${relPath}:${box.line} is a partial \`[~]\` box linking neither ${SURVEY_FILES.join(' nor ')}. ` +
					`The surveys of open work grep \`- [ ]\`, so the half of this item that is still open is ` +
					`reachable from nowhere. File the remaining work in one of those and link it — or, if nothing ` +
					`remains, tick the box.`
			);
		}
	}
	return problems;
}

export function run() {
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

	const problems = [];
	for (const rel of trackedMarkdown()) {
		problems.push(...auditDoc(rel, readFileSync(join(REPO_ROOT, rel), 'utf-8'), documented));
	}
	return problems;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
	let problems;
	try {
		problems = run();
	} catch (err) {
		console.error(err.message);
		process.exit(1);
	}
	if (problems.length > 0) {
		console.error(problems.join('\n'));
		process.exit(1);
	}
	console.log('doc checkboxes: every marker is documented and every [~] names its follow-up');
}
