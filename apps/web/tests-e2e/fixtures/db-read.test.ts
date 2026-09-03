import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

import { readCount, readMaybeRow, readRow, readRows } from './db-read';
import { stripComments } from '../../src/lib/core/strip_comments';

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
 * Source guard.
 *
 * The first version of this guard banned one shape: a destructured `{ data }`
 * coalesced into a literal on the same line as an `expect`. That is how the
 * defect was first met — `expect(Number(row?.total ?? 0)).toBe(6000)` blaming
 * a mileage trigger for a service-role read that never ran — but it is only
 * how it was first met. Sweeping the tree for the whole class found the same
 * swallow wearing four other costumes: a bare `?.` into the assertion, a
 * `!`, a `(row as { field: T })` cast, and no absorber at all, where the
 * read's own `null` was already the value the matcher wanted. Thirty of
 * those PASSED on a read that never reached the table, most of them RLS
 * negatives and Art 17 cascade checks (decisions.md § 777).
 *
 * So the rule here is not a taxonomy of absorbers — a taxonomy only ever
 * catches the costumes someone has already seen. It is the shape underneath:
 * a binding taken from a Supabase read whose `error` is never consulted may
 * not appear inside an `expect(...)` at all. Read it through readRow /
 * readRows / readMaybeRow / readCount, and the read fails as itself.
 *
 * A read whose result is used for something other than an assertion (an id
 * captured for teardown, a value fed to the next insert) is out of scope:
 * it has no cross-check to corrupt, and it fails loudly on its own.
 */

/**
 * String CONTENTS replaced by spaces, offsets preserved. Two things need it:
 * a table name is not a reference to a like-named binding (`'routine-history'`
 * is not the binding `history`), and a paren inside a message would otherwise
 * unbalance the walk that finds where an `expect(` argument ends.
 */
function blankStringContents(source: string): string {
	return source.replace(/'[^'\n]*'|"[^"\n]*"/g, (m) => m[0] + ' '.repeat(m.length - 2) + m[0]);
}

