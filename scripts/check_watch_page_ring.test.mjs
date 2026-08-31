import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import test from 'node:test';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';

import {
	NAV_FILE,
	PAGE_FILE,
	RING_ANCHOR,
	check,
	parsePageCodes,
	parsePageNext,
	parseRingEdges,
} from './check_watch_page_ring.mjs';

const GUARD = join(dirname(fileURLToPath(import.meta.url)), 'check_watch_page_ring.mjs');

const PAGE_RS = [
	'impl Page {',
	'    pub fn code(self) -> &\'static str {',
	'        match self {',
	'            Page::Daylight => "SUN",',
	'            // Page::Ghost => "GHST" — a commented-out arm is not a page.',
	'            Page::Storm => "BARO",',
	'            Page::Waypoint => "WPT",',
	'        }',
	'    }',
	'    pub fn next(self) -> Page {',
	'        match self {',
	'            Page::Daylight => Page::Storm,',
	'            Page::Storm => Page::Waypoint,',
	'            Page::Waypoint => Page::Daylight,',
	'        }',
	'    }',
	'}',
].join('\n');

/** @param {string} ring */
const navWith = (ring) =>
	['# nav', '', '```mermaid', 'flowchart LR', `    ${ring}`, '```', ''].join('\n');

const RING = '%% the anchor, in a mermaid comment: RCAP --> STRK';

test('the committed ring agrees with the committed page cycle', () => {
	const { errors, ok } = check(
		readFileSync(PAGE_FILE, 'utf-8'),
		readFileSync(NAV_FILE, 'utf-8'),
	);
	assert.deepEqual(errors, []);
	assert.equal(ok.length, 1);
});

test('the parsers read only their own match arms, comments excluded', () => {
	const codes = parsePageCodes(PAGE_RS);
	assert.deepEqual([...codes.entries()], [
		['Daylight', 'SUN'],
		['Storm', 'BARO'],
		['Waypoint', 'WPT'],
	]);
	assert.deepEqual(parsePageNext(PAGE_RS), [
		['Daylight', 'Storm'],
		['Storm', 'Waypoint'],
		['Waypoint', 'Daylight'],
	]);
});

test('a page dropped from the diagram is reported in both directions', () => {
	// The § 376 defect exactly: BARO absent, so the ring skips it.
	const md = navWith(`${RING}\n    SUN --> WPT --> SUN`);
	const { errors } = check(PAGE_RS, md);
	assert.equal(errors.length, 3);
	assert.ok(errors.some((e) => /never draws SUN --> BARO/.test(e)));
	assert.ok(errors.some((e) => /never draws BARO --> WPT/.test(e)));
	assert.ok(errors.some((e) => /draws SUN --> WPT, which is not a step/.test(e)));
});

test('a drawn edge the firmware does not take is reported', () => {
	const md = navWith(`${RING}\n    SUN --> BARO --> WPT --> SUN\n    WPT --> BARO`);
	const { errors } = check(PAGE_RS, md);
	assert.equal(errors.length, 1);
	assert.match(errors[0], /draws WPT --> BARO/);
});

test('a chained mermaid line is read as its edges, not as one', () => {
	const edges = parseRingEdges(navWith(`${RING}\n    SUN --> BARO --> WPT`));
	assert.ok(edges.has('SUN>BARO'));
	assert.ok(edges.has('BARO>WPT'));
	assert.ok(!edges.has('SUN>WPT'));
});

test("mermaid's own direction token is not read as a page", () => {
	const edges = parseRingEdges(navWith(`${RING}\n    SUN --> BARO`));
	assert.ok(![...edges].some((e) => e.includes('LR')));
});

test('a missing anchor throws rather than reporting agreement', () => {
	assert.throws(
		() => parseRingEdges('```mermaid\nflowchart LR\n    A --> B\n```'),
		new RegExp(RING_ANCHOR),
	);
});

test('an empty parse throws rather than passing vacuously', () => {
	assert.throws(() => parsePageCodes('fn code() { match self { } }'), /parsed empty/);
	assert.throws(() => parsePageNext('fn next() { match self { } }'), /parsed empty/);
});

