// Unit tests for scripts/check_doc_checkboxes.mjs.
//
// Run: `node --test scripts/check_doc_checkboxes.test.mjs`
//
// Most cases run the pure functions over miniature in-memory documents, so
// each breaks exactly one thing. The last two run the real tree: one asserts
// the committed docs are clean, the other plants a violating document in a
// throwaway directory and asserts the auditor reports it. The plant lives in
// `os.tmpdir()` and never in a tree any other guard walks — a probe that
// writes into `src/lib` and deletes it again makes concurrent scanners ENOENT
// on a file they have just listed.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

import {
	auditDoc,
	checkboxesIn,
	CONVENTIONS_PATH,
	declaresFrozen,
	FROZEN_MARKER,
	linksSurvey,
	readDocumentedMarkers,
	readMarkerList,
	REVIEWS_README_PATH,
	run,
	SURVEY_FILES,
	OPEN_MARKER,
	CLOSE_MARKER,
} from './check_doc_checkboxes.mjs';

const STATES = ['- `[ ]` open — none of it has shipped', '- `[x]` done — all of it', '- `[~]` partial — some'].join('\n');
const CONVENTIONS = `## Doc checkboxes\n\n${OPEN_MARKER}\n\n${STATES}\n\n${CLOSE_MARKER}\n`;
const DOCUMENTED = [' ', 'x', '~'];

test('the marker list parser reads both homes in the one shape they share', () => {
	assert.deepEqual(readMarkerList(STATES), [' ', 'x', '~']);
	assert.deepEqual(readDocumentedMarkers(CONVENTIONS), [' ', 'x', '~']);
});

test('the marker vocabulary has exactly one home', () => {
	assert.throws(() => readDocumentedMarkers('no block here'), /exactly one/);
	assert.throws(() => readDocumentedMarkers(CONVENTIONS + CONVENTIONS), /exactly one/);
	assert.throws(
		() => readDocumentedMarkers(`${OPEN_MARKER}\n\nprose, no markers\n\n${CLOSE_MARKER}`),
		/declares no markers/
	);
});

test('a checkbox carries its whole bullet, so the link rule reads continuation lines', () => {
	const boxes = checkboxesIn(['- [~] first line', '  wrapped onto a second', '', '- [x] done'].join('\n'));
	assert.equal(boxes.length, 2);
	assert.equal(boxes[0].marker, '~');
	assert.equal(boxes[0].line, 1);
	assert.match(boxes[0].text, /wrapped onto a second/);
	assert.equal(boxes[1].marker, 'x');
	assert.equal(boxes[1].line, 4);
});

test('a checkbox inside a fenced block is sample output, not a box', () => {
	const doc = ['```', '- [ ] [Severity] file:line — <description>', '```', '- [x] a real one'].join('\n');
	assert.deepEqual(
		checkboxesIn(doc).map((b) => b.marker),
		['x']
	);
	assert.deepEqual(checkboxesIn(['~~~', '- [?] tilde-fenced sample', '~~~'].join('\n')), []);
});

test('an undocumented marker is reported wherever it appears', () => {
	const problems = auditDoc('docs/x.md', '- [?] a fourth state\n', DOCUMENTED);
	assert.equal(problems.length, 1);
	assert.match(problems[0], /docs\/x\.md:1/);
	assert.match(problems[0], /`\[\?\]`, which no document defines/);
});

test('a partial box is held to a link, not to a prose mention of the filename', () => {
	const from = 'docs/backend/x.md';
	assert.equal(linksSurvey('tracked in followups.md, honest', from), false);
	assert.equal(linksSurvey('see [it](../product/followups.md)', from), true);
	assert.equal(linksSurvey('see [it](../product/followups.md#anchor)', from), true);
	assert.equal(linksSurvey('see [it](../product/roadmap.md)', from), true);
	// followups_archive.md contains "followups" but is not a survey file.
	assert.equal(linksSurvey('see [it](../product/followups_archive.md)', from), false);
	assert.equal(linksSurvey('see [it](followups.md)', 'docs/product/x.md'), true);

	assert.equal(auditDoc(from, '- [~] built, not live\n', DOCUMENTED).length, 1);
	assert.match(auditDoc(from, '- [~] built\n', DOCUMENTED)[0], new RegExp(SURVEY_FILES[0]));
	assert.deepEqual(
		auditDoc(from, '- [~] built ([rest](../product/followups.md))\n', DOCUMENTED),
		[],
	);
});

// The href is resolved against the linking document, so the rule holds a box
// to the two files the surveys read. Matching the BASENAME anywhere accepted
// docs/custom_watch/roadmap.md — a different document, which no survey greps,
// and the one this guard's own header names as reading `[~]` a third way.
// decisions § 774.
test('a link to the watch roadmap does not satisfy the survey rule', () => {
	assert.equal(linksSurvey('see [it](roadmap.md)', 'docs/custom_watch/x.md'), false);
	assert.equal(linksSurvey('see [it](../custom_watch/roadmap.md)', 'docs/product/x.md'), false);
	assert.equal(
		auditDoc('docs/custom_watch/x.md', '- [~] built ([rest](roadmap.md))\n', DOCUMENTED).length,
		1,
	);
});

