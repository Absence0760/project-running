/// The two bounds the streamed Art 20 export still has, on their own.
///
/// `export_budget.ts` has no suite of its own — it is exercised only through
/// `stream_section.test.ts`, which drives it at one point on each side of the
/// deadline. That leaves the object's own contract untested: whether the
/// deadline is inclusive, whether the shortfall list a manifest is built from
/// can be mutated by whoever reads it, and whether the wall-clock budget still
/// leaves the platform timeout room to finalise the upload. A budget that
/// under-reports its shortfall is an archive the manifest claims is whole.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/export-data/budget_invariants.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	createExportBudget,
	EXPORT_FUNCTION_TIMEOUT_MS,
	EXPORT_WALL_CLOCK_BUDGET_MS,
} from './export_budget.ts';
import { EXPORT_PAGE_SIZE, parseContentRangeTotal } from './paging.ts';
import { EXPORT_FETCH_CONCURRENCY, pooledPipeline } from './pooled.ts';

Deno.test('the budget deadline is inclusive, so the last millisecond is already spent', () => {
	let clock = 1000;
	const budget = createExportBudget(50, () => clock);
	assertEquals(budget.expired(), false);
	clock = 1049;
	assertEquals(budget.expired(), false);
	clock = 1050;
	assertEquals(budget.expired(), true, 'exactly at the deadline is expired');
	clock = 1051;
	assertEquals(budget.expired(), true);
});

Deno.test('remainingMs counts down and then stops at zero, never below', () => {
	let clock = 0;
	const budget = createExportBudget(100, () => clock);
	assertEquals(budget.remainingMs(), 100);
	clock = 60;
	assertEquals(budget.remainingMs(), 40);
	clock = 100;
	assertEquals(budget.remainingMs(), 0);
	clock = 10_000;
	assertEquals(budget.remainingMs(), 0, 'a long overrun is still zero, not negative');
});

Deno.test('a budget reads its clock every time, so it cannot be created already spent', () => {
	// The deadline is `now() + budgetMs` at construction. Reading the clock once
	// and caching it would make a budget created early in a request expire on a
	// schedule set by whoever constructed it first.
	let clock = 5_000_000;
	const budget = createExportBudget(1000, () => clock);
	assertEquals(budget.expired(), false);
	clock += 999;
	assertEquals(budget.expired(), false);
	clock += 1;
	assertEquals(budget.expired(), true);
});

Deno.test('noteSkipped keeps first-seen order and records a section once', () => {
	// The list becomes `manifest.json`'s `incomplete`. A duplicate would make a
	// section look twice-truncated; a lost one would drop a whole table out of
	// the shortfall while it is still missing from the archive.
	const budget = createExportBudget(1000, () => 0);
	budget.noteSkipped('food_log');
	budget.noteSkipped('gym_sets');
	budget.noteSkipped('food_log');
	budget.noteSkipped('runs');
	budget.noteSkipped('gym_sets');
	assertEquals(budget.deadlineSkipped(), ['food_log', 'gym_sets', 'runs']);
});

Deno.test('deadlineSkipped hands back a copy, so a reader cannot empty the shortfall', () => {
	// The handler folds this list into the response AND into the manifest. If
	// the two readers shared one array, the first to sort, splice or clear it
	// would silently change what the second reported.
	const budget = createExportBudget(1000, () => 0);
	budget.noteSkipped('food_log');
	const first = budget.deadlineSkipped();
	first.length = 0;
	first.push('nothing_was_skipped');
	assertEquals(budget.deadlineSkipped(), ['food_log']);
	assert(budget.deadlineSkipped() !== budget.deadlineSkipped(), 'a fresh array each read');
});

Deno.test('an unspent budget claims no shortfall at all', () => {
	// The complement of every case above: `incomplete` must be empty on a run
	// that finished, or every export apologises for nothing.
	const budget = createExportBudget(1000, () => 0);
	assertEquals(budget.deadlineSkipped(), []);
	assertEquals(budget.expired(), false);
});

