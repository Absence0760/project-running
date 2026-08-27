import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { EXPORT_PAGE_SIZE } from './paging.ts';
import { createExportBudget, EXPORT_WALL_CLOCK_BUDGET_MS } from './export_budget.ts';
import { openJsonSection, walkPages } from './stream_section.ts';

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
				(_, i) => ({ id: offset + i }),
			),
			total: countOn && offset === 0 ? n : null,
		});
	};
	return { calls, fetchPage };
}

async function drain(body: ReadableStream<Uint8Array>): Promise<string> {
	return await new Response(body).text();
}

Deno.test('an empty section opens nothing and claims to be complete', async () => {
	const { calls, fetchPage } = clampedServer(0);
	const section = await openJsonSection(fetchPage, { pageSize: 4 });
	assertEquals(section.opened, false);
	assertEquals(section.summary, { written: 0, total: 0, complete: true });
	assertEquals(calls.length, 1);
});

Deno.test('a section shorter than one page streams valid JSON', async () => {
	const { calls, fetchPage } = clampedServer(3);
	const section = await openJsonSection(fetchPage, { pageSize: 4 });
	assertEquals(section.opened, true);
	const text = await drain(section.body);
	assertEquals(JSON.parse(text), [{ id: 0 }, { id: 1 }, { id: 2 }]);
	assertEquals(section.summary, { written: 3, total: 3, complete: true });
	assertEquals(calls.length, 1);
});

Deno.test('exactly one page costs one more empty page and stays complete', async () => {
	const { calls, fetchPage } = clampedServer(4);
	const section = await openJsonSection(fetchPage, { pageSize: 4 });
	const rows = JSON.parse(await drain(section.body));
	assertEquals(rows.length, 4);
	assertEquals(section.summary.complete, true);
	assertEquals(calls.length, 2);
});

Deno.test('a multi-page section is streamed whole, never capped at one page', async () => {
	const { calls, fetchPage } = clampedServer(2400);
	const section = await openJsonSection(fetchPage, { pageSize: 1000 });
	const rows = JSON.parse(await drain(section.body));
	assertEquals(rows.length, 2400);
	assertEquals(section.summary, { written: 2400, total: 2400, complete: true });
	assertEquals(calls.length, 3);
	assertEquals(calls[0], [0, 1000]);
	assertEquals(calls[2], [2000, 1000]);
});

Deno.test('there is no per-section row ceiling any more', async () => {
	// 120,000 rows is past the old 50,000 EXPORT_ROW_CEILING. The point
	// of streaming is that the section's size no longer bounds what the
	// subject receives.
	const { fetchPage } = clampedServer(120_000);
	const section = await openJsonSection(fetchPage, { pageSize: 1000 });
	let rows = 0;
	for await (const chunk of section.body) {
		rows += (new TextDecoder().decode(chunk).match(/"id"/g) ?? []).length;
	}
	assertEquals(rows, 120_000);
	assertEquals(section.summary, { written: 120_000, total: 120_000, complete: true });
});

Deno.test('a mid-stream page failure keeps the rows read and refuses to claim completeness', async () => {
	const { fetchPage } = clampedServer(2400);
	const section = await openJsonSection(
		(offset, limit) => offset === 0 ? fetchPage(offset, limit) : Promise.resolve(null),
		{ pageSize: 1000 },
	);
	const text = await drain(section.body);
	// Still valid JSON: the array is closed even though the walk died,
	// so the archive holds a readable partial rather than a broken file.
	assertEquals(JSON.parse(text).length, 1000);
	assertEquals(section.summary, { written: 1000, total: 2400, complete: false });
});

Deno.test('a first-page failure opens nothing and is not complete', async () => {
	const section = await openJsonSection(() => Promise.resolve(null));
	assertEquals(section.opened, false);
	assertEquals(section.summary, { written: 0, total: 0, complete: false });
});

