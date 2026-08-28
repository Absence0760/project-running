// Every way the Strava page walk can stop, and what the caller is told about
// each. `complete` is the field the two clients grade a sync on, so an exit
// that never reaches the return statement is an exit the flag cannot describe.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import {
	backfill,
	nextWalkWindow,
	parseSyncCursor,
	serialiseSyncCursor,
	type WalkWindow,
} from './backfill.ts';

interface DbStubOptions {
	stravaIds?: string[];
	syncCursor?: string | null;
	onIntegrationsUpdate?: (patch: Record<string, unknown>) => void;
}

function dbStub(opts: DbStubOptions = {}): DbClient {
	// deno-lint-ignore no-explicit-any
	const chain = (result: unknown): any => ({
		select: () => chain(result),
		eq: () => chain(result),
		order: () => chain(result),
		range: () => chain(result),
		maybeSingle: () => Promise.resolve(result),
		// deno-lint-ignore no-explicit-any
		then: (res: any, rej: any) => Promise.resolve(result).then(res, rej),
	});
	return {
		from(table: string) {
			if (table === 'user_settings') return chain({ data: null, error: null });
			if (table === 'runs') {
				return {
					select: (cols: string) =>
						chain({
							data: cols.includes('metadata')
								? (opts.stravaIds ?? []).map((id) => ({ metadata: { strava_id: id } }))
								: [],
							error: null,
						}),
				};
			}
			return {
				select: () => chain({ data: { sync_cursor: opts.syncCursor ?? null }, error: null }),
				update: (patch: Record<string, unknown>) => {
					opts.onIntegrationsUpdate?.(patch);
					return chain({ data: null, error: null });
				},
			};
		},
	} as unknown as DbClient;
}

interface FakeActivity {
	id: number;
	sport_type: string;
	start_date: string;
	distance: number;
}

const DAY_MS = 86400_000;
/// Anchored inside the default 90-day window, because a page of activities
/// older than the floor the walk asked for cannot narrow it.
const WINDOW_BASE_MS = Date.now() - 60 * DAY_MS;
const pageStartMs = (n: number, i: number) => WINDOW_BASE_MS + n * DAY_MS + i * 60_000;
const epochS = (ms: number) => Math.floor(ms / 1000);
/// A cursor left by an earlier default-lookback walk that got one day short.
const resumePoint = (): WalkWindow => ({
	from: epochS(Date.now() - 90 * DAY_MS),
	after: epochS(Date.now() - DAY_MS),
	before: null,
});

/// Page `n` of a walk, oldest activity first — the order Strava returns when
/// `after` is set.
function page(n: number, size: number, sportType = 'Ride'): FakeActivity[] {
	return Array.from({ length: size }, (_, i) => ({
		id: n * 1000 + i,
		sport_type: sportType,
		start_date: new Date(pageStartMs(n, i)).toISOString(),
		distance: 5000,
	}));
}

/// Swap `globalThis.fetch` for `responder` for the duration of `run`, and
/// report every URL the walk asked for.
async function withFetch(
	responder: (url: string, callIndex: number) => Response | Promise<Response>,
	run: (urls: string[]) => Promise<void>,
): Promise<void> {
	const urls: string[] = [];
	const original = globalThis.fetch;
	globalThis.fetch = ((input: string | URL | Request) => {
		const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
		urls.push(url);
		return Promise.resolve(responder(url, urls.length - 1));
	}) as typeof fetch;
	try {
		await run(urls);
	} finally {
		globalThis.fetch = original;
	}
}

const json = (body: unknown, status = 200) =>
	new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

Deno.test('an empty first page is the end of the window', async () => {
	await withFetch(() => json([]), async () => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, true);
		assertEquals(r.rate_limited, false);
	});
});

Deno.test('a short page is the end of the window', async () => {
	await withFetch(() => json(page(1, 3)), async (urls) => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, true);
		assertEquals(urls.length, 1);
	});
});

Deno.test('a 429 truncates and says so', async () => {
	await withFetch(() => json({ message: 'Rate Limit Exceeded' }, 429), async () => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, false);
		assertEquals(r.rate_limited, true);
	});
});

Deno.test('an upstream 500 truncates without claiming a throttle', async () => {
	await withFetch(() => json({}, 500), async () => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, false);
		assertEquals(r.rate_limited, false);
	});
});

