// A narrowed run read carries the columns it asked for, and `track` can never
// be one of them.
//
// `RunColumns` is `keyof Run & keyof RunRow` since § 1468, so `track` — a lazy
// Storage download that has never been a column — cannot appear in a caller's
// tuple, and § 1520 stopped `fetchRuns` inventing the key on a projected row.
// Both of those are type-level and row-level facts. What neither reaches is a
// CONSUMER that gets a projected row through an `as`, a `JsonObject` index or
// a structurally-bound parameter and reads `.track` off it anyway: it would
// read `undefined` where the same code once read `null`, and nothing would
// object.
//
// So the rule is about the reading file, not about the row: a file whose run
// rows all come from a narrowed read may not name `.track` at all. A file that
// ALSO performs an unnarrowed read has a `Run` to read it off and is exempt —
// no file is, today, and a future one that needs the exemption gets it here
// rather than by widening the rule.
//
// Invocation: npx tsx --test src/lib/core/projected_run_guard.test.ts

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

import { stripComments } from './strip_comments';

const srcRoot = resolve(import.meta.dirname, '../..');

/// The three sibling reads that project a fixed column tuple. `fetchRuns`
/// itself is narrowed only when the call names `columns`, so it is resolved
/// per call rather than by name.
const NARROWED_READERS = [
	'fetchRunsForDashboard',
	'fetchRunsForPeriodSummary',
	'fetchRunsForRecap',
];

/// Reads that answer with a whole `Run`, which legitimately declares `track`.
const UNNARROWED_READERS = [
	'fetchRunsWithError',
	'fetchRunById',
	'fetchRunsOnRoute',
	'fetchPublicRun',
	'fetchTrack',
];

/// `core/data.ts` declares every one of these and owns the unnarrowed read
/// itself, so it is the one file the rule cannot be about.
const READER_MODULE = 'src/lib/core/data.ts';

function sources(dir: string): string[] {
	const out: string[] = [];
	for (const entry of readdirSync(dir)) {
		const full = join(dir, entry);
		if (statSync(full).isDirectory()) {
			if (entry === 'node_modules' || entry === '.svelte-kit') continue;
			out.push(...sources(full));
			continue;
		}
		if (!/\.(ts|svelte)$/.test(entry)) continue;
		if (/\.test\.ts$/.test(entry)) continue;
		out.push(full);
	}
	return out;
}

/// The argument text of every `<name>(` call in `src`, walked over balanced
/// brackets so a nested object or arrow does not truncate it.
function callArgs(src: string, name: string): string[] {
	const out: string[] = [];
	for (const m of src.matchAll(new RegExp(`\\b${name}\\s*\\(`, 'g'))) {
		let depth = 0;
		let i = m.index + m[0].length - 1;
		for (; i < src.length; i++) {
			const c = src[i];
			if (c === '(' || c === '[' || c === '{') depth++;
			else if (c === ')' || c === ']' || c === '}') {
				depth--;
				if (depth === 0) break;
			}
		}
		out.push(src.slice(m.index + m[0].length, i));
	}
	return out;
}

test('no file that only reads narrowed run rows names `.track`', () => {
	const offenders: string[] = [];
	let narrowedFiles = 0;

	for (const file of sources(srcRoot)) {
		const rel = file.slice(resolve(srcRoot, '..').length + 1);
		if (rel === READER_MODULE) continue;
		const src = stripComments(readFileSync(file, 'utf-8'));

		const fetchRunsCalls = callArgs(src, 'fetchRuns');
		const narrowed =
			fetchRunsCalls.some((args) => args.includes('columns:')) ||
			NARROWED_READERS.some((n) => new RegExp(`\\b${n}\\s*\\(`).test(src));
		if (!narrowed) continue;

		const unnarrowed =
			fetchRunsCalls.some((args) => !args.includes('columns:')) ||
			UNNARROWED_READERS.some((n) => new RegExp(`\\b${n}\\s*\\(`).test(src));
		if (unnarrowed) continue;

		narrowedFiles++;
		for (const m of src.matchAll(/\.track\b/g)) {
			offenders.push(`${rel}:${src.slice(0, m.index).split('\n').length}`);
		}
	}

	// Population: a walk that classified nothing as narrowed would satisfy the
	// assertion below while proving nothing. Six files read a narrowed run row
	// today — the two recap routes, the two dashboard routes, the plan editor
	// and the gear page.
	assert.ok(
		narrowedFiles >= 6,
		`only ${narrowedFiles} files classified as narrowed-only run readers — walker broken?`,
	);

	assert.deepEqual(
		offenders.sort(),
		[],
		'a file whose run rows all come from a column-narrowed read names `.track`. ' +
			'A projected row cannot carry it (§ 1468 / § 1520), so the read answers ' +
			'`undefined` — add an unnarrowed read if the track is genuinely needed, or ' +
			'drop the reference.',
	);
});