Deno.test('the builders stop early enough to finalise, and the margin is real', () => {
	// The remainder covers the last 6 MiB PATCH, the signature and the answer,
	// none of which may be cut off — a killed request leaves no artifact at all,
	// so this margin is the difference between a short archive and no archive.
	assert(EXPORT_WALL_CLOCK_BUDGET_MS < EXPORT_FUNCTION_TIMEOUT_MS);
	assertEquals(EXPORT_FUNCTION_TIMEOUT_MS - EXPORT_WALL_CLOCK_BUDGET_MS, 30_000);
	assertEquals(EXPORT_WALL_CLOCK_BUDGET_MS, 120_000);
	assertEquals(EXPORT_FUNCTION_TIMEOUT_MS, 150_000);
});

Deno.test('parseContentRangeTotal — a total is read, and everything else is unknown', () => {
	assertEquals(parseContentRangeTotal('0-999/1212'), 1212);
	assertEquals(parseContentRangeTotal('0-0/1'), 1);
	assertEquals(parseContentRangeTotal('*/0'), 0);
	assertEquals(parseContentRangeTotal('items 0-9/100'), 100);
	assertEquals(parseContentRangeTotal('0-999/ 1212 '), 1212, 'the tail is trimmed');
	assertEquals(parseContentRangeTotal('0-999/0012'), 12, 'leading zeros are still digits');
	// Every countless or unparseable form. An unknown total must never be read
	// as a small one: `stream_section` compares the rows it read against this
	// figure to decide whether the section is complete, so a bogus small total
	// would certify a truncated section as whole.
	const unknown = [
		null,
		'',
		'*/*',
		'0-999/*',
		'0-999',
		'/',
		'0-999/',
		'0-999/abc',
		'0-999/12.5',
		'0-999/-12',
		'0-999/+12',
		'0-999/1 212',
		'0-999/1e3',
		'0-999/ ',
	];
	for (const header of unknown) {
		assertEquals(parseContentRangeTotal(header), null, JSON.stringify(header));
	}
});

Deno.test('parseContentRangeTotal — the LAST slash is the separator', () => {
	// PostgREST's own form has one slash, but reading from the first would turn
	// any prefixed form into an unparseable one, which reads as "unknown total"
	// and quietly stops the completeness check working at all.
	assertEquals(parseContentRangeTotal('bytes 0-999/1212'), 1212);
	assertEquals(parseContentRangeTotal('a/b/1212'), 1212);
	assertEquals(parseContentRangeTotal('0-999/12/34'), 34);
});

Deno.test('the page size is PostgREST\'s own ceiling, so a full page is also the server\'s cap', () => {
	assertEquals(EXPORT_PAGE_SIZE, 1000);
});

Deno.test('pooledPipeline — a nonsense width still runs everything, exactly once, in order', async () => {
	// `Math.trunc(concurrency) || 1` is the only guard, so 0, a fraction under
	// one and NaN all have to land on a working pipeline rather than on a pool
	// of zero workers that returns having consumed nothing.
	const widths = [0, -5, 0.5, Number.NaN, 1, 3, 1000];
	for (const width of widths) {
		const items = [0, 1, 2, 3, 4, 5, 6];
		const consumed: number[] = [];
		await pooledPipeline(
			items,
			width,
			(item: number) => Promise.resolve(item * 2),
			(_item: number, loaded: number) => {
				consumed.push(loaded);
				return Promise.resolve();
			},
		);
		assertEquals(consumed, [0, 2, 4, 6, 8, 10, 12], `width ${width}`);
	}
});

Deno.test('pooledPipeline — an absent payload is skipped without stranding its successors', async () => {
	// `loaded != null` covers both null and undefined, and a missing object is
	// the normal case on this path: a run whose track was deleted, a photo the
	// bucket no longer has. Its turn still has to be released or every later
	// item waits forever.
	const items = [0, 1, 2, 3];
	const consumed: number[] = [];
	await pooledPipeline(
		items,
		2,
		(item: number) => Promise.resolve(item % 2 === 0 ? null : item),
		(_item: number, loaded: number) => {
			consumed.push(loaded);
			return Promise.resolve();
		},
	);
	assertEquals(consumed, [1, 3]);
});

Deno.test('pooledPipeline — the concurrency constant is the documented six', () => {
	assertEquals(EXPORT_FETCH_CONCURRENCY, 6);
});