Deno.test('a body that is not an array truncates', async () => {
	await withFetch(() => json({ message: 'unexpected' }), async () => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, false);
	});
});

Deno.test('the 20-page cap truncates after exactly 20 fetches', async () => {
	await withFetch((_u, i) => json(page(i + 1, 50)), async (urls) => {
		const r = await backfill(dbStub(), 'u1', 'tok', 90);
		assertEquals(r.complete, false);
		assertEquals(urls.length, 20);
	});
});

// A transport failure is a truncation, not a crash. `fetch` rejects on
// DNS / TLS / a dropped connection and `resp.json()` on an HTML error page
// from anything in front of Strava; both used to propagate past `handleSync`
// into `withSentry`, which answers 500 `internal_error` and discards every
// count the walk had earned.
Deno.test('a thrown fetch mid-walk truncates and keeps the counts', async () => {
	await withFetch(
		(_u, i) => {
			if (i === 1) throw new TypeError('error sending request');
			return json(page(1, 50, 'Run'));
		},
		async () => {
			const r = await backfill(dbStub({ stravaIds: ['1000'] }), 'u1', 'tok', 90);
			assertEquals(r.complete, false);
			assertEquals(r.rate_limited, false);
			assertEquals(r.skipped, 1);
		},
	);
});

Deno.test('a body that is not JSON at all truncates rather than throwing', async () => {
	await withFetch(
		() => new Response('<html>502</html>', { status: 200, headers: { 'Content-Type': 'text/html' } }),
		async () => {
			const r = await backfill(dbStub(), 'u1', 'tok', 90);
			assertEquals(r.complete, false);
		},
	);
});

Deno.test('last_sync_at is stamped only when the window was walked to its end', async () => {
	const patches: Record<string, unknown>[] = [];
	await withFetch(() => json({}, 500), async () => {
		await backfill(dbStub({ onIntegrationsUpdate: (p) => patches.push(p) }), 'u1', 'tok', 90);
	});
	assertEquals(patches.length, 0);
	await withFetch(() => json([]), async () => {
		await backfill(dbStub({ onIntegrationsUpdate: (p) => patches.push(p) }), 'u1', 'tok', 90);
	});
	assertEquals(patches.length, 1);
	assert('last_sync_at' in patches[0]);
});

// ---- the resume cursor ----

Deno.test('parseSyncCursor fails closed on everything it cannot read', () => {
	assertEquals(parseSyncCursor(null), null);
	assertEquals(parseSyncCursor(''), null);
	assertEquals(parseSyncCursor('not json'), null);
	assertEquals(parseSyncCursor('[1,2]'), null);
	assertEquals(parseSyncCursor('"a string"'), null);
	// A shape from some other version of this cursor is not this one.
	assertEquals(parseSyncCursor('{"v":2,"from":100,"after":100,"before":null}'), null);
	assertEquals(parseSyncCursor('{"from":100,"after":100,"before":null}'), null);
	assertEquals(parseSyncCursor('{"v":1,"from":100,"after":"100","before":null}'), null);
	assertEquals(parseSyncCursor('{"v":1,"from":100,"after":100.5,"before":null}'), null);
	assertEquals(parseSyncCursor('{"v":1,"from":0,"after":0,"before":null}'), null);
	// A cursor whose frontier sits below its own job floor is unreadable.
	assertEquals(parseSyncCursor('{"v":1,"from":500,"after":100,"before":null}'), null);
	// An inverted window would fetch nothing and read as progress.
	assertEquals(parseSyncCursor('{"v":1,"from":100,"after":200,"before":100}'), null);
	assertEquals(parseSyncCursor('{"v":1,"from":100,"after":200,"before":200}'), null);
});

Deno.test('parseSyncCursor round-trips what serialiseSyncCursor writes', () => {
	for (
		const w of [
			{ from: 100, after: 100, before: null },
			{ from: 100, after: 300, before: 900 },
		] as WalkWindow[]
	) {
		assertEquals(parseSyncCursor(serialiseSyncCursor(w)), w);
	}
});