Deno.test('a server total above the rows read forces incomplete', async () => {
	const section = await openJsonSection((offset) =>
		Promise.resolve({
			rows: offset === 0 ? [{ id: 1 }, { id: 2 }, { id: 3 }] : [],
			total: offset === 0 ? 9 : null,
		}), { pageSize: 3 });
	await drain(section.body);
	assertEquals(section.summary, { written: 3, total: 9, complete: false });
});

Deno.test('without a server count a short page still proves completeness', async () => {
	const { fetchPage } = clampedServer(1500, EXPORT_PAGE_SIZE, false);
	const section = await openJsonSection(fetchPage, { pageSize: 1000 });
	await drain(section.body);
	assertEquals(section.summary, { written: 1500, total: 1500, complete: true });
});

Deno.test('the wall-clock budget stops the walk and names the section', async () => {
	const { fetchPage } = clampedServer(5000);
	let clock = 0;
	const budget = createExportBudget(10, () => clock);
	const section = await openJsonSection(fetchPage, {
		pageSize: 1000,
		budget,
		label: 'food_log',
	});
	clock = 50;
	const text = await drain(section.body);
	assertEquals(JSON.parse(text).length, 1000);
	assertEquals(section.summary, { written: 1000, total: 5000, complete: false });
	assertEquals(budget.deadlineSkipped(), ['food_log']);
});

Deno.test('shape projects each row and keep sees every row in order', async () => {
	const { fetchPage } = clampedServer(5);
	const kept: number[] = [];
	const section = await openJsonSection(fetchPage, {
		pageSize: 2,
		shape: (r) => ({ n: r.id * 10 }),
		keep: (r) => kept.push(r.id),
	});
	const rows = JSON.parse(await drain(section.body));
	assertEquals(rows, [{ n: 0 }, { n: 10 }, { n: 20 }, { n: 30 }, { n: 40 }]);
	assertEquals(kept, [0, 1, 2, 3, 4]);
});

Deno.test('walkPages reduces every page without producing an entry', async () => {
	const { calls, fetchPage } = clampedServer(2400);
	let sum = 0;
	const summary = await walkPages(fetchPage, (r) => {
		sum += r.id;
	}, { pageSize: 1000 });
	assertEquals(summary, { written: 2400, total: 2400, complete: true });
	assertEquals(sum, (2399 * 2400) / 2);
	assertEquals(calls.length, 3);
});

Deno.test('walkPages refuses to claim completeness on a failed page', async () => {
	const { fetchPage } = clampedServer(2400);
	const seen: number[] = [];
	const summary = await walkPages(
		(offset, limit) => offset === 0 ? fetchPage(offset, limit) : Promise.resolve(null),
		(r) => {
			seen.push(r.id);
		},
		{ pageSize: 1000 },
	);
	assertEquals(seen.length, 1000);
	assertEquals(summary, { written: 1000, total: 2400, complete: false });
});

Deno.test('walkPages honours the budget and names the section', async () => {
	const { fetchPage } = clampedServer(5000);
	let clock = 0;
	const budget = createExportBudget(10, () => clock);
	const first = await walkPages(fetchPage, () => {
		clock = 50;
	}, { pageSize: 1000, budget, label: 'jobs_summary' });
	assertEquals(first.complete, false);
	assertEquals(budget.deadlineSkipped(), ['jobs_summary']);
});

Deno.test('the budget leaves the platform timeout room to finalise', () => {
	assertEquals(EXPORT_WALL_CLOCK_BUDGET_MS < 150_000, true);
	const budget = createExportBudget(1000, () => 0);
	assertEquals(budget.expired(), false);
	assertEquals(budget.remainingMs(), 1000);
	assertEquals(budget.deadlineSkipped(), []);
});

Deno.test('a section opened past the deadline is shed, not read', async () => {
	const { calls, fetchPage } = clampedServer(50);
	const budget = createExportBudget(0, () => 1);
	const section = await openJsonSection(fetchPage, { pageSize: 10, budget, label: 'gym_sets' });
	assertEquals(section.opened, false);
	assertEquals(section.summary.complete, false);
	assertEquals(calls.length, 0, 'not even the count query should be spent');
	assertEquals(budget.deadlineSkipped(), ['gym_sets']);
});
