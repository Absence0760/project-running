import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { readCount, readMaybeRow, readRow, readRows } from './db-read';

const HERE = dirname(fileURLToPath(import.meta.url));
const E2E_ROOT = join(HERE, '..');

const ok = <T>(data: T) => Promise.resolve({ data, error: null });
const failed = (message: string, code?: string) =>
	Promise.resolve({ data: null, error: { message, code } });

test('a read that worked returns exactly what came back', async () => {
	assert.deepEqual(await readRows('rows', ok([{ id: 1 }])), [{ id: 1 }]);
	assert.deepEqual(await readRow('row', ok({ id: 1 })), { id: 1 });
	assert.deepEqual(await readMaybeRow('row', ok({ id: 1 })), { id: 1 });
	assert.equal(await readCount('count', Promise.resolve({ count: 3, error: null })), 3);
});

// The whole point: zero rows is a real answer, so it must survive as one and
// never be conflated with the read having failed.
test('zero rows is an answer, not a failure', async () => {
	assert.deepEqual(await readRows('rows', ok([])), []);
	assert.equal(await readMaybeRow('row', ok(null)), null);
	assert.equal(await readCount('count', Promise.resolve({ count: 0, error: null })), 0);
});

test('a failed read throws naming itself, its code, and the driver message', async () => {
	await assert.rejects(() => readRows('gear_with_distance by id', failed('permission denied', '42501')), {
		message:
			'gear_with_distance by id: the read itself failed [42501] — permission denied'
	});
	await assert.rejects(() => readRow('the run row', failed('boom')), {
		message: 'the run row: the read itself failed — boom'
	});
	await assert.rejects(() => readMaybeRow('the run row', failed('boom')), /the read itself failed/);
	await assert.rejects(
		() => readCount('the probe', Promise.resolve({ count: null, error: { message: 'boom' } })),
		/the read itself failed/
	);
});

// A failed read used to satisfy `expect(rows ?? []).toEqual([])`. The helper
// must throw where the old shape returned the empty value the test wanted.
test('a failed read cannot be mistaken for the empty result a negative assertion wants', async () => {
	await assert.rejects(() => readRows('rows', failed('network')), /the read itself failed/);
	await assert.rejects(
		() => readCount('probe', Promise.resolve({ count: null, error: { message: 'network' } })),
		/the read itself failed/
	);
});

// PGRST116 means the read reached the table and the row was not there. That is
// a different sentence from the read failing, and it points at a different bug.
test('an absent single row is reported as absent, not as a broken read', async () => {
	await assert.rejects(
		() => readRow('the gear row', failed('JSON object requested, 0 rows', 'PGRST116')),
		{ message: 'the gear row: expected exactly one row, the table had none — JSON object requested, 0 rows' }
	);
	assert.equal(await readMaybeRow('the gear row', failed('0 rows', 'PGRST116')), null);
});

test('a null payload with no error is still refused rather than coalesced', async () => {
	await assert.rejects(() => readRows('rows', ok(null)), /no rows array and no error/);
	await assert.rejects(() => readRow('row', ok(null)), /expected exactly one row, got none/);
	await assert.rejects(
		() => readCount('probe', Promise.resolve({ count: null, error: null })),
		/no count and no error/
	);
});

/*
 * Source guard. The class this module exists to kill is a destructure that
 * drops `error` and then coalesces the absence into a value an `expect`
 * compares against — `expect(Number(row?.total ?? 0)).toBe(6000)` blames the
 * feature for a read that never ran, and `expect(rows ?? []).toEqual([])` is
 * SATISFIED by one. Both shapes are mechanical, so both are checkable.
 */

/** Source with comments removed, so prose describing the bug never trips it. */
function withoutComments(source: string): string {
	return source
		.replace(/\/\*[\s\S]*?\*\//g, (m) => '\n'.repeat((m.match(/\n/g) ?? []).length))
		.split('\n')
		.map((line) => (line.includes('://') ? line : line.replace(/\/\/.*$/, '')))
		.join('\n');
}

const DESTRUCTURE = /const\s*\{([^}]*)\}\s*=\s*await\b/g;
/** A coalesce that manufactures a concrete, legitimate-looking value. */
const FABRICATES = /(\?\?|\|\|)\s*(0\b|\[\]|''|"")/;
const ASSERTS = /expect\(|toBe|toEqual|toContain|toHaveLength|toHaveCount/;

function typescriptSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) typescriptSources(full, out);
		else if (full.endsWith('.ts')) out.push(full);
	}
	return out;
}

/**
 * Lines where a binding taken from an awaited `{ data }` — with no `error`
 * beside it — is fabricated into a value inside an assertion.
 */
function swallowedReadLines(file: string): number[] {
	const source = withoutComments(readFileSync(file, 'utf8'));
	const lines = source.split('\n');
	const hits: number[] = [];
	let match: RegExpExecArray | null;
	DESTRUCTURE.lastIndex = 0;
	while ((match = DESTRUCTURE.exec(source))) {
		const bound = match[1];
		if (/\berror\b/.test(bound)) continue;
		if (!/\bdata\b/.test(bound)) continue;
		const alias = /\bdata\s*:\s*([A-Za-z_$][\w$]*)/.exec(bound)?.[1] ?? 'data';
		const declLine = source.slice(0, match.index).split('\n').length;
		const mentions = new RegExp(`\\b${alias}\\b`);
		const rebinds = new RegExp(`const\\s*\\{[^}]*\\b${alias}\\b`);
		for (let i = declLine; i < lines.length; i++) {
			if (!mentions.test(lines[i])) continue;
			if (rebinds.test(lines[i])) break;
			if (FABRICATES.test(lines[i]) && ASSERTS.test(lines[i])) hits.push(i + 1);
		}
	}
	return hits;
}

/**
 * Specs allowed to keep the shape, each with why. Every entry is asserted to
 * still match, so the list cannot rot into a set of stale exemptions — a
 * converted file must be deleted from it, and a new one may not be added
 * without a reason that survives being read out loud.
 */
const SWALLOWED_READ_ALLOWED: Record<string, string> = {};

test('no spec asserts against a value fabricated from a read whose error it dropped', () => {
	const offenders: string[] = [];
	for (const file of typescriptSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel === 'fixtures/db-read.ts' || rel === 'fixtures/db-read.test.ts') continue;
		if (rel in SWALLOWED_READ_ALLOWED) continue;
		const hits = swallowedReadLines(file);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'These lines drop a read error and then coalesce the absence into the value an assertion ' +
			'compares against. Against a non-zero expectation that blames the feature for a read ' +
			'that never ran; against a zero/empty one the assertion PASSES and stops testing ' +
			'anything (decisions.md § 732). Read through fixtures/db-read.ts — readRow / readRows / ' +
			`readMaybeRow / readCount — so the read fails as itself: ${offenders.join(' ')}`
	);
});

test('every allowed swallowed read still exists and still matches', () => {
	for (const [rel, reason] of Object.entries(SWALLOWED_READ_ALLOWED)) {
		const file = join(E2E_ROOT, rel);
		assert.ok(
			statSync(file).isFile(),
			`${rel} is allowed to swallow a read error but no longer exists — drop the entry.`
		);
		assert.ok(
			swallowedReadLines(file).length > 0,
			`${rel} no longer swallows a read error (${reason}) — drop it from ` +
				'SWALLOWED_READ_ALLOWED so the guard covers it.'
		);
	}
});