Deno.test('nextWalkWindow moves the floor up on an oldest-first page', () => {
	assertEquals(
		nextWalkWindow({ from: 100, after: 100, before: null }, { min: 120, max: 500, ascending: true }),
		{ from: 100, after: 500, before: null },
	);
	// A ceiling already in play survives the narrowing.
	assertEquals(
		nextWalkWindow({ from: 100, after: 100, before: 900 }, { min: 120, max: 500, ascending: true }),
		{ from: 100, after: 500, before: 900 },
	);
});

Deno.test('nextWalkWindow moves the ceiling down on a newest-first page', () => {
	assertEquals(
		nextWalkWindow({ from: 100, after: 100, before: null }, { min: 500, max: 900, ascending: false }),
		{ from: 100, after: 100, before: 500 },
	);
});

Deno.test('nextWalkWindow refuses a cursor that would not narrow the window', () => {
	// No page walked at all.
	assertEquals(nextWalkWindow({ from: 100, after: 100, before: null }, null), null);
	// Oldest-first, but every activity sat at or below the floor we asked for.
	assertEquals(
		nextWalkWindow({ from: 500, after: 500, before: null }, { min: 100, max: 500, ascending: true }),
		null,
	);
	// Newest-first, but nothing sat below the ceiling we asked for.
	assertEquals(
		nextWalkWindow({ from: 100, after: 100, before: 500 }, { min: 500, max: 900, ascending: false }),
		null,
	);
	// Oldest-first walk that already reached the ceiling: the remainder is empty.
	assertEquals(
		nextWalkWindow({ from: 100, after: 100, before: 500 }, { min: 200, max: 500, ascending: true }),
		null,
	);
});

Deno.test('the page cap records where it stopped', async () => {
	const patches: Record<string, unknown>[] = [];
	await withFetch((_u, i) => json(page(i + 1, 50)), async () => {
		const r = await backfill(
			dbStub({ onIntegrationsUpdate: (p) => patches.push(p) }),
			'u1',
			'tok',
			90,
		);
		assertEquals(r.complete, false);
		assertEquals(r.resumable, true);
	});
	assertEquals(patches.length, 1);
	assert(!('last_sync_at' in patches[0]));
	const cursor = parseSyncCursor(patches[0].sync_cursor);
	assert(cursor !== null);
	// Page 20's newest activity, since `page()` emits each page oldest-first.
	assertEquals(cursor.after, epochS(pageStartMs(20, 49)));
	assertEquals(cursor.before, null);
});

Deno.test('a stored cursor narrows the next walk to what is left', async () => {
	const resume = resumePoint();
	const stored = serialiseSyncCursor(resume);
	await withFetch(() => json([]), async (urls) => {
		const r = await backfill(dbStub({ syncCursor: stored }), 'u1', 'tok', 90);
		assertEquals(r.complete, true);
		assertEquals(r.resumable, false);
	});
	await withFetch(() => json([]), async (urls) => {
		await backfill(dbStub({ syncCursor: stored }), 'u1', 'tok', 90);
		assert(urls[0].includes(`after=${resume.after}`), urls[0]);
	});
});

Deno.test('a walk that finishes clears the cursor and stamps last_sync_at', async () => {
	const patches: Record<string, unknown>[] = [];
	await withFetch(() => json(page(1, 3)), async () => {
		const r = await backfill(
			dbStub({
				syncCursor: serialiseSyncCursor(resumePoint()),
				onIntegrationsUpdate: (p) => patches.push(p),
			}),
			'u1',
			'tok',
			90,
		);
		assertEquals(r.complete, true);
		assertEquals(r.resumable, false);
	});
	assertEquals(patches.length, 1);
	assertEquals(patches[0].sync_cursor, null);
	assert('last_sync_at' in patches[0]);
});

Deno.test('a request reaching further back than the cursor ignores it', async () => {
	// The cursor's floor is one day ago; the caller asked for a year. Honouring
	// the cursor would answer a narrower question than the one asked.
	const oneDayAgo = Math.floor((Date.now() - 86400_000) / 1000);
	await withFetch(() => json([]), async (urls) => {
		const r = await backfill(
			dbStub({ syncCursor: serialiseSyncCursor({ from: oneDayAgo, after: oneDayAgo, before: null }) }),
			'u1',
			'tok',
			365,
		);
		assertEquals(r.complete, true);
		const asked = Number(urls[0].match(/after=(\d+)/)?.[1]);
		assert(asked < oneDayAgo, `${asked} should reach further back than ${oneDayAgo}`);
	});
});