/** The argument text of every `expect(...)`, by matching paren. */
function expectArguments(source: string): Array<{ from: number; text: string }> {
	const out: Array<{ from: number; text: string }> = [];
	const call = /\bexpect\s*\(/g;
	let match: RegExpExecArray | null;
	while ((match = call.exec(source))) {
		let depth = 1;
		let i = call.lastIndex;
		while (i < source.length && depth > 0) {
			if (source[i] === '(') depth++;
			else if (source[i] === ')') depth--;
			i++;
		}
		out.push({ from: match.index, text: source.slice(call.lastIndex, i - 1) });
	}
	return out;
}

/** A supabase read, as opposed to any other awaited call. */
const READS_THE_DB = /\.(from|rpc)\s*\(|\.storage\b|auth\.admin\./;
/** Already routed through this module — the whole point, not an offence. */
const THROUGH_FIXTURE = /^\s*(readRow|readRows|readMaybeRow|readCount)\s*\(/;
const DECLARATION = /\b(?:const|let)\s+(\{[^}]*\}|[A-Za-z_$][\w$]*)\s*=\s*await\s([\s\S]*?);/g;

/**
 * Lines where a binding from a read that dropped its error is judged by an
 * `expect`. The binding is live from its declaration until the name is
 * declared again, which is as much scope as a source-level scan can see and
 * errs towards reporting rather than missing.
 */
function swallowedReadLines(file: string): number[] {
	const source = blankStringContents(stripComments(readFileSync(file, 'utf8')));
	const lineOf = (index: number) => source.slice(0, index).split('\n').length;
	const asserts = expectArguments(source);
	const hits = new Set<number>();
	let match: RegExpExecArray | null;
	DECLARATION.lastIndex = 0;
	while ((match = DECLARATION.exec(source))) {
		const [, bound, initializer] = match;
		if (!READS_THE_DB.test(initializer) || THROUGH_FIXTURE.test(initializer)) continue;

		let binding: string | null = null;
		let viaData = false;
		if (bound.startsWith('{')) {
			const named = (prop: string) =>
				new RegExp(`\\b${prop}\\b\\s*(?::\\s*([A-Za-z_$][\\w$]*))?`).exec(bound);
			const error = named('error');
			// An error that is read somewhere is an error that was not dropped.
			if (error) {
				const local = error[1] ?? 'error';
				if ([...source.matchAll(new RegExp(`\\b${local}\\b`, 'g'))].length > 1) continue;
			}
			const data = named('data') ?? named('count');
			if (!data) continue;
			binding = data[1] ?? data[0].trim();
		} else {
			binding = bound;
			viaData = true;
			if (new RegExp(`\\b${binding}\\s*\\.\\s*error\\b`).test(source)) continue;
		}

		const declaredAt = match.index;
		const redeclared = new RegExp(`\\b(?:const|let)\\s+(?:\\{[^}]*\\b${binding}\\b|${binding}\\b)`, 'g');
		redeclared.lastIndex = declaredAt + match[0].length;
		const until = redeclared.exec(source)?.index ?? source.length;
		const reference = viaData
			? new RegExp(`\\b${binding}\\s*\\.\\s*data\\b`)
			: new RegExp(`\\b${binding}\\b`);

		for (const { from, text } of asserts) {
			if (from <= declaredAt || from >= until) continue;
			if (reference.test(text)) hits.add(lineOf(from));
		}
	}
	return [...hits].sort((a, b) => a - b);
}

/**
 * Reads allowed to keep the raw shape, each with why. Every entry is
 * asserted to still match and to carry a reason, so the list cannot rot into
 * a set of stale exemptions — a converted file must be deleted from it, and a
 * new one may not be added without a reason that survives being read aloud.
 *
 * Empty, and it should stay that way: an exemption here is a cross-check that
 * cannot say whether it looked. The one read whose error genuinely IS the
 * answer — GoTrue reports a deleted user with a 404 rather than a null row —
 * asserts that the status is 404 before reading the absence, which is a fix
 * rather than an exemption.
 */
const SWALLOWED_READ_ALLOWED: Record<string, string> = {};

const SCANNED = ['.ts', '.mjs'];

function scannedSources(dir: string, out: string[] = []): string[] {
	for (const entry of readdirSync(dir)) {
		if (entry === 'node_modules' || entry === '.auth') continue;
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) scannedSources(full, out);
		else if (SCANNED.some((ext) => full.endsWith(ext))) out.push(full);
	}
	return out;
}

test('no spec judges a feature by a read whose error it dropped', () => {
	const offenders: string[] = [];
	for (const file of scannedSources(E2E_ROOT)) {
		const rel = relative(E2E_ROOT, file);
		if (rel === 'fixtures/db-read.ts' || rel === 'fixtures/db-read.test.ts') continue;
		if (rel in SWALLOWED_READ_ALLOWED) continue;
		const hits = swallowedReadLines(file);
		if (hits.length) offenders.push(`${rel}:${hits.join(',')}`);
	}
	assert.deepEqual(
		offenders,
		[],
		'These assertions judge the feature by a read whose error was discarded. Against a ' +
			'non-zero expectation the read failing blames the feature; against a zero, empty or ' +
			'null one the assertion PASSES and the cross-check stops testing anything ' +
			'(decisions.md § 777). Read through fixtures/db-read.ts — readRow / readRows / ' +
			`readMaybeRow / readCount — so the read fails as itself: ${offenders.join(' ')}`
	);
});

test('every allowed swallowed read still exists, still matches, and says why', () => {
	for (const [rel, reason] of Object.entries(SWALLOWED_READ_ALLOWED)) {
		assert.ok(
			reason.trim().length > 0,
			`${rel} is exempt from the swallowed-read guard with no reason given — say why, or convert it.`
		);
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