test('a follow-up link on a child bullet belongs to the box above it', () => {
	// Flushing on any bullet at all meant a `[~]` whose link sat on a
	// sub-bullet was reported as linking nothing. A SIBLING bullet still ends
	// the box, and a nested checkbox is still its own.
	const nested = '- [~] built, not live\n  - the open half is [here](../product/followups.md)\n';
	assert.deepEqual(auditDoc('docs/backend/x.md', nested, DOCUMENTED), []);

	const sibling = '- [~] built, not live\n- unrelated [here](../product/followups.md)\n';
	assert.equal(auditDoc('docs/backend/x.md', sibling, DOCUMENTED).length, 1);

	const child = '- [x] done\n  - [~] and a nested partial\n';
	assert.deepEqual(
		checkboxesIn(child).map((b) => [b.line, b.marker, b.indent]),
		[
			[1, 'x', 0],
			[2, '~', 2],
		],
	);
});

test('the frozen declaration has to be a declaration, not a mention', () => {
	const box = '- [~] built, tracked nowhere\n';
	assert.equal(declaresFrozen(`${FROZEN_MARKER}\n\n${box}`), true);
	assert.equal(declaresFrozen(`A doc says so with \`${FROZEN_MARKER}\`.\n\n${box}`), false);
	assert.equal(declaresFrozen('```\n' + FROZEN_MARKER + '\n```\n'), false);

	assert.equal(auditDoc('docs/x.md', `Written as \`${FROZEN_MARKER}\`.\n\n${box}`, DOCUMENTED).length, 1);
});

// The rule and its measurement: one hit across the 666 bold-titled checkboxes
// in the tracked tree, and it was a closed followups.md item whose pre-closure
// copy had been counted as live work for two weeks. decisions § 774.
test('one file saying two different things about one item is reported', () => {
	const doc = [
		'- [x] **A thing.** Closed 2026-08-26.',
		'- [ ] **A thing.** The original filing, left behind.',
		'',
	].join('\n');
	const problems = auditDoc('docs/product/followups.md', doc, DOCUMENTED);
	assert.equal(problems.length, 1);
	assert.match(problems[0], /states two different things about "A thing\."/);
	assert.match(problems[0], /lines 1 `\[x\]`, 2 `\[ \]`/);

	// Same state twice is redundancy, not a contradiction, and no rule here.
	const same = '- [x] **A thing.** one\n- [x] **A thing.** two\n';
	assert.deepEqual(auditDoc('docs/product/followups.md', same, DOCUMENTED), []);

	// A frozen snapshot is history; rule 3 only.
	const frozen = `${FROZEN_MARKER}\n\n${doc}`;
	assert.deepEqual(auditDoc('docs/product/followups_archive.md', frozen, DOCUMENTED), []);
});

test('a frozen snapshot keeps the vocabulary but is exempt from the link', () => {
	const frozen = `${FROZEN_MARKER}\n\n- [~] captured as it stood\n`;
	assert.deepEqual(auditDoc('archive.md', frozen, DOCUMENTED), []);

	const bad = `${FROZEN_MARKER}\n\n- [?] a fourth state\n`;
	assert.equal(auditDoc('archive.md', bad, DOCUMENTED).length, 1);
});

test('the two documented homes agree on the set of markers', () => {
	const conventions = readDocumentedMarkers(readFileSync(CONVENTIONS_PATH, 'utf-8'));
	const reviews = readMarkerList(readFileSync(REVIEWS_README_PATH, 'utf-8'));
	assert.deepEqual([...new Set(conventions)].sort(), [...new Set(reviews)].sort());
	assert.deepEqual([...new Set(conventions)].sort(), [' ', 'x', '~']);
});

test('the committed docs pass', () => {
	assert.deepEqual(run(), []);
});

// The floor under the walk itself. `git ls-files` coming back empty takes every
// rule above over nothing and reports the tree clean — the shape of a guard
// that has quietly stopped guarding. Both sibling guards in this directory
// refuse that state (`Parsed no GATT rows`, `no failure()-conditioned steps`);
// this one used to pass it.
test('a walk over no documents is refused rather than reported clean', () => {
	assert.throws(() => run([]), /came back empty/);
});

test('the walk reads exactly the documents it is handed', () => {
	assert.throws(() => run(['docs/no-such-file.md']), /ENOENT/);
});

test('a planted violation is reported, and stops being reported once removed', () => {
	const dir = mkdtempSync(join(tmpdir(), 'doc-checkbox-probe-'));
	try {
		const path = join(dir, 'planted.md');
		writeFileSync(path, '- [~] built but not live, tracked nowhere\n- [?] a state nobody documented\n');
		const problems = auditDoc('docs/product/planted.md', readFileSync(path, 'utf-8'), DOCUMENTED);
		assert.equal(problems.length, 2);
		assert.match(problems[0], /planted\.md:1.*partial/s);
		assert.match(problems[1], /planted\.md:2.*no document defines/s);

		writeFileSync(path, '- [~] built, the rest is [here](followups.md)\n- [x] done\n');
		assert.deepEqual(
			auditDoc('docs/product/planted.md', readFileSync(path, 'utf-8'), DOCUMENTED),
			[],
		);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
