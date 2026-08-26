import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { waterDayKey } from '../../src/lib/nutrition/diary_day';

import {
	BROWSER_TIMEZONE,
	browserDate,
	browserDateOf,
	browserDatetimeLocal,
	browserDayAt,
	browserDayStart,
	browserYear,
	noonOnBrowserDay,
	waterStorageKey
} from './dates';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

test('a day instant lands on the wall-clock time it was asked for', () => {
	assert.match(browserDayStart(), /T00:00:00\.000Z$/);
	assert.match(noonOnBrowserDay(), /T12:00:00\.000Z$/);
	assert.match(browserDayAt(-2, 8, 30), /T08:30:00\.000Z$/);
});

test('a day instant belongs to the day it names, at either edge', () => {
	assert.equal(browserDateOf(browserDayAt(-3, 0, 0)), browserDate(-3));
	assert.equal(browserDateOf(browserDayAt(-3, 23, 59)), browserDate(-3));
	assert.equal(browserDayStart(-3).slice(0, 10), browserDate(-3));
});

test('offsets step whole calendar days, in both directions', () => {
	const day = 24 * 3_600_000;
	assert.equal(Date.parse(browserDayStart(0)) - Date.parse(browserDayStart(-1)), day);
	assert.equal(Date.parse(browserDayStart(1)) - Date.parse(browserDayStart(0)), day);
	assert.equal(Date.parse(browserDayStart(0)) - Date.parse(browserDayStart(-40)), 40 * day);
});

// The whole point of the module: the day it names must not move when the
// machine running the suite sits in a different zone from the browser.
test('the day a helper names is the same in every runner zone', () => {
	const original = process.env.TZ;
	try {
		process.env.TZ = 'Pacific/Kiritimati';
		const ahead = [browserDate(), browserDate(-1), noonOnBrowserDay(), browserDayStart()];
		process.env.TZ = 'Pacific/Midway';
		const behind = [browserDate(), browserDate(-1), noonOnBrowserDay(), browserDayStart()];
		process.env.TZ = 'UTC';
		const utc = [browserDate(), browserDate(-1), noonOnBrowserDay(), browserDayStart()];
		assert.deepEqual(ahead, utc);
		assert.deepEqual(behind, utc);
	} finally {
		if (original === undefined) delete process.env.TZ;
		else process.env.TZ = original;
	}
});

test('a datetime-local string is the browser wall clock of the instant', () => {
	assert.equal(browserDatetimeLocal('2026-08-25T14:29:00.000Z'), '2026-08-25T14:29');
	assert.equal(browserDatetimeLocal(Date.parse('2026-01-01T00:00:00Z')), '2026-01-01T00:00');
	// The control has no zone, so the browser reads back exactly the instant
	// the fixture meant — which is the whole reason it is not built locally.
	const instant = Date.now() - 60_000;
	assert.equal(Date.parse(`${browserDatetimeLocal(instant)}Z`), Math.floor(instant / 60_000) * 60_000);
});

test('the year and the datetime-local string are the same in every runner zone', () => {
	const original = process.env.TZ;
	try {
		const seen = new Set<string>();
		for (const tz of ['Pacific/Kiritimati', 'Pacific/Midway', 'Australia/Sydney', 'UTC']) {
			process.env.TZ = tz;
			seen.add(`${browserYear()}|${browserYear(-32)}|${browserDatetimeLocal(1_800_000_000_000)}`);
		}
		assert.equal(seen.size, 1);
	} finally {
		if (original === undefined) delete process.env.TZ;
		else process.env.TZ = original;
	}
});

test('the water key is the page key, unpadded, on the browser day', () => {
	const now = new Date();
	const expected = `water_ml_abc_${now.getUTCFullYear()}-${now.getUTCMonth() + 1}-${now.getUTCDate()}`;
	assert.equal(waterStorageKey('abc'), expected);
	assert.equal(waterStorageKey('abc'), `water_ml_abc_${waterDayKey(browserDate())}`);
});

