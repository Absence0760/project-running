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
	assert.equal(linksSurvey('tracked in followups.md, honest'), false);
	assert.equal(linksSurvey('see [it](../product/followups.md)'), true);
	assert.equal(linksSurvey('see [it](followups.md#anchor)'), true);
	assert.equal(linksSurvey('see [it](roadmap.md)'), true);
	// followups_archive.md contains "followups" but is not a survey file.
	assert.equal(linksSurvey('see [it](followups_archive.md)'), false);

	assert.equal(auditDoc('d.md', '- [~] built, not live\n', DOCUMENTED).length, 1);
	assert.match(auditDoc('d.md', '- [~] built\n', DOCUMENTED)[0], new RegExp(SURVEY_FILES[0]));
	assert.deepEqual(auditDoc('d.md', '- [~] built ([rest](followups.md))\n', DOCUMENTED), []);
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

test('a planted violation is reported, and stops being reported once removed', () => {
	const dir = mkdtempSync(join(tmpdir(), 'doc-checkbox-probe-'));
	try {
		const path = join(dir, 'planted.md');
		writeFileSync(path, '- [~] built but not live, tracked nowhere\n- [?] a state nobody documented\n');
		const problems = auditDoc('planted.md', readFileSync(path, 'utf-8'), DOCUMENTED);
		assert.equal(problems.length, 2);
		assert.match(problems[0], /planted\.md:1.*partial/s);
		assert.match(problems[1], /planted\.md:2.*no document defines/s);

		writeFileSync(path, '- [~] built, the rest is [here](followups.md)\n- [x] done\n');
		assert.deepEqual(auditDoc('planted.md', readFileSync(path, 'utf-8'), DOCUMENTED), []);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
