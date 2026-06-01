/// Gunzip a Blob using the browser-native `DecompressionStream` — no new
/// dependency. Returns `null` (never throws) when decompression fails, so
/// callers can degrade gracefully instead of dropping the work item.
///
/// Modern Strava exports gzip the inner GPX/TCX (`.gpx.gz`). On a browser
/// without `DecompressionStream` (old Safari) or on a corrupt member, the
/// import must still persist the row trackless rather than silently skip
/// it while the caller counts it as imported (the phantom-import bug —
/// persona round-5 theme F / intermediate).
export async function gunzipBlob(blob: Blob): Promise<Blob | null> {
	const Ctor = (globalThis as { DecompressionStream?: typeof DecompressionStream })
		.DecompressionStream;
	if (!Ctor) return null;
	try {
		const buf = await blob.arrayBuffer();
		const stream = new Response(buf).body!.pipeThrough(new Ctor('gzip'));
		return await new Response(stream).blob();
	} catch (_) {
		return null;
	}
}
