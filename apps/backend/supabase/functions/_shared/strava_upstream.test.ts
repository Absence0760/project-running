/// What the Strava helpers do with an answer from Strava, and with the
/// database reads the dedupe depends on.
///
/// `strava.test.ts` covers `buildTrackFromStreams` and
/// `strava_sport_filter.test.ts` the sport allowlist; `ingest_activity.test.ts`
/// covers the insert. Three exported helpers between them had nothing:
/// `fetchStravaActivity`, whose three-state answer decides whether a webhook
/// returns 500 (Strava RETRIES the delivery) or 200 (Strava DROPS it forever);
/// `isAlreadyImported`, the per-provider dedupe read; and `gzipBytes`, which
/// every uploaded track passes through.
///
/// Run with `cd apps/backend && deno test --no-check --allow-read --allow-env
/// supabase/functions/_shared/strava_upstream.test.ts`.

import { assert, assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	fetchStravaActivity,
	gzipBytes,
	isAlreadyImported,
	uploadTrack,
} from './strava.ts';

function stubFetch(responder: (url: string, init?: RequestInit) => Response) {
	const original = globalThis.fetch;
	const calls: Array<{ url: string; init?: RequestInit }> = [];
	globalThis.fetch = ((url: string | URL | Request, init?: RequestInit) => {
		calls.push({ url: String(url), init });
		return Promise.resolve(responder(String(url), init));
	}) as typeof fetch;
	return { calls, restore: () => { globalThis.fetch = original; } };
}

function silenceWarn(): () => void {
	const original = console.warn;
	console.warn = () => {};
	return () => { console.warn = original; };
}

Deno.test('fetchStravaActivity — a throttle is reported as a throttle, so the delivery is retried', async () => {
	// 429 and 503 are the two statuses that mean "ask again later". The
	// webhook maps this state to a 500 so Strava redelivers; collapsing it
	// into `not_found` would answer 200 and Strava would drop the activity
	// permanently, losing the run with no error anywhere.
	const unwarn = silenceWarn();
	for (const status of [429, 503]) {
		const { restore } = stubFetch(() => new Response('slow down', { status }));
		try {
			assertEquals(await fetchStravaActivity('tok', 1), { status: 'rate_limited' });
		} finally {
			restore();
		}
	}
	unwarn();
});

Deno.test('fetchStravaActivity — every other refusal is not_found, and never a throttle', async () => {
	// The inverse of the case above: answering `rate_limited` for a 401 would
	// make the webhook 500 forever on a revoked token, and Strava would retry
	// a delivery that can never succeed for three days.
	for (const status of [400, 401, 403, 404, 410, 500, 502]) {
		const { restore } = stubFetch(() => new Response('nope', { status }));
		try {
			assertEquals(await fetchStravaActivity('tok', 1), { status: 'not_found' }, String(status));
		} finally {
			restore();
		}
	}
});

Deno.test('fetchStravaActivity — a success carries the activity and the bearer', async () => {
	const activity = { id: 99, sport_type: 'TrailRun', distance: 21097 };
	const { calls, restore } = stubFetch(() => Response.json(activity));
	try {
		const result = await fetchStravaActivity('tok-abc', 99);
		assertEquals(result, { status: 'ok', activity });
	} finally {
		restore();
	}
	// The id reaches the path and the token reaches the header — a helper that
	// dropped either would 401 on every real call while every stubbed one
	// still passed.
	assertEquals(calls.length, 1);
	assertEquals(calls[0].url, 'https://www.strava.com/api/v3/activities/99');
	const headers = calls[0].init?.headers as Record<string, string>;
	assertEquals(headers.Authorization, 'Bearer tok-abc');
});

interface RecordedFilter {
	fn: string;
	args: unknown[];
}

function countingClient(count: number | null) {
	const filters: RecordedFilter[] = [];
	let table = '';
	// deno-lint-ignore no-explicit-any
	const builder: any = {};
	for (const fn of ['select', 'eq']) {
		builder[fn] = (...args: unknown[]) => {
			filters.push({ fn, args });
			return builder;
		};
	}
	builder.then = (onF: (v: unknown) => unknown, onR?: (e: unknown) => unknown) =>
		Promise.resolve({ count, error: null }).then(onF, onR);
	const client = {
		from: (t: string) => {
			table = t;
			return builder;
		},
	};
	// deno-lint-ignore no-explicit-any
	return { client: client as any, filters, tableOf: () => table };
}

Deno.test('isAlreadyImported — the dedupe is scoped to this user, this source and this activity', async () => {
	const { client, filters, tableOf } = countingClient(1);
	assertEquals(await isAlreadyImported(client, 'u-1', 12345), true);
	assertEquals(tableOf(), 'runs');
	// All three predicates. Losing `user_id` would let one runner's import
	// suppress another's; losing `source` would let a manual run of the same
	// id suppress the Strava one; losing the id would suppress everything.
	assertEquals(
		new Set(filters.filter((f) => f.fn === 'eq').map((f) => `${f.args[0]}=${f.args[1]}`)),
		new Set(['user_id=u-1', 'source=strava', 'metadata->>strava_id=12345']),
	);
	// A head-only exact count, so the check costs no rows.
	const select = filters.find((f) => f.fn === 'select');
	assertEquals(select?.args[1], { count: 'exact', head: true });
});

