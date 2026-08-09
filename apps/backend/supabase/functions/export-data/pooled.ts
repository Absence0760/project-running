// Bounded-concurrency fetch pipeline for the export builders.
//
// The Art 20 export issues one REST call per personal-data table (61 of
// them) and one Storage download per run track, per HR sidecar, per
// photo and per orphaned object — up to ~5,000 round trips on a deep
// history. Run serially against the 150 s function budget that is not
// slow, it is a data-portability path the runner can never complete.
//
// `load` runs `concurrency`-wide so the round trips overlap. `consume`
// runs strictly one at a time in input order: the zip writer is a
// single stream, and entry order has to stay deterministic. A worker
// therefore holds its payload only while it waits for its turn, which
// caps live payloads at `concurrency` — that bound is what keeps the
// sweep inside the function's memory ceiling, so it is part of the
// contract, not an implementation detail.

/// 6 concurrent fetches. The budget is memory, not the wire: the
/// `run-photos` bucket caps an object at 10 MB (migration
/// `20260620_001`) and a run track at 5 MB gzipped
/// (`MAX_TRACK_GZIP_BYTES`), so 6 in flight is at most ~60 MB of
/// transient buffers alongside the archive the zip writer is
/// accumulating in memory. 6 is also the classic per-host connection
/// ceiling, well under anything Storage rate-limits.
export const EXPORT_FETCH_CONCURRENCY = 6;

export async function pooledPipeline<T, R>(
	items: readonly T[],
	concurrency: number,
	load: (item: T, index: number) => Promise<R | null>,
	consume: (item: T, loaded: R, index: number) => Promise<void>,
): Promise<void> {
	const n = items.length;
	if (n === 0) return;

	const release: Array<() => void> = new Array(n);
	const turn: Array<Promise<void>> = new Array(n);
	for (let i = 0; i < n; i++) {
		turn[i] = new Promise<void>((resolve) => {
			release[i] = resolve;
		});
	}

	let claimed = 0;
	let failed = false;
	let failure: unknown;
	const fail = (e: unknown) => {
		if (!failed) {
			failed = true;
			failure = e;
		}
	};

	const width = Math.max(1, Math.min(Math.trunc(concurrency) || 1, n));
	const workers: Promise<void>[] = [];
	for (let w = 0; w < width; w++) {
		workers.push((async () => {
			for (;;) {
				const i = claimed++;
				if (i >= n) return;
				let loaded: R | null = null;
				try {
					loaded = await load(items[i], i);
				} catch (e) {
					fail(e);
				}
				// Every index below i is claimed before i is, and every
				// claimed index releases in the `finally`, so this chain
				// always drains — waiting on the predecessor cannot cycle.
				if (i > 0) await turn[i - 1];
				try {
					if (loaded != null) await consume(items[i], loaded, i);
				} catch (e) {
					fail(e);
				} finally {
					release[i]();
				}
			}
		})());
	}

	await Promise.all(workers);
	if (failed) throw failure;
}
