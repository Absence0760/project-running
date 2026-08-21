import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { EXPORT_PAGE_SIZE, parseContentRangeTotal } from './paging.ts';

Deno.test('the page size matches PostgREST db-max-rows', () => {
	// Asking for more per request buys nothing — the server clamps to
	// this and says so nowhere.
	assertEquals(EXPORT_PAGE_SIZE, 1000);
});

Deno.test('parseContentRangeTotal reads the total and refuses the countless forms', () => {
	assertEquals(parseContentRangeTotal('0-999/1212'), 1212);
	assertEquals(parseContentRangeTotal('*/0'), 0);
	assertEquals(parseContentRangeTotal('0-999/*'), null);
	assertEquals(parseContentRangeTotal(null), null);
	assertEquals(parseContentRangeTotal('garbage'), null);
});

Deno.test('every multi-row read in the export walks pages', async () => {
	// The bug this guards: a bare `.select().eq()` — or a `.limit(5000)`,
	// which PostgREST clamps to db-max-rows just the same — returns the
	// first 1000 rows and says so nowhere, so the archive is short and
	// the manifest asserts it is whole.
	const src = await Deno.readTextFile(new URL('./index.ts', import.meta.url));
	// `.select(` narrows to the PostgREST reads; the Storage client
	// reaches `.from(` too, and its list walk pages on its own terms.
	const chains = (src.match(/\.from\('[a-z_]+'\)[\s\S]*?;/g) ?? [])
		.filter((chain) => chain.includes('.select('));
	assertEquals(chains.length >= 5, true, `found only ${chains.length} table reads`);
	for (const chain of chains) {
		const singleRow = chain.includes('.limit(1)');
		const paged = chain.includes('.range(');
		assertEquals(singleRow || paged, true, `unpaged read: ${chain.slice(0, 60)}`);
	}
	// The raw-REST table walk builds its own window rather than going
	// through the query builder.
	assertEquals(src.includes('&limit=${limit}&offset=${offset}'), true);
});

Deno.test('paging.ts no longer offers a per-section row ceiling', async () => {
	// The ceiling existed only because the archive was assembled in
	// memory; the streaming sink removed the reason for it, and leaving
	// the constant around would invite a caller to reintroduce a bound
	// with no remaining justification. The wall clock is the only bound
	// (export_budget.ts).
	const src = await Deno.readTextFile(new URL('./paging.ts', import.meta.url));
	assertEquals(src.includes('EXPORT_ROW_CEILING'), false);
	assertEquals(src.includes('ceiling'), true, 'the removal should still be explained');
});
