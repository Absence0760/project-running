import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { EXPORT_PAGE_SIZE, fetchAllPages, parseContentRangeTotal } from './paging.ts';

/// A server holding `n` rows that clamps every response to PostgREST's
/// `db-max-rows`, exactly as Supabase does — including clamping a
/// larger client-supplied limit.
function clampedServer(n: number, cap = EXPORT_PAGE_SIZE, countOn = true) {
	const calls: Array<[number, number]> = [];
	const fetchPage = (offset: number, limit: number) => {
		calls.push([offset, limit]);
		const take = Math.min(limit, cap);
		return Promise.resolve({
			rows: Array.from(
				{ length: Math.max(0, Math.min(take, n - offset)) },
				(_, i) => offset + i,
			),
			total: countOn && offset === 0 ? n : null,
		});
	};
	return { calls, fetchPage };
}

Deno.test('fetchAllPages — a 2400-row table is read whole, not capped at one page', async () => {
	const { calls, fetchPage } = clampedServer(2400);
	const out = await fetchAllPages(fetchPage);
	assertEquals(out.rows.length, 2400);
	assertEquals(out.total, 2400);
	assertEquals(out.complete, true);
	assertEquals(calls.length, 3);
	assertEquals(calls[0], [0, 1000]);
	assertEquals(calls[2], [2000, 1000]);
});

Deno.test('fetchAllPages — an exact multiple of the page size costs one more empty page', async () => {
	const { calls, fetchPage } = clampedServer(2000);
	const out = await fetchAllPages(fetchPage);
	assertEquals(out.rows.length, 2000);
	assertEquals(out.complete, true);
	assertEquals(calls.length, 3);
});

Deno.test('fetchAllPages — a single short page needs no second call', async () => {
	const { calls, fetchPage } = clampedServer(7);
	const out = await fetchAllPages(fetchPage);
	assertEquals(out.rows.length, 7);
	assertEquals(out.total, 7);
	assertEquals(out.complete, true);
	assertEquals(calls.length, 1);
});

Deno.test('fetchAllPages — a failed page keeps the rows read but never claims completeness', async () => {
	const { fetchPage } = clampedServer(2400);
	const out = await fetchAllPages((offset, limit) => offset === 0 ? fetchPage(offset, limit) : Promise.resolve(null));
	assertEquals(out.rows.length, 1000);
	assertEquals(out.total, 2400);
	assertEquals(out.complete, false);
});

Deno.test('fetchAllPages — a first-page failure yields nothing and is not complete', async () => {
	const out = await fetchAllPages(() => Promise.resolve(null));
	assertEquals(out.rows.length, 0);
	assertEquals(out.total, 0);
	assertEquals(out.complete, false);
});

Deno.test('fetchAllPages — the ceiling truncates but still reports the true total', async () => {
	const { fetchPage } = clampedServer(5000);
	const out = await fetchAllPages(fetchPage, EXPORT_PAGE_SIZE, 2000);
	assertEquals(out.rows.length, 2000);
	assertEquals(out.total, 5000);
	assertEquals(out.complete, false);
});

Deno.test('fetchAllPages — without a server count a short page still proves completeness', async () => {
	const { fetchPage } = clampedServer(1500, EXPORT_PAGE_SIZE, false);
	const out = await fetchAllPages(fetchPage);
	assertEquals(out.rows.length, 1500);
	assertEquals(out.total, 1500);
	assertEquals(out.complete, true);
});

Deno.test('fetchAllPages — a server total above the rows read forces incomplete', async () => {
	const out = await fetchAllPages((offset) =>
		Promise.resolve({
			rows: offset === 0 ? [1, 2, 3] : [],
			total: offset === 0 ? 9 : null,
		})
	);
	assertEquals(out.rows.length, 3);
	assertEquals(out.total, 9);
	assertEquals(out.complete, false);
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