test('two pages under one code are refused rather than collapsed', () => {
	// `SUN>WPT` would be produced by two different declared edges, so the ring
	// could agree with a diagram that draws neither page.
	const clash = PAGE_RS.replace('Page::Storm => "BARO",', 'Page::Storm => "SUN",');
	assert.throws(() => parsePageCodes(clash), /both take the code "SUN"/);
});

test('the committed page.rs gives every page its own code', () => {
	const codes = parsePageCodes(readFileSync(PAGE_FILE, 'utf-8'));
	assert.equal(new Set(codes.values()).size, codes.size);
	assert.ok(codes.size >= 45, `expected the whole Page catalogue, found ${codes.size}`);
});

test('the ring anchor outside a mermaid block throws rather than reading prose', () => {
	// `lastIndexOf` would otherwise reach back to an earlier diagram and the
	// walk would grade the wrong block.
	assert.throws(
		() => parseRingEdges(['```mermaid', 'flowchart LR', '  A --> B', '```', '', RING_ANCHOR, ''].join('\n')),
		/not inside a mermaid block/,
	);
});

test('a drawn ring and a declared ring of the same SIZE still disagree edge for edge', () => {
	// § 794's point: a count would not have caught the missing BARO, because
	// the diagram named 45 pages either way.
	const md = navWith(`${RING}\n    SUN --> WPT --> BARO --> SUN`);
	const { errors } = check(PAGE_RS, md);
	assert.equal(parseRingEdges(md).size, 3);
	assert.equal(parsePageNext(PAGE_RS).length, 3);
	assert.ok(errors.length > 0, 'a same-size ring drawn in the wrong order must still fail');
});

/// The guard's exported file overrides exist so the whole script — exit code
/// and all — can be pointed at a mutated tree. Nothing exercised them, so the
/// path CI actually runs (a process, an exit status, an `::error::` line) was
/// covered by no test at all.
test('the script exits 0 on the committed tree and 1 on the § 376 defect', () => {
	const dir = mkdtempSync(join(tmpdir(), 'page-ring-'));
	try {
		const nav = join(dir, 'navigation.md');
		const committed = readFileSync(NAV_FILE, 'utf-8');
		writeFileSync(nav, committed);
		const clean = spawnSync(process.execPath, [GUARD], {
			encoding: 'utf-8',
			env: { ...process.env, WATCH_NAV_MD: nav },
		});
		assert.equal(clean.status, 0, clean.stderr);
		assert.match(clean.stdout, /agrees edge for edge/);

		// The § 376 defect on the real diagram: BARO dropped out of the ring
		// the storm page joined, leaving SUN --> WPT as the drawn step.
		const broken = committed.replace('SUN --> BARO --> WPT', 'SUN --> WPT');
		assert.notEqual(broken, committed, 'the § 376 edges must still be in navigation.md');
		writeFileSync(nav, broken);
		const failed = spawnSync(process.execPath, [GUARD], {
			encoding: 'utf-8',
			env: { ...process.env, WATCH_NAV_MD: nav },
		});
		assert.equal(failed.status, 1);
		assert.match(failed.stderr, /::error::check_watch_page_ring: navigation\.md never draws SUN --> BARO/);
		assert.match(failed.stderr, /never draws BARO --> WPT/);
		assert.match(failed.stderr, /draws SUN --> WPT, which is not a step/);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});

test('a page.rs the guard cannot parse fails the process rather than passing it', () => {
	const dir = mkdtempSync(join(tmpdir(), 'page-ring-'));
	try {
		const page = join(dir, 'page.rs');
		writeFileSync(page, 'impl Page { pub fn code(self) -> &\'static str { match self { } } }');
		const res = spawnSync(process.execPath, [GUARD], {
			encoding: 'utf-8',
			env: { ...process.env, WATCH_PAGE_RS: page },
		});
		assert.notEqual(res.status, 0);
		assert.match(res.stderr, /parsed empty|no `fn next`/);
	} finally {
		rmSync(dir, { recursive: true, force: true });
	}
});
