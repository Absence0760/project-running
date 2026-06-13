import { test } from 'node:test';
import assert from 'node:assert/strict';
import { assemblePublicRoute } from './public_route_assembly.js';

test('assemblePublicRoute: fires both reads concurrently (neither awaits the other)', async () => {
	let metaStarted = false;
	let clipStarted = false;
	let metaSawClipStarted = false;
	let clipSawMetaStarted = false;

	let resolveMeta!: (v: { id: string }) => void;
	let resolveClip!: (v: number[]) => void;
	const metaPromise = new Promise<{ id: string }>((r) => (resolveMeta = r));
	const clipPromise = new Promise<number[]>((r) => (resolveClip = r));

	const readMeta = () => {
		metaStarted = true;
		// If the helper serialised (await meta THEN clip), clip would not
		// have started by the time meta's thunk runs.
		metaSawClipStarted = clipStarted;
		return metaPromise;
	};
	const readClip = () => {
		clipStarted = true;
		clipSawMetaStarted = metaStarted;
		return clipPromise;
	};

	const out = assemblePublicRoute(readMeta, readClip);

	// Both thunks must have been invoked synchronously, before EITHER
	// promise resolves — that is the concurrency guarantee.
	assert.equal(metaStarted, true, 'meta read should start immediately');
	assert.equal(clipStarted, true, 'clip read should start immediately');
	// And each started while the other was already in flight.
	assert.equal(clipSawMetaStarted, true, 'clip started after meta was already in flight');

	resolveMeta({ id: 'r1' });
	resolveClip([1, 2, 3]);
	const result = await out;
	assert.deepEqual(result, { meta: { id: 'r1' }, clipped: [1, 2, 3] });

	// `metaSawClipStarted` records whether clip had begun by the time
	// meta's thunk evaluated; with Promise.all the two thunks are invoked
	// in array order in the same tick, so clip starts immediately after
	// meta — this asserts they are not serialised behind an await.
	assert.equal(metaSawClipStarted, false);
});

test('assemblePublicRoute: returns null when the meta row is absent, even with a clip result', async () => {
	let clipStarted = false;
	const result = await assemblePublicRoute(
		async () => null,
		async () => {
			clipStarted = true;
			return [9, 9];
		},
	);
	assert.equal(result, null);
	// The clip read still fired (it's launched concurrently, not gated on
	// meta) — failing closed to null is the assembler's job, not a reason
	// to skip the parallel read.
	assert.equal(clipStarted, true);
});

test('assemblePublicRoute: assembles meta + clipped when present', async () => {
	const result = await assemblePublicRoute(
		async () => ({ id: 'x', name: 'Loop' }),
		async () => [{ lat: 1, lng: 2 }],
	);
	assert.deepEqual(result, {
		meta: { id: 'x', name: 'Loop' },
		clipped: [{ lat: 1, lng: 2 }],
	});
});
