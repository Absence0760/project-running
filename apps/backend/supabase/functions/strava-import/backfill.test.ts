// Every way the Strava page walk can stop, and what the caller is told about
// each. `complete` is the field the two clients grade a sync on, so an exit
// that never reaches the return statement is an exit the flag cannot describe.

import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import type { DbClient } from '../_shared/database.ts';
import { backfill } from './backfill.ts';

interface DbStubOptions {
	stravaIds?: string[];
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

function page(n: number, size: number, sportType = 'Ride'): FakeActivity[] {
	return Array.from({ length: size }, (_, i) => ({
		id: n * 1000 + i,
		sport_type: sportType,
		start_date: new Date(Date.UTC(2026, 0, 1 + n) + i * 60_000).toISOString(),
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

// The two exits `complete` cannot describe, because neither reaches the
// return statement. A DNS failure or a dropped TLS handshake throws out of
// `fetch`; an HTML error page from anything in front of Strava throws out of
// `resp.json()`. Both propagate past `handleSync` into `withSentry`, which
// answers 500 `internal_error` — so every activity the walk had already
// ingested is in the database and absent from the report. These two tests pin
// the behaviour as it stands; see the commit that follows.
Deno.test('a thrown fetch mid-walk escapes the walk entirely', async () => {
	await withFetch(
		(_u, i) => {
			if (i === 1) throw new TypeError('error sending request');
			return json(page(1, 50, 'Run'));
		},
		async () => {
			await assertRejects(
				() => backfill(dbStub({ stravaIds: ['1000'] }), 'u1', 'tok', 90),
				TypeError,
			);
		},
	);
});

Deno.test('a body that is not JSON at all escapes the walk entirely', async () => {
	await withFetch(
		() => new Response('<html>502</html>', { status: 200, headers: { 'Content-Type': 'text/html' } }),
		async () => {
			await assertRejects(() => backfill(dbStub(), 'u1', 'tok', 90), SyntaxError);
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