Deno.test('a throttle on the first page records no cursor and claims no resume', async () => {
	const patches: Record<string, unknown>[] = [];
	await withFetch(() => json({}, 429), async () => {
		const r = await backfill(
			dbStub({ onIntegrationsUpdate: (p) => patches.push(p) }),
			'u1',
			'tok',
			90,
		);
		assertEquals(r.rate_limited, true);
		assertEquals(r.resumable, false);
	});
	assertEquals(patches.length, 0);
});

Deno.test('a throttle after resuming keeps the cursor it could not advance', async () => {
	const patches: Record<string, unknown>[] = [];
	await withFetch(() => json({}, 429), async () => {
		const r = await backfill(
			dbStub({
				syncCursor: serialiseSyncCursor(resumePoint()),
				onIntegrationsUpdate: (p) => patches.push(p),
			}),
			'u1',
			'tok',
			90,
		);
		assertEquals(r.resumable, true);
	});
	assertEquals(patches.length, 0);
});

Deno.test('a newest-first page walks the ceiling down', async () => {
	const patches: Record<string, unknown>[] = [];
	// A genuine newest-first walk: page 1 is the newest, page 20 the oldest.
	await withFetch((_u, i) => json(page(20 - i, 50).slice().reverse()), async () => {
		await backfill(dbStub({ onIntegrationsUpdate: (p) => patches.push(p) }), 'u1', 'tok', 90);
	});
	const cursor = parseSyncCursor(patches[0].sync_cursor);
	assert(cursor !== null);
	// Page 20 of the walk holds the oldest activities, and its oldest is the
	// frontier when the list runs newest-first.
	assertEquals(cursor.before, epochS(pageStartMs(1, 0)));
});

// The whole point of the cursor: "sync again to finish" has to be an
// instruction that can succeed. Before it, the walk restarted at page 1 with
// `after` recomputed, so a runner whose window held more than 1000 activities
// re-skipped the same 1000 and hit the cap again, forever.
Deno.test('a second sync gets past the 20-page cap', async () => {
	const corpus = Array.from({ length: 1250 }, (_, i) => ({
		id: i,
		sport_type: 'Ride',
		start_date: new Date(WINDOW_BASE_MS + i * 3600_000).toISOString(),
		distance: 5000,
	}));
	const serve = (url: string): Response => {
		const q = new URL(url).searchParams;
		const after = Number(q.get('after'));
		const beforeRaw = q.get('before');
		const before = beforeRaw === null ? null : Number(beforeRaw);
		const pageNo = Number(q.get('page'));
		const size = Number(q.get('per_page'));
		const inWindow = corpus.filter((a) => {
			const t = epochS(Date.parse(a.start_date));
			return t > after && (before === null || t < before);
		});
		return json(inWindow.slice((pageNo - 1) * size, pageNo * size));
	};

	let cursor: string | null = null;
	const record = (p: Record<string, unknown>) => {
		if ('sync_cursor' in p) cursor = p.sync_cursor as string | null;
	};

	let first: Awaited<ReturnType<typeof backfill>> | null = null;
	await withFetch(serve, async () => {
		first = await backfill(dbStub({ onIntegrationsUpdate: record }), 'u1', 'tok', 90);
	});
	assertEquals(first!.complete, false);
	assertEquals(first!.resumable, true);
	assert(cursor !== null);

	const secondUrls: string[] = [];
	let second: Awaited<ReturnType<typeof backfill>> | null = null;
	await withFetch(serve, async (urls) => {
		second = await backfill(
			dbStub({ syncCursor: cursor, onIntegrationsUpdate: record }),
			'u1',
			'tok',
			90,
		);
		secondUrls.push(...urls);
	});
	assertEquals(second!.complete, true);
	assertEquals(second!.resumable, false);
	// It resumed rather than restarting: the 1000th activity is behind it.
	assert(
		Number(new URL(secondUrls[0]).searchParams.get('after')) >=
			epochS(Date.parse(corpus[999].start_date)),
		secondUrls[0],
	);
	// And the resume walked the remaining 250 in five full pages plus the empty
	// one that ends the window.
	assertEquals(secondUrls.length, 6);
	assertEquals(cursor, null);
});