// `dates.ts` builds every day in UTC because that is what the config pins. If
// the pin moves, the module is silently wrong everywhere at once.
test('the browser is still pinned to the zone dates.ts builds in', () => {
	const config = readFileSync(join(E2E_ROOT, 'playwright.config.ts'), 'utf8');
	assert.equal(BROWSER_TIMEZONE, 'UTC');
	assert.ok(
		/timezoneId:\s*'UTC'/.test(config),
		'playwright.config.ts no longer pins the browser to UTC — fixtures/dates.ts builds every ' +
			'day-relative timestamp in UTC and must change with it.'
	);
});

/**
 * Local-zone date getters and setters, which derive a calendar day in the
 * Node process's zone. `.getUTCDate()` and friends do not match — the `.`
 * anchors the name.
 */
const LOCAL_ZONE_DAY = new RegExp(
	'\\.(?:' +
		[
			'getFullYear',
			'getMonth',
			'getDate',
			'getDay',
			'getHours',
			'setFullYear',
			'setMonth',
			'setDate',
			'setHours',
			'toLocaleDateString'
		].join('|') +
		')\\s*\\('
);

/**
 * Files that still derive a day in the runner's zone, each with why it has not
 * been converted. Every entry is asserted to still match, so the list cannot
 * rot into a set of stale exemptions — a converted file must be deleted from
 * it, and a new file may not be added without a reason.
 *
 * The four marked "not yet converted" are the same bug this module exists to
 * kill, outside the nutrition surface it was fixed on; they are tracked in
 * docs/product/followups.md.
 */
const LOCAL_ZONE_ALLOWED: Record<string, string> = {
	'plans/calendar.spec.ts':
		'zone-neutral: one read runs inside page.evaluate (browser zone), the rest construct and format a fixed y/m/d in the same zone'
};

function typescriptSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) typescriptSources(full, out);
		else if (full.endsWith('.ts')) out.push(full);
	}
	return out;
}

/** Source with comments removed, so prose describing the bug never trips it. */
function withoutComments(source: string): string {
	return source
		.replace(/\/\*[\s\S]*?\*\//g, '')
		.split('\n')
		.map((line) => (line.includes('://') ? line : line.replace(/\/\/.*$/, '')))
		.join('\n');
}

function localZoneDayLines(file: string): number[] {
	const lines = withoutComments(readFileSync(file, 'utf8')).split('\n');
	const hits: number[] = [];
	lines.forEach((line, i) => {
		if (LOCAL_ZONE_DAY.test(line)) hits.push(i + 1);
	});
	return hits;
}

test('no spec derives a day-relative date in the runner zone', () => {
	const offenders: string[] = [];
	for (const file of typescriptSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel === 'fixtures/dates.ts' || rel === 'fixtures/dates.test.ts') continue;
		if (rel in LOCAL_ZONE_ALLOWED) continue;
		const hits = localZoneDayLines(file);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'These files build a calendar day in the Node process\'s zone while playwright.config.ts ' +
			`pins the browser to ${BROWSER_TIMEZONE}, so the seeded row lands on the adjacent day ` +
			'for part of every day and the page renders nothing (decisions.md § 728). Use ' +
			'fixtures/dates.ts — browserDate / browserDateOf / browserDayStart / browserDayAt / ' +
			`noonOnBrowserDay / waterStorageKey — instead of local Date getters: ${offenders.join(' ')}`
	);
});

test('every allowed local-zone site still exists and still matches', () => {
	for (const [rel, reason] of Object.entries(LOCAL_ZONE_ALLOWED)) {
		const file = join(E2E_ROOT, rel);
		assert.ok(
			statSync(file).isFile(),
			`${rel} is allowed to derive a day in the runner zone but no longer exists — drop the entry.`
		);
		assert.ok(
			localZoneDayLines(file).length > 0,
			`${rel} no longer derives a day in the runner zone (${reason}) — drop it from LOCAL_ZONE_ALLOWED ` +
				'so the guard covers it.'
		);
	}
});
