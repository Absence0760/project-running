// Regression tests for the gzip-bomb guard added to export-data's
// decodeTrack helper. audit/edge-functions (May 2026) flagged that
// the function ran DecompressionStream + JSON.parse on the full
// download blob with no cap on the gzipped byte count, mirroring
// the pattern clip-public-track had already hardened against.

import {
	assertEquals,
	assertRejects,
} from 'https://deno.land/std@0.224.0/assert/mod.ts';
import {
	MAX_TRACK_GZIP_BYTES,
	TrackShapeError,
	TrackTooLargeError,
	decodeTrack,
} from './decode_track.ts';

async function gzipString(s: string): Promise<Uint8Array> {
	const cs = new (globalThis as { CompressionStream: typeof CompressionStream })
		.CompressionStream('gzip');
	const stream = new Response(s).body!.pipeThrough(cs);
	return new Uint8Array(await new Response(stream).arrayBuffer());
}

Deno.test('decodeTrack — small valid track round-trips', async () => {
	const points = [
		{ lat: 51.5, lng: -0.1, t: 0 },
		{ lat: 51.51, lng: -0.11, t: 1 },
	];
	const gz = await gzipString(JSON.stringify(points));
	const blob = new Blob([gz as BlobPart]);
	const decoded = await decodeTrack(blob);
	assertEquals(decoded.length, 2);
	assertEquals(decoded[0].lat, 51.5);
});

Deno.test('decodeTrack — bytes at exactly the cap are accepted', async () => {
	// This case is named for the boundary and used to assert only the constant,
	// which a decoder rejecting every track at any size also satisfies. Building
	// exactly MAX bytes of VALID gzip is brittle, so the boundary is observed the
	// other way round: a blob of exactly the cap must get PAST the guard and fail
	// in the decompressor instead. That distinguishes `>` from `>=` — which is
	// the whole content of "at exactly the cap" — without needing the payload to
	// be well formed.
	const atCap = new Blob([new Uint8Array(MAX_TRACK_GZIP_BYTES)]);
	const err = await decodeTrack(atCap).then(() => null, (e: unknown) => e);
	assertEquals(err instanceof TrackTooLargeError, false, 'the cap must be exclusive');
	assertEquals(err !== null, true, 'and the bytes are still not a track');
	assertEquals(MAX_TRACK_GZIP_BYTES, 5 * 1024 * 1024);
});

Deno.test(
	'decodeTrack — gzipped bytes > cap throws TrackTooLargeError',
	async () => {
		// Don't actually allocate 5 MB of valid gzip data — fake it with
		// raw bytes the same size as MAX + 1. The cap is checked first,
		// before the DecompressionStream sees the bytes, so the content
		// doesn't have to be valid gzip.
		const bin = new Uint8Array(MAX_TRACK_GZIP_BYTES + 1);
		const blob = new Blob([bin]);
		await assertRejects(
			() => decodeTrack(blob),
			TrackTooLargeError,
			'track too large',
		);
	},
);

Deno.test(
	'decodeTrack — error type is named so callers can distinguish ' +
		'oversize from other JSON failures',
	() => {
		const err = new TrackTooLargeError();
		assertEquals(err.name, 'TrackTooLargeError');
		assertEquals(err instanceof TrackTooLargeError, true);
		assertEquals(err.message, 'track too large');
	},
);

Deno.test('a blob that decodes to something other than a list is refused', async () => {
	// The return type promised `TrackPoint[]`; `JSON.parse` promised nothing.
	// An object reached the GPX renderer's `for…of` — and the caller's guard
	// (`track.length < 2`) is false for `undefined`, so the TypeError escaped
	// the per-run tolerance and failed the WHOLE export on one bad blob.
	// Throwing puts it back inside the caller's `catch`, which skips the run.
	for (const payload of ['{}', '{"points":[]}', 'null', '42', '"a"', 'true']) {
		const blob = new Blob([await gzipString(payload) as BlobPart]);
		const err = await decodeTrack(blob).then(() => null, (e: unknown) => e);
		assertEquals(
			err instanceof TrackShapeError,
			true,
			`${payload} decoded without a refusal`,
		);
	}
});

Deno.test('a real list of points still decodes, so the refusal is not blanket', async () => {
	// The positive control beside the negative above: an empty array and a
	// populated one are both lists and must both come back.
	const empty = new Blob([await gzipString('[]') as BlobPart]);
	assertEquals(await decodeTrack(empty), []);
	const two = new Blob([
		await gzipString(JSON.stringify([{ lat: 1, lng: 2 }, { lat: 3, lng: 4 }])) as BlobPart,
	]);
	assertEquals((await decodeTrack(two)).length, 2);
});
