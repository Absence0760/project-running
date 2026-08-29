import { assert, assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { EXPORT_FETCH_CONCURRENCY, pooledPipeline } from './pooled.ts';

function deferred(): { promise: Promise<void>; resolve: () => void } {
	let resolve!: () => void;
	const promise = new Promise<void>((r) => {
		resolve = r;
	});
	return { promise, resolve };
}

const sleep = (ms: number) => new Promise<void>((r) => setTimeout(r, ms));

Deno.test('pooledPipeline overlaps loads up to the width and never beyond it', async () => {
	const items = Array.from({ length: 40 }, (_, i) => i);
	let inFlight = 0;
	let peak = 0;
	await pooledPipeline(
		items,
		6,
		async (i) => {
			inFlight++;
			if (inFlight > peak) peak = inFlight;
			await sleep(1);
			inFlight--;
			return i;
		},
		async () => {},
	);
	assertEquals(peak, 6, 'the pool must actually reach its configured width');
	assertEquals(inFlight, 0);
});

Deno.test('pooledPipeline holds at most `concurrency` loaded payloads at once', async () => {
	// The memory bound is the reason the width is small: a worker that
	// has downloaded its bytes keeps them alive only until its turn to
	// write. If this ever exceeds the width, a 6-wide sweep of 10 MB
	// photos stops fitting in the function's memory ceiling.
	const items = Array.from({ length: 30 }, (_, i) => i);
	let live = 0;
	let peakLive = 0;
	await pooledPipeline(
		items,
		4,
		async (i) => {
			await sleep(i % 3);
			live++;
			if (live > peakLive) peakLive = live;
			return i;
		},
		async () => {
			await sleep(1);
			live--;
		},
	);
	assertEquals(peakLive, 4);
	assertEquals(live, 0);
});

Deno.test('pooledPipeline consumes in input order despite out-of-order loads', async () => {
	// Zip entry order has to be deterministic, so completion order must
	// not leak into the archive.
	const items = [0, 1, 2, 3, 4, 5, 6, 7];
	const consumed: number[] = [];
	await pooledPipeline(
		items,
		4,
		async (i) => {
			await sleep(items.length - i);
			return i;
		},
		async (_item, loaded) => {
			consumed.push(loaded);
		},
	);
	assertEquals(consumed, items);
});

Deno.test('pooledPipeline is faster than the serial loop it replaces', async () => {
	const items = Array.from({ length: 36 }, (_, i) => i);
	const perItemMs = 10;
	let loaded = 0;
	let consumed = 0;
	const started = Date.now();
	await pooledPipeline(items, 6, async () => {
		await sleep(perItemMs);
		loaded++;
		return 1;
	}, async () => {
		consumed++;
	});
	const elapsed = Date.now() - started;
	const serial = items.length * perItemMs;
	// A speed claim on its own is satisfied by a pipeline that skipped the
	// work: the fastest possible implementation of this loop is one that
	// never calls anything. Assert the work first, then the clock.
	assertEquals(loaded, items.length, 'every item must still be loaded');
	assertEquals(consumed, items.length, 'every load must still be consumed');
	assert(
		elapsed < serial / 2,
		`36 x ${perItemMs}ms at width 6 took ${elapsed}ms; the serial loop is ${serial}ms`,
	);
});

Deno.test('pooledPipeline skips consume for a null load and still drains', async () => {
	const items = [0, 1, 2, 3, 4, 5];
	const consumed: number[] = [];
	await pooledPipeline(
		items,
		3,
		async (i) => (i % 2 === 0 ? i : null),
		async (_item, loaded) => {
			consumed.push(loaded);
		},
	);
	assertEquals(consumed, [0, 2, 4]);
});

Deno.test('pooledPipeline reports the first failure without stranding the pool', async () => {
	const items = [0, 1, 2, 3, 4, 5, 6, 7];
	const consumed: number[] = [];
	await assertRejects(
		() =>
			pooledPipeline(
				items,
				3,
				async (i) => i,
				async (_item, loaded) => {
					if (loaded === 2) throw new Error('zip add failed');
					consumed.push(loaded);
				},
			),
		Error,
		'zip add failed',
	);
	// Everything that could still be written was written — a stalled
	// turn-chain would have hung the whole pipeline instead.
	assertEquals(consumed, [0, 1, 3, 4, 5, 6, 7]);
});

Deno.test('pooledPipeline handles an empty list and a width above the item count', async () => {
	let calls = 0;
	await pooledPipeline([], 6, async () => {
		calls++;
		return 1;
	}, async () => {});
	assertEquals(calls, 0);

	const gate = deferred();
	const consumed: number[] = [];
	const run = pooledPipeline(
		[7, 8],
		64,
		async (i) => {
			await gate.promise;
			return i;
		},
		async (_item, loaded) => {
			consumed.push(loaded);
		},
	);
	gate.resolve();
	await run;
	assertEquals(consumed, [7, 8]);
});

Deno.test('EXPORT_FETCH_CONCURRENCY stays inside the function memory budget', () => {
	// 6 x the 10 MB run-photos object cap = ~60 MB of transient buffers
	// on top of the archive being accumulated in memory. Raising this
	// without re-deriving that budget is how the export starts OOMing
	// instead of timing out.
	assertEquals(EXPORT_FETCH_CONCURRENCY, 6);
});

// --- Source guards: the export builders must go through the pool ---
//
// The builders talk to Storage + PostgREST through the live clients, so
// the round-trip count can't be observed in a unit test. These read
// index.ts as text and pin the shape, the same way delete-account's
// wiring.test.ts guards its handler.

const indexSource = Deno.readTextFileSync(new URL('./index.ts', import.meta.url));

Deno.test('no export loop awaits a Storage download inside a bare for-of', () => {
	// Reason: every one of these was a serial N+1 — 5,000 runs meant
	// 5,000 sequential downloads, which does not fit the 150 s budget.
	// An empty offender list is also what an empty file produces, and an
	// unreadable or renamed index.ts is the likelier of the two: pin that the
	// scan saw the loops it polices and a download to police them for.
	assert(
		/await .*\.download\(/.test(indexSource),
		'index.ts awaits no Storage download at all — this guard is scanning the wrong file',
	);
	const lines = indexSource.split('\n');
	const offenders: string[] = [];
	let loops = 0;
	let loopDepth = 0;
	let braceDepthAtLoop = 0;
	let braces = 0;
	for (const line of lines) {
		if (loopDepth > 0 && braces <= braceDepthAtLoop) loopDepth = 0;
		if (/^\s*for \(const .+ of /.test(line)) {
			loops++;
			loopDepth = 1;
			braceDepthAtLoop = braces;
		}
		braces += (line.match(/\{/g) ?? []).length - (line.match(/\}/g) ?? []).length;
		if (loopDepth > 0 && /await .*\.(download|list)\(/.test(line)) {
			offenders.push(line.trim());
		}
		if (loopDepth > 0 && /await fetchBackupTable\(/.test(line)) {
			offenders.push(line.trim());
		}
	}
	assertEquals(
		offenders,
		[],
		`Serial Storage/REST fetch inside a for-of loop: ${offenders.join(' | ')}. ` +
			'Route it through pooledPipeline instead.',
	);
	assert(loops > 0, 'the scan found no for-of loop to police');
});

Deno.test('every fetch sweep in index.ts uses the shared width', () => {
	const uses = indexSource.match(/pooledPipeline\(/g) ?? [];
	assert(
		uses.length >= 7,
		`expected the table, gpx, track, hr, photo, avatar and orphan sweeps to be pooled; found ${uses.length}`,
	);
	const widths = indexSource.match(/^\s*EXPORT_FETCH_CONCURRENCY,$/gm) ?? [];
	assertEquals(
		widths.length,
		uses.length,
		'every pooledPipeline call must pass EXPORT_FETCH_CONCURRENCY, not an ad-hoc width',
	);
});

Deno.test('listAllObjects pages by the rows it received, not by the requested limit', () => {
	// Reason: 5,000 objects at 100 per page is 50 sequential list calls.
	// Raising the page size only pays off if the loop tolerates a server
	// that returns fewer rows than asked — advancing the offset by the
	// requested limit would silently skip objects out of the export.
	const start = indexSource.indexOf('async function listAllObjects');
	assert(start >= 0, 'listAllObjects not found — renamed?');
	const body = indexSource.slice(start, indexSource.indexOf('\nasync function', start + 1));
	assert(
		/offset \+= entries\.length/.test(body),
		'listAllObjects must advance its offset by the number of rows returned.',
	);
	assert(
		/entries\.length === 0/.test(body),
		'listAllObjects must terminate on an empty page, not on a short one.',
	);
	assert(
		!/const pageSize = 100\b/.test(body),
		'listAllObjects must not page a multi-thousand-object folder 100 at a time.',
	);
});
