// Unit tests for scripts/check_parity_matrix.dart.
//
// Run: `node --test scripts/check_parity_matrix.test.mjs`
//
// They drive the guard as a process over fixture files. The guard is a bare
// `dart:io` script and there is no Dart test package at the repo root, so this
// is the harness available — and a guard with no suite at all is how its row
// walk carried the § 779 blind spot from the day it was written. `dart` being
// absent FAILS these rather than skipping them: a suite that reports a tree
// clean because it could not run is the defect this round is about.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GUARD = join(REPO_ROOT, 'scripts', 'check_parity_matrix.dart');
const MATRIX = join(REPO_ROOT, 'docs', 'product', 'parity.md');

const HEADER = ['| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |', '|---|---|---|---|---|---|---|'];

const LEGEND = ['| Symbol | Meaning |', '|---|---|', '| `✓` | Shipped. |', '| `Partial` | Wired but unobserved. |'];

/**
 * @param {string[]} lines
 * @returns {string}
 */
function fixture(lines) {
	const dir = mkdtempSync(join(tmpdir(), 'parity-matrix-'));
	const path = join(dir, 'parity.md');
	writeFileSync(path, `${lines.join('\n')}\n`, 'utf8');
	return path;
}

/**
 * @param {string} path
 * @returns {{ code: number, out: string }}
 */
function run(path) {
	try {
		const out = execFileSync('dart', ['run', GUARD, path], {
			cwd: REPO_ROOT,
			encoding: 'utf8',
			stdio: ['ignore', 'pipe', 'pipe'],
		});
		return { code: 0, out };
	} catch (err) {
		const e = /** @type {{ status: number | null, stdout: string, stderr: string }} */ (
			/** @type {unknown} */ (err)
		);
		if (e.status === null || e.status === undefined) throw err;
		return { code: e.status, out: `${e.stdout}${e.stderr}` };
	}
}

const CLEAN = ['## Legend', '', ...LEGEND, '', '## Import', '', ...HEADER, '| GPX import | ✓ | Partial | ✓ | N/A | N/A | |'];

test('a clean matrix passes and the Legend is not read as parity rows', () => {
	const { code, out } = run(fixture(CLEAN));
	assert.equal(code, 0, out);
	assert.match(out, /1 rows parsed, no issues/);
});

test('the committed docs/product/parity.md passes', () => {
	const { code, out } = run(MATRIX);
	assert.equal(code, 0, out);
	assert.match(out, /rows parsed, no issues/);
});

// --- The optional LEADING pipe. decisions § 779.
//
// GFM makes it optional exactly as it makes the trailing one optional, and the
// row renders identically — measured against `marked`, the `<tr>` is
// indistinguishable from its neighbours. This guard found its rows with
// `line.startsWith('|')`, so such a row reached none of its three rules.

test('an illegal symbol is caught in a row written without its leading pipe', () => {
	const row = 'FIT import | ✓ | Partial | Maybe | N/A | N/A | Notes. |';
	for (const line of [row, `| ${row}`]) {
		const { code, out } = run(fixture([...CLEAN, line]));
		assert.equal(code, 1, out);
		assert.match(out, /Web cell "Maybe" is not one of/);
	}
});

test('the 7-column rule reaches such a row too', () => {
	const { code, out } = run(fixture([...CLEAN, 'FIT import | ✓ | Partial | ✓ | N/A | Notes. |']));
	assert.equal(code, 1, out);
	assert.match(out, /row has 6 columns \(expected 7/);
});

test('the Partial-needs-Notes rule reaches such a row too', () => {
	const { code, out } = run(fixture([...CLEAN, 'FIT import | Partial | Partial | ✓ | N/A | N/A | |']));
	assert.equal(code, 1, out);
	assert.match(out, /Notes column is empty/);
});

test('one such row does not take the rest of its table with it', () => {
	const { code, out } = run(
		fixture([
			...CLEAN,
			'FIT import | ✓ | Partial | ✓ | N/A | N/A | Notes. |',
			'| TCX import | ✓ | Partial | Maybe | N/A | N/A | Notes. |',
		]),
	);
	assert.equal(code, 1, out);
	assert.match(out, /3 parsed rows/);
	assert.match(out, /Web cell "Maybe"/);
});

// A table-aware walk gains a way to lose rows the old one did not have: break
// the delimiter's width and GFM opens no table, so every row under it stops
// existing. Two committed docs are in that state today.
test('a table whose delimiter went wrong is reported rather than silently lost', () => {
	const { code, out } = run(
		fixture([
			'## Import',
			'',
			'| Feature | Android | iOS | Web | Wear OS | Apple Watch | Notes |',
			'|---|---|',
			'| GPX import | ✓ | Partial | ✓ | N/A | N/A | |',
		]),
	);
	assert.equal(code, 1, out);
	assert.match(out, /belongs to no table/);
});

test('a blank line splitting a table is reported, not a silent truncation', () => {
	const { code, out } = run(fixture([...CLEAN, '', '| TCX import | ✓ | Partial | ✓ | N/A | N/A | |']));
	assert.equal(code, 1, out);
	assert.match(out, /belongs to no table/);
});

test('a table drawn inside a fence is an illustration, not a matrix', () => {
	const { code, out } = run(fixture([...CLEAN, '', '```md', ...HEADER, '| Sample | ✓ | ✓ | ✓ | ✓ | ✓ | |', '```']));
	assert.equal(code, 0, out);
	assert.match(out, /1 rows parsed/);
});

test('a matrix with no data rows at all is an error, not a pass', () => {
	const { code, out } = run(fixture(['## Legend', '', ...LEGEND]));
	assert.equal(code, 2, out);
	assert.match(out, /no data rows parsed/);
});
