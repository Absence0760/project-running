// Track-blob decoder used by the export-data handler. Extracted from
// index.ts so the gzip-bomb guard can be unit tested without pulling
// the whole serve() / Supabase / zipjs surface into Deno's type
// checker.
//
// audit/edge-functions (May 2026) flagged that the function ran
// DecompressionStream + JSON.parse on the full download blob with
// no cap on the gzipped byte count. clip-public-track had already
// hardened the same pattern; this brings export-data in line.

// Real tracks compress to ~50 KB at typical GPS density; even a
// 10-hour run is under 200 KB. Anything north of 5 MB is either
// pathological or an attempt to chain gzip + JSON.parse into a
// memory amplifier on the EF instance (~250 MB heap budget).
// Matches the cap used by clip-public-track.
export const MAX_TRACK_GZIP_BYTES = 5 * 1024 * 1024;

export class TrackTooLargeError extends Error {
	constructor() {
		super('track too large');
		this.name = 'TrackTooLargeError';
	}
}

/// The blob decoded to something that is not a list of points.
///
/// Thrown for the same reason `TrackTooLargeError` is: the GPX loop's
/// `catch` is what tolerates one unreadable object, and the return type
/// promised an array that `JSON.parse` had no obligation to produce. An
/// object decoded here reached `buildGpx`'s `for…of`, whose TypeError
/// escaped the loop's guard (`track.length < 2` is false for `undefined`)
/// and failed the WHOLE export on one bad blob.
export class TrackShapeError extends Error {
	constructor() {
		super('track is not a list of points');
		this.name = 'TrackShapeError';
	}
}

export interface TrackPoint {
	lat: number;
	lng: number;
	t?: number;
	ele?: number;
	bpm?: number;
}

export async function decodeTrack(blob: Blob): Promise<TrackPoint[]> {
	// Tracks are gzipped JSON arrays. Storage's download() returns the
	// raw bytes; we gunzip in-process.
	const gz = new Uint8Array(await blob.arrayBuffer());
	if (gz.byteLength > MAX_TRACK_GZIP_BYTES) {
		// Throw rather than return [] so the caller's try/catch in
		// the GPX-build loop counts this as a skipped run instead of
		// a silent empty track. Worker / Edge Function failure modes
		// must be observable.
		throw new TrackTooLargeError();
	}
	const ds = new (globalThis as { DecompressionStream: typeof DecompressionStream })
		.DecompressionStream('gzip');
	const stream = new Response(gz).body!.pipeThrough(ds);
	const txt = await new Response(stream).text();
	const parsed: unknown = JSON.parse(txt);
	if (!Array.isArray(parsed)) throw new TrackShapeError();
	return parsed as TrackPoint[];
}
