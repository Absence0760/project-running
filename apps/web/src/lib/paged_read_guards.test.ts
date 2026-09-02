// Every paged read composes into the whole table, or it composes into
// something nobody can name. Invocation:
//   npx tsx --test src/lib/paged_read_guards.test.ts
//
// PostgREST turns `.range(from, to)` into LIMIT/OFFSET. Postgres makes no
// promise about the order of rows that a query does not order, and none about
// which of two equal sort keys comes first — so an OFFSET walk over a
// non-unique ORDER BY (or none at all) can return a row on a page boundary
// twice and another not at all. The tree already knew this: four load-more
// readers in `core/data.ts` carry a "Secondary key so offset pages are stable"
// note and a unique tiebreak.
//
// The readers that did NOT were the ones where it costs most. `createBackup`
// pages `runs` on `started_at` alone and paged `routes` with no order
// whatsoever, then writes a manifest saying `complete` — the archive someone
// wipes a device on. `fetchRuns` pages the entire history behind the recap,
// the heatmap and the account export. The two ZIP importers page the dedupe
// set, where a dropped row re-imports a run the runner already has.
//
// So the rule is a rule now: a `.range()` read's ordering has to end on a
// column that is unique per row.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';

const srcRoot = resolve(import.meta.dirname, '..');

/**
 * Columns that are unique within one query's result set, so an ordering
 * ending on one is a total order. `id` is every table's primary key here;
 * the two membership tables are keyed on a pair whose other half the query
 * already fixes with `.eq()`, which is why their own readers tiebreak on the
 * user rather than on an id they do not have.
 */
const UNIQUE_TIEBREAKS = ['id', 'user_id', 'follower_id', 'followee_id'];

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

/** Comment bodies blanked, so prose about a paged read is not read as one. */
function code(src: string): string {
	return src
		.replace(/\/\*[\s\S]*?\*\//g, ' ')
		.split('\n')
		.map((l) => (/^\s*\/\//.test(l) ? '' : l.replace(/\s\/\/.*$/, '')))
		.join('\n');
}

/**
 * The chained builder call each `.range(` sits at the end of, as raw text.
 * Walked BACKWARDS over balanced brackets rather than sliced at the nearest
 * delimiter, because `.order('x', { ascending: false })` puts a brace inside
 * every chain this guard is about.
 */
function chainsEndingInRange(src: string): { line: number; chain: string }[] {
	const out: { line: number; chain: string }[] = [];
	for (const m of src.matchAll(/\.range\(/g)) {
		const at = m.index;
		let depth = 0;
		let i = at - 1;
		for (; i >= 0; i--) {
			const c = src[i];
			if (c === ')' || c === ']' || c === '}') depth++;
			else if (c === '(' || c === '[' || c === '{') {
				if (depth === 0) break;
				depth--;
			} else if (depth === 0 && (c === ';' || c === ',')) break;
			else if (depth === 0 && c === '>' && src[i - 1] === '=') break;
		}
		out.push({
			line: src.slice(0, at).split('\n').length,
			chain: src.slice(i + 1, at),
		});
	}
	return out;
}

/**
 * The body of a local `const <name> = ...;` declaration, balanced over
 * brackets. A paged read whose builder is a closure (`build().range(...)` in
 * `fetchRuns`) keeps its ordering there, so the chain alone says nothing.
 */
function localDeclaration(src: string, name: string): string | null {
	const decl = new RegExp(`\\bconst\\s+${name}\\s*=`).exec(src);
	if (!decl) return null;
	let depth = 0;
	for (let i = decl.index + decl[0].length; i < src.length; i++) {
		const c = src[i];
		if (c === '(' || c === '[' || c === '{') depth++;
		else if (c === ')' || c === ']' || c === '}') depth--;
		else if (c === ';' && depth === 0) return src.slice(decl.index, i);
	}
	return null;
}

/** Every `.order('col'` in a chunk of source, in order. */
function orderKeys(text: string): string[] {
	return [...text.matchAll(/\.order\(\s*['"]([A-Za-z_][\w]*)['"]/g)].map((m) => m[1]);
}

test('every paged read ends its ordering on a column unique per row', () => {
	const offenders: string[] = [];
	let ranges = 0;

	for (const file of sources(srcRoot)) {
		const src = code(readFileSync(file, 'utf-8'));
		if (!src.includes('.range(')) continue;
		for (const { line, chain } of chainsEndingInRange(src)) {
			ranges++;
			let orders = orderKeys(chain);
			// `build().range(...)` — the ordering lives in the closure, not
			// in the chain the call returns.
			const rootCall = /([A-Za-z_][\w]*)\(\s*\)\s*$/.exec(chain.trim());
			if (orders.length === 0 && rootCall) {
				const body = localDeclaration(src, rootCall[1]);
				if (body) orders = orderKeys(body);
			}
			const rel = file.slice(resolve(srcRoot, '..').length + 1);
			if (orders.length === 0) {
				offenders.push(`${rel}:${line}: paged read with no .order() at all`);
				continue;
			}
			const last = orders[orders.length - 1];
			if (!UNIQUE_TIEBREAKS.includes(last)) {
				offenders.push(`${rel}:${line}: paged read ends its order on \`${last}\`, which is not unique`);
			}
		}
	}

	// Population: a walk that resolved nothing would satisfy the assertion
	// below while proving nothing. The tree holds about a dozen.
	assert.ok(ranges >= 8, `only found ${ranges} .range() reads — walker broken?`);

	assert.deepEqual(
		offenders.sort(),
		[],
		'a `.range()` read is paged over an ordering that is not a total order, ' +
			'so a row on a page boundary can be returned twice or not at all. ' +
			'Add a unique secondary key the way fetchClubMembers does.',
	);
});
