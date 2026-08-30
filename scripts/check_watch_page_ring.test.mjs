import { readFileSync } from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

import {
	NAV_FILE,
	PAGE_FILE,
	RING_ANCHOR,
	check,
	parsePageCodes,
	parsePageNext,
	parseRingEdges,
} from './check_watch_page_ring.mjs';

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
