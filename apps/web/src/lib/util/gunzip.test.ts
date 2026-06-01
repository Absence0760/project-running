import { test } from 'node:test';
import assert from 'node:assert/strict';
import { gunzipBlob } from './gunzip';

// Build a valid gzip member from arbitrary bytes using the same
// browser-native CompressionStream the runtime has.
async function gzip(text: string): Promise<Blob> {
	const stream = new Response(text).body!.pipeThrough(new CompressionStream('gzip'));
	return await new Response(stream).blob();
}

test('gunzipBlob — round-trips a valid gzip member', async () => {
	const original = '<gpx>...track...</gpx>';
	const compressed = await gzip(original);
	const out = await gunzipBlob(compressed);
	assert.notEqual(out, null);
	assert.equal(await out!.text(), original);
});

test('gunzipBlob — returns null (no throw) on non-gzip garbage', async () => {
	// This is the phantom-import path: a corrupt / non-gzip body must
	// degrade to null so the caller imports the row trackless rather than
	// skipping it while still counting it as imported.
	const garbage = new Blob([Uint8Array.from([0x00, 0x01, 0x02, 0x03, 0x04])]);
	const out = await gunzipBlob(garbage);
	assert.equal(out, null);
});

test('gunzipBlob — returns null on an empty blob', async () => {
	const out = await gunzipBlob(new Blob([]));
	assert.equal(out, null);
});