Deno.test('isAlreadyImported — an unknown count is read as not-imported, never as imported', async () => {
	// A null count is what a failed or head-less read yields. Reading it as
	// "already imported" would silently skip the activity and lose the run;
	// reading it as "not imported" costs at worst a duplicate the per-provider
	// unique key still catches.
	for (const count of [null, 0]) {
		const { client } = countingClient(count);
		assertEquals(await isAlreadyImported(client, 'u-1', 1), false, String(count));
	}
	const { client } = countingClient(2);
	assertEquals(await isAlreadyImported(client, 'u-1', 1), true);
});

Deno.test('isAlreadyImported — the activity id is compared as text, because the jsonb key is text', async () => {
	// `metadata->>strava_id` yields text. Passing the number would compare a
	// text column against a number and match nothing, so every activity would
	// re-import on every sync.
	const { client, filters } = countingClient(0);
	await isAlreadyImported(client, 'u-1', 987654321);
	const idFilter = filters.find((f) => f.args[0] === 'metadata->>strava_id');
	assert(idFilter, 'the activity-id predicate is gone');
	assertEquals(typeof idFilter.args[1], 'string');
	assertEquals(idFilter.args[1], '987654321');
});

Deno.test('gzipBytes — the bytes round-trip through a real gunzip', async () => {
	// Stated as a round trip rather than as a byte count: an implementation
	// that returned its input unchanged, or that dropped every chunk after the
	// first, satisfies any length assertion but not this.
	const original = new TextEncoder().encode(
		JSON.stringify(Array.from({ length: 2000 }, (_, i) => ({ lat: 51.5 + i / 1e5, lng: -0.1 }))),
	) as Uint8Array<ArrayBuffer>;
	const gz = await gzipBytes(original);
	assert(gz.byteLength < original.byteLength, 'a repetitive track must compress');
	assertEquals(gz[0], 0x1f, 'gzip magic byte 0');
	assertEquals(gz[1], 0x8b, 'gzip magic byte 1');
	const ds = new DecompressionStream('gzip');
	const back = new Uint8Array(
		await new Response(new Response(gz).body!.pipeThrough(ds)).arrayBuffer(),
	);
	assertEquals(back.byteLength, original.byteLength);
	assertEquals(new TextDecoder().decode(back), new TextDecoder().decode(original));
});

Deno.test('gzipBytes — an empty input still yields a valid gzip member', async () => {
	const gz = await gzipBytes(new Uint8Array(new ArrayBuffer(0)));
	assert(gz.byteLength > 0, 'an empty payload still has a gzip header and trailer');
	const ds = new DecompressionStream('gzip');
	const back = new Uint8Array(
		await new Response(new Response(gz).body!.pipeThrough(ds)).arrayBuffer(),
	);
	assertEquals(back.byteLength, 0);
});

Deno.test('uploadTrack — the object lands on the owner-scoped path the CHECK enforces', async () => {
	// `runs.track_url` carries a CHECK for `{user_id}/{run_id}.json.gz`
	// (20260621_001), and both `clip-public-track` and the export downloader
	// re-derive that exact shape before handing a path to a service-role
	// download. A writer that used a different shape would store an object
	// neither reader could ever reach.
	const uploads: Array<{ path: string; opts: unknown }> = [];
	const updates: Array<{ payload: Record<string, unknown>; id: unknown }> = [];
	// deno-lint-ignore no-explicit-any
	const supabase: any = {
		storage: {
			from: () => ({
				upload: (path: string, _blob: Blob, opts: unknown) => {
					uploads.push({ path, opts });
					return Promise.resolve({ error: null });
				},
			}),
		},
		from: () => {
			let payload: Record<string, unknown> = {};
			// deno-lint-ignore no-explicit-any
			const b: any = {};
			b.update = (p: Record<string, unknown>) => {
				payload = p;
				return b;
			};
			b.eq = (_col: string, id: unknown) => {
				updates.push({ payload, id });
				return Promise.resolve({ error: null });
			};
			return b;
		},
	};
	await uploadTrack(supabase, 'user-9', 'run-7', [{ lat: 1, lng: 2 }]);
	assertEquals(uploads.length, 1);
	assertEquals(uploads[0].path, 'user-9/run-7.json.gz');
	assertEquals(uploads[0].opts, { contentType: 'application/gzip', upsert: true });
	// And the row is pointed at the same path, keyed on the run — a writer
	// that stored the object but not the pointer loses the track silently.
	assertEquals(updates, [{ payload: { track_url: 'user-9/run-7.json.gz' }, id: 'run-7' }]);
});

Deno.test('uploadTrack — a failed upload throws rather than pointing the row at nothing', async () => {
	// The row update runs after the upload. Swallowing the upload error would
	// stamp `track_url` for an object that does not exist, and every later
	// read would 502 on a run the importer reported as successful.
	let updated = false;
	// deno-lint-ignore no-explicit-any
	const supabase: any = {
		storage: {
			from: () => ({
				upload: () => Promise.resolve({ error: { message: 'quota exceeded' } }),
			}),
		},
		from: () => {
			updated = true;
			throw new Error('the row must not be touched');
		},
	};
	const err = await uploadTrack(supabase, 'u', 'r', []).then(() => null, (e: unknown) => e);
	assert(err !== null, 'a failed upload must not resolve');
	assertEquals(updated, false);
});
